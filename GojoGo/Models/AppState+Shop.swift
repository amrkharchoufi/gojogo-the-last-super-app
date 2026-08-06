import SwiftUI

// MARK: - Shops: the merchant catalog on the phone (Phase 5 · M1 + M2)
//
// Phase 5 built four milestones of backend and no client at all, which is what
// this is: browse, a product page with variants and reviews, a basket that
// obeys the one-checkout-is-one-seller rule, an order list where "it arrived"
// is the tap that moves the money, and the digital shelf.
//
// Two rules from the server are enforced *here as well*, and both are enforced
// on the way in rather than at checkout, because a basket that can be built and
// not paid for is a basket that wasted somebody's afternoon:
//
//   1. One checkout is one seller. Adding from a second shop is refused by
//      name, with the offer to start again.
//   2. A digital line and a physical line cannot share an order — one of them
//      completes at capture and the other one weeks later, and an order has one
//      terminal moment.

extension AppState {

    // MARK: Browse

    /// Replaces the shop catalog with what the server just served.
    ///
    /// Wholesale, like `refreshSocial` and for the same reason: an answer of
    /// "nothing for sale" is an answer, and the alternative — keeping the last
    /// non-empty page — is how a deleted product keeps its card forever on one
    /// device. The one card kept back is whatever product page is open right
    /// now, so a refresh landing mid-read doesn't empty the screen under the
    /// reader.
    func refreshShops() async {
        guard backendConnected else { return }
        shopLoading = shopProducts.isEmpty
        defer { shopLoading = false }
        do {
            let page = try await ShopStore.shared.browse(category: shopCategory)
            shopNextBefore = page.nextBefore
            let servedIDs = Set(page.items.map(\.id))
            let openProduct = browsingShopProduct.flatMap {
                servedIDs.contains($0.id) ? nil : $0
            }
            withAnimation(.easeOut(duration: 0.25)) {
                shopProducts = page.items + (openProduct.map { [$0] } ?? [])
            }
        } catch {
            #if DEBUG
            print("Shops refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    func selectShopCategory(_ category: String) {
        guard shopCategory != category else { return }
        shopCategory = category
        shopNextBefore = nil
        Task { await refreshShops() }
    }

    func loadMoreShopsIfNeeded(after productID: UUID) {
        guard backendConnected,
              !shopLoadingMore,
              let cursor = shopNextBefore,
              let index = shopProducts.firstIndex(where: { $0.id == productID }),
              index >= shopProducts.count - 3 else { return }
        shopLoadingMore = true
        Task {
            defer { shopLoadingMore = false }
            do {
                let page = try await ShopStore.shared.browse(category: shopCategory, before: cursor)
                shopNextBefore = page.nextBefore
                let existing = Set(shopProducts.map(\.id))
                shopProducts.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            } catch {
                #if DEBUG
                print("Shops page load failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: The product page

    /// Opens a product and pulls its reviews behind it. The card in hand is
    /// shown immediately and replaced by the server's copy when it lands —
    /// browse carries every field the page needs, so there is no spinner over
    /// a page we can already draw.
    func openShopProduct(_ product: ShopProductDTO) {
        browsingShopProduct = product
        shopProductReviews = []
        Task {
            async let fresh = try? await ShopStore.shared.product(product.id)
            async let reviews = try? await ShopStore.shared.reviews(product.id)
            if let fresh = await fresh, browsingShopProduct?.id == product.id {
                browsingShopProduct = fresh
                if let index = shopProducts.firstIndex(where: { $0.id == fresh.id }) {
                    shopProducts[index] = fresh
                }
            }
            if browsingShopProduct?.id == product.id {
                shopProductReviews = await reviews ?? []
            }
        }
    }

    /// Opens a product by id — the route a search hit or a push takes, where
    /// there is no card in hand. A product that has gone says so rather than
    /// opening an empty page.
    func openShopProduct(id: UUID) {
        if let known = shopProducts.first(where: { $0.id == id }) {
            openShopProduct(known)
            return
        }
        Task {
            do {
                let product = try await ShopStore.shared.product(id)
                openShopProduct(product)
            } catch {
                showEconomyNotice("That product isn't available any more.")
            }
        }
    }

    func closeShopProduct() {
        browsingShopProduct = nil
        shopProductReviews = []
    }

    // MARK: The basket

    var basketSellerName: String? { shopBasket.first?.sellerName }

    var basketTotalCents: Int64 { shopBasket.reduce(0) { $0 + $1.lineTotalCents } }

    var basketCount: Int { shopBasket.reduce(0) { $0 + $1.quantity } }

    /// Why an add would be refused, or nil when it wouldn't. Asked by the
    /// product page *before* the tap, so the button can explain itself instead
    /// of failing under a finger.
    func basketRefusal(for product: ShopProductDTO) -> String? {
        guard let first = shopBasket.first else { return nil }
        if first.sellerId != product.sellerId {
            return "Your basket is from \(first.sellerName). One order is one shop — empty it to buy from \(product.sellerName)."
        }
        if first.isDigital != product.isDigital {
            return first.isDigital
                ? "Your basket has a download in it. Downloads are bought on their own."
                : "A download is bought on its own — finish this order first."
        }
        return nil
    }

    /// Adds a variant, or bumps the quantity if it is already in there. Capped
    /// at the stock the catalog reported, which is a courtesy rather than a
    /// guarantee: the placement transaction is the only thing that can actually
    /// decide whether the last one is yours.
    func addToBasket(_ product: ShopProductDTO, variant: ShopVariantDTO, quantity: Int = 1) {
        if let refusal = basketRefusal(for: product) {
            showEconomyNotice(refusal)
            return
        }
        withAnimation(.ggSnappy) {
            if let index = shopBasket.firstIndex(where: { $0.variantId == variant.id }) {
                let capped = min(shopBasket[index].quantity + quantity, max(1, variant.stock))
                shopBasket[index].quantity = capped
                shopBasket[index].stock = variant.stock
            } else {
                shopBasket.append(ShopBasketLine(
                    productId: product.id,
                    variantId: variant.id,
                    sellerId: product.sellerId,
                    sellerName: product.sellerName,
                    productName: product.name,
                    variantLabel: variant.label,
                    unitPriceCents: variant.priceCents,
                    imageURL: product.imageURL,
                    isDigital: product.isDigital,
                    quantity: min(quantity, max(1, variant.stock)),
                    stock: variant.stock))
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func setBasketQuantity(_ variantId: UUID, _ quantity: Int) {
        guard let index = shopBasket.firstIndex(where: { $0.variantId == variantId }) else { return }
        withAnimation(.ggSnappy) {
            if quantity <= 0 {
                shopBasket.remove(at: index)
            } else {
                shopBasket[index].quantity = min(quantity, max(1, shopBasket[index].stock))
            }
        }
    }

    func emptyBasket() {
        withAnimation(.ggSnappy) { shopBasket = [] }
    }

    // MARK: Checkout

    /// Places the order. Returns nil on success, or the sentence to show.
    ///
    /// Nothing is inserted locally on failure. A card that looks like an order
    /// and has no order behind it is the ghost this codebase has now written
    /// down twice — the seller never sees it, no refresh explains it, and the
    /// buyer believes they have bought something.
    func placeShopOrder(shipTo: String, promotionCode: String) async -> String? {
        guard backendConnected else { return "You're not connected — try again in a moment." }
        guard !shopBasket.isEmpty else { return "Your basket is empty." }
        let digital = shopBasket.contains(where: \.isDigital)
        let address = shipTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !digital && address.isEmpty { return "Where should this go?" }
        let code = promotionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let order = try await ShopStore.shared.checkout(ShopCheckoutBody(
                lines: shopBasket.map { ShopCheckoutLine(variantId: $0.variantId, quantity: $0.quantity) },
                shipTo: digital ? nil : address,
                promotionCode: code.isEmpty ? nil : code))
            withAnimation(.ggSnappy) {
                shopBasket = []
                shopOrders.insert(order, at: 0)
                showShopCheckout = false
                showShopOrders = true
            }
            // A digital order granted its entitlements inside the same
            // transaction that took the money, so the shelf is already right —
            // it just hasn't been read yet.
            if digital { await refreshEntitlements() }
            await refreshWallet()
            return nil
        } catch {
            return Self.message(from: error, fallback: "That order didn't go through.")
        }
    }

    // MARK: Orders

    func refreshShopOrders() async {
        guard backendConnected else { return }
        do {
            let orders = try await ShopStore.shared.myOrders()
            withAnimation(.easeOut(duration: 0.2)) { shopOrders = orders }
        } catch {
            #if DEBUG
            print("Shop orders refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// "It arrived" — the only tap in this vertical that pays somebody. No
    /// optimistic move: the row changes when the server says the money did.
    func confirmShopOrderReceived(_ orderId: UUID) {
        Task {
            do {
                let order = try await ShopStore.shared.confirmReceived(orderId)
                applyShopOrder(order)
                await refreshWallet()
            } catch {
                showEconomyNotice(Self.message(
                    from: error, fallback: "Couldn't confirm that order."))
            }
        }
    }

    func cancelShopOrder(_ orderId: UUID) {
        Task {
            do {
                let order = try await ShopStore.shared.cancelOrder(orderId)
                applyShopOrder(order)
                await refreshWallet()
            } catch {
                showEconomyNotice(Self.message(from: error, fallback: "Couldn't cancel that order."))
            }
        }
    }

    /// Leaves a verified-purchase review, then folds it into whatever product
    /// page is open. Returns nil on success.
    func reviewShopProduct(orderId: UUID, productId: UUID, rating: Int,
                           body: String) async -> String? {
        do {
            let review = try await ShopStore.shared.review(productId, ShopReviewBody(
                orderId: orderId, rating: rating,
                body: body.trimmingCharacters(in: .whitespacesAndNewlines), photoUrls: []))
            if browsingShopProduct?.id == productId {
                withAnimation(.easeOut(duration: 0.2)) {
                    shopProductReviews.removeAll { $0.authorId == review.authorId }
                    shopProductReviews.insert(review, at: 0)
                }
                // The rating average moved; the page's own copy has not.
                if let fresh = try? await ShopStore.shared.product(productId),
                   browsingShopProduct?.id == productId {
                    browsingShopProduct = fresh
                }
            }
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't post that review.")
        }
    }

    /// Settles every surface an order shows on: the buyer's list and, when the
    /// same account is the shop, the seller's queue.
    private func applyShopOrder(_ order: ShopOrderDTO) {
        withAnimation(.easeOut(duration: 0.2)) {
            if let index = shopOrders.firstIndex(where: { $0.id == order.id }) {
                shopOrders[index] = order
            }
            if let index = shopOrderQueue.firstIndex(where: { $0.id == order.id }) {
                shopOrderQueue[index] = order
            }
        }
    }

    // MARK: The digital shelf

    func refreshEntitlements() async {
        guard backendConnected else { return }
        do {
            let owned = try await ShopStore.shared.entitlements()
            withAnimation(.easeOut(duration: 0.2)) { entitlements = owned }
        } catch {
            #if DEBUG
            print("Entitlements refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Mints a fresh signed link and hands it to the system browser. Never
    /// cached: the URL expires, and a stored one is a dead button later.
    func openDownload(_ entitlement: ShopEntitlementDTO) {
        Task {
            do {
                let raw = try await ShopStore.shared.downloadURL(entitlement.id)
                guard let url = URL(string: raw) else {
                    showEconomyNotice("That download link came back malformed.")
                    return
                }
                await UIApplication.shared.open(url)
            } catch {
                showEconomyNotice(Self.message(
                    from: error, fallback: "Couldn't open that download."))
            }
        }
    }
}
