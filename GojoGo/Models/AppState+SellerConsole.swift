import SwiftUI

// MARK: - The seller's own side of the shop (Phase 5 · M1 + M2)
//
// The economy sibling of the restaurant dashboard: a shop's settings, its
// catalog, the orders waiting to be posted, its promotions and its money. It
// talks only to `/v1/economy/sellers/mine/**`, which resolves the shop from the
// caller's token — so nothing here carries a shop id, and nothing here can be
// pointed at somebody else's shop by editing a request.

/// What a product save produced. The product itself, because a digital one is
/// not finished until an asset is attached to its id, and that id does not
/// exist until the create returns.
enum ShopProductSaveResult {
    case saved(ShopProductDTO)
    case failed(String)

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

extension AppState {

    func openSellerConsole() {
        showSellerConsole = true
    }

    func closeSellerConsole() {
        showSellerConsole = false
    }

    /// Everything the console renders, in one pass. The five reads are
    /// independent and are made to fail independently: a shop whose promotions
    /// call fell over still shows its orders, because the orders are the part
    /// somebody is waiting on.
    func refreshSellerConsole() async {
        guard backendConnected, isSeller else { return }
        sellerConsoleLoading = myShop == nil
        defer { sellerConsoleLoading = false }
        do {
            myShop = try await ShopStore.shared.mySeller()
        } catch {
            showEconomyNotice(Self.message(
                from: error, fallback: "Couldn't load your shop."))
            return
        }
        async let products = try? await ShopStore.shared.myProducts()
        async let orders = try? await ShopStore.shared.sellerOrders()
        async let promos = try? await ShopStore.shared.promotions()
        async let wallet = try? await ShopStore.shared.sellerWallet()
        let (loadedProducts, loadedOrders, loadedPromos, loadedWallet) =
            await (products, orders, promos, wallet)
        withAnimation(.easeOut(duration: 0.2)) {
            myShopProducts = loadedProducts ?? myShopProducts
            shopOrderQueue = loadedOrders ?? shopOrderQueue
            shopPromotions = loadedPromos ?? shopPromotions
            shopWallet = loadedWallet ?? shopWallet
        }
    }

    // MARK: Shop settings

    /// Saves the shop's name, logo and shipping rules. Returns nil on success.
    func saveShopSettings(_ body: ShopSellerBody) async -> String? {
        do {
            myShop = try await ShopStore.shared.updateSeller(body)
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't save those settings.")
        }
    }

    // MARK: Catalog

    /// Creates or edits a product. The same body posts both ways, variants
    /// included — a variant missing from the list is retired server-side rather
    /// than deleted, because order lines point at it forever.
    ///
    /// Returns the saved product rather than just a success flag, because a
    /// digital one has a second step that needs its id: a licence-key product
    /// created and never given its generator is a product that takes money and
    /// delivers nothing.
    func saveShopProduct(_ productId: UUID?, _ body: ShopProductBody) async -> ShopProductSaveResult {
        do {
            let product = productId == nil
                ? try await ShopStore.shared.createProduct(body)
                : try await ShopStore.shared.updateProduct(productId!, body)
            withAnimation(.easeOut(duration: 0.2)) {
                if let index = myShopProducts.firstIndex(where: { $0.id == product.id }) {
                    myShopProducts[index] = product
                } else {
                    myShopProducts.insert(product, at: 0)
                }
                // The buyer's catalog is looking at the same row.
                if let index = shopProducts.firstIndex(where: { $0.id == product.id }) {
                    shopProducts[index] = product
                }
                if browsingShopProduct?.id == product.id { browsingShopProduct = product }
            }
            return .saved(product)
        } catch {
            return .failed(Self.message(from: error, fallback: "Couldn't save that product."))
        }
    }

    /// Takes a product off the shelf, or puts it back. Optimistic — the badge
    /// the seller just tapped is the whole point of the tap — and reverted with
    /// the server's own sentence when it is refused.
    func setShopProductActive(_ productId: UUID, _ active: Bool) {
        guard let index = myShopProducts.firstIndex(where: { $0.id == productId }) else { return }
        let previous = myShopProducts[index]
        Task {
            do {
                let product = try await ShopStore.shared.setProductActive(productId, active)
                withAnimation(.ggSnappy) {
                    if let index = myShopProducts.firstIndex(where: { $0.id == productId }) {
                        myShopProducts[index] = product
                    }
                    // An inactive product must leave the buyer's catalog.
                    if product.active {
                        if !shopProducts.contains(where: { $0.id == productId }) {
                            shopProducts.insert(product, at: 0)
                        }
                    } else {
                        shopProducts.removeAll { $0.id == productId }
                    }
                }
            } catch {
                withAnimation(.ggSnappy) {
                    if let index = myShopProducts.firstIndex(where: { $0.id == productId }) {
                        myShopProducts[index] = previous
                    }
                }
                showEconomyNotice(Self.message(
                    from: error, fallback: "Couldn't change that product."))
            }
        }
    }

    /// Attaches the file (or the licence generator) a digital product delivers.
    /// A digital product with nothing attached sells something the buyer cannot
    /// then be given, so the console says so on the row until this has run.
    func attachDigitalAsset(to productId: UUID, data: Data?, fileName: String,
                            contentType: String, licenseKeys: Bool) async -> String? {
        do {
            if licenseKeys {
                try await ShopStore.shared.attachLicenseAsset(to: productId)
            } else {
                guard let data else { return "Pick a file first." }
                try await ShopStore.shared.uploadDigitalAsset(
                    data, fileName: fileName, contentType: contentType, to: productId)
            }
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't attach that file.")
        }
    }

    // MARK: The order queue

    /// Marks an order posted. The note is what the buyer reads on their own
    /// order — a tracking number, a courier, "left with your neighbour".
    func shipShopOrder(_ orderId: UUID, note: String) {
        Task {
            do {
                let order = try await ShopStore.shared.ship(
                    orderId, trackingNote: note.trimmingCharacters(in: .whitespacesAndNewlines))
                applySellerOrder(order)
            } catch {
                showEconomyNotice(Self.message(from: error, fallback: "Couldn't mark that shipped."))
            }
        }
    }

    /// The seller's cancel — refunds the buyer in full, whoever asked for it.
    func cancelShopOrderAsSeller(_ orderId: UUID) {
        Task {
            do {
                let order = try await ShopStore.shared.cancelAsSeller(orderId)
                applySellerOrder(order)
                shopWallet = try? await ShopStore.shared.sellerWallet()
            } catch {
                showEconomyNotice(Self.message(from: error, fallback: "Couldn't cancel that order."))
            }
        }
    }

    private func applySellerOrder(_ order: ShopOrderDTO) {
        withAnimation(.easeOut(duration: 0.2)) {
            if let index = shopOrderQueue.firstIndex(where: { $0.id == order.id }) {
                shopOrderQueue[index] = order
            }
            if let index = shopOrders.firstIndex(where: { $0.id == order.id }) {
                shopOrders[index] = order
            }
        }
    }

    // MARK: Promotions

    func createShopPromotion(_ body: ShopPromotionBody) async -> String? {
        do {
            let promotion = try await ShopStore.shared.createPromotion(body)
            withAnimation(.easeOut(duration: 0.2)) { shopPromotions.insert(promotion, at: 0) }
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't create that promotion.")
        }
    }

    /// Deactivation, never deletion: a redemption points at it forever, and a
    /// row that disappears takes an order's discount line with it.
    func deactivateShopPromotion(_ promotionId: UUID) {
        Task {
            do {
                try await ShopStore.shared.deactivatePromotion(promotionId)
                shopPromotions = (try? await ShopStore.shared.promotions()) ?? shopPromotions
            } catch {
                showEconomyNotice(Self.message(
                    from: error, fallback: "Couldn't end that promotion."))
            }
        }
    }

    // MARK: Reviews

    func replyToShopReview(_ reviewId: UUID, body: String) async -> String? {
        do {
            let review = try await ShopStore.shared.replyToReview(reviewId, body: body)
            withAnimation(.easeOut(duration: 0.2)) {
                if let index = shopProductReviews.firstIndex(where: { $0.id == review.id }) {
                    shopProductReviews[index] = review
                }
            }
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't post that reply.")
        }
    }
}
