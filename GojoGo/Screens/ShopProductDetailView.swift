import SwiftUI

// MARK: - A product page (Phase 5 · M1 + M2)
//
// The variant picker is the whole screen, really. A product has no price of its
// own — every price and every stock count belongs to a variant — so nothing on
// this page can be bought until one is chosen, and the button says which.
//
// Three refusals are shown *before* the tap rather than after it. A sold-out
// variant is unbuyable and says so on its own chip; a basket that already
// belongs to another shop (or to the other side of the digital/physical line)
// explains itself in the button's own place, because the alternative is a
// notice appearing over a tap the buyer thought had worked; and your own
// product has no buy bar at all, because the server would refuse that order
// after an address and a promo code had been typed into it.
//
// The add itself is *shown*. This page covers the whole screen, so the basket
// bar that grows on the Economy tab is invisible from here — an add used to be
// a haptic tick and nothing else, which reads as a dead button.

struct ShopProductDetailView: View {
    @EnvironmentObject var app: AppState

    let product: ShopProductDTO

    @State private var selectedVariantID: UUID?
    @State private var quantity: Int = 1
    @State private var showAllReviews = false
    /// Non-nil for a couple of seconds after an add lands: drives the receipt
    /// above the bar and the tick on the button.
    @State private var addedAt: Date?
    @State private var addedResetTask: Task<Void, Never>?

    private var live: ShopProductDTO { app.browsingShopProduct ?? product }

    private var isMine: Bool { app.isOwnShopProduct(live) }

    private var justAdded: Bool { addedAt != nil }

    private var selected: ShopVariantDTO? {
        live.variants.first { $0.id == selectedVariantID }
            ?? live.variants.first(where: \.inStock)
            ?? live.variants.first
    }

    /// Only ever a *basket* refusal now — ownership is answered by the bar
    /// itself, which is a different screen rather than a sentence over the
    /// same one.
    private var refusal: String? { isMine ? nil : app.basketRefusal(for: live) }

    var body: some View {
        ZStack(alignment: .top) {
            GGColor.sheetBG.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    gallery
                    header
                    if isMine { ownerBanner }
                    variantPicker
                    if let specs = Self.readable(live.specs) {
                        block(title: "Details", body: specs)
                    }
                    if let description = Self.readable(live.description) {
                        block(title: "About", body: description)
                    }
                    reviews
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 18)
                .padding(.top, 66)
            }

            closeBar
        }
        .safeAreaInset(edge: .bottom) { buyBar }
        .onAppear { selectedVariantID = live.variants.first(where: \.inStock)?.id }
        .onDisappear { addedResetTask?.cancel() }
    }

    /// The seller's own product. Says so where the price and the stock are,
    /// because that is where somebody looking at their own shelf is looking.
    private var ownerBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "storefront")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("This is your product")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text("This is how buyers see it. You can't buy from your own shop.")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 16, tint: GGColor.ink(0.07))
    }

    // MARK: Gallery

    private var gallery: some View {
        Group {
            if live.imageUrls.isEmpty {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(GGColor.ink(0.06))
                    .frame(height: 280)
                    .overlay {
                        Image(systemName: live.isDigital ? "arrow.down.doc" : "shippingbox")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(GGColor.textTertiary)
                    }
            } else {
                TabView {
                    ForEach(live.imageUrls, id: \.self) { url in
                        MediaImage(url: url, cornerRadius: 22)
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 280)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(live.sellerName.uppercased())
                    .font(.ggMono(10, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(GGColor.textTertiary)
                if live.isDigital {
                    Text("DOWNLOAD")
                        .font(.ggMono(9, .bold))
                        .tracking(0.8)
                        .foregroundStyle(GGColor.onAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(GGColor.white))
                }
                Spacer(minLength: 0)
            }
            Text(live.name)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            HStack(spacing: 10) {
                if let rating = live.averageRating, live.ratingCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                        Text(String(format: "%.1f", rating))
                            .font(.ggMono(12, .semibold))
                        Text("(\(live.ratingCount))")
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                    .foregroundStyle(GGColor.textSecondary)
                }
                if let brand = live.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Variants

    private var variantPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if live.variants.count > 1 {
                Text("Pick one")
                    .font(.ggMono(10, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(GGColor.textTertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(live.variants) { variant in
                        variantChip(variant)
                    }
                }
                .padding(.vertical, 2)
            }
            if let selected, selected.inStock, selected.stock <= 5 {
                // A real number, not "low stock": the count is what decides
                // whether somebody buys two now or comes back tomorrow.
                Text("\(selected.stock) left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
            }
        }
    }

    private func variantChip(_ variant: ShopVariantDTO) -> some View {
        let active = selected?.id == variant.id
        return Button {
            guard variant.inStock else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.ggSnappy) {
                selectedVariantID = variant.id
                quantity = 1
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.label)
                    .font(.system(size: 13, weight: .semibold))
                Text(variant.inStock
                     ? EconomyStore.formatPrice(cents: variant.priceCents, currency: "USD")
                     : "Sold out")
                    .font(.ggMono(11, .semibold))
                    .opacity(0.75)
            }
            .foregroundStyle(active ? GGColor.onAccent
                             : (variant.inStock ? GGColor.textPrimary : GGColor.textTertiary))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
            .overlay {
                if !variant.inStock {
                    Capsule().strokeBorder(GGColor.hairline, lineWidth: 0.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!variant.inStock)
    }

    /// Text worth putting a heading over, or nil.
    ///
    /// `specs` is stored as JSON server-side, so a product with none comes back
    /// as the string `"{}"` rather than as an empty one — and an emptiness check
    /// that only tested for `""` duly rendered a **Details** heading with two
    /// braces under it. Found on the first product ever created. The empty
    /// containers are listed rather than parsed: this is a display guard, and a
    /// JSON decode that failed would have to fall back to showing it anyway.
    static func readable(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !["{}", "[]", "null", "\"\""].contains(trimmed) else { return nil }
        return trimmed
    }

    private func block(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.ggMono(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Reviews

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reviews")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer(minLength: 0)
                if app.shopProductReviews.count > 3 {
                    Button(showAllReviews ? "Show less" : "See all") {
                        withAnimation(.ggSnappy) { showAllReviews.toggle() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .buttonStyle(.plain)
                }
            }
            if app.shopProductReviews.isEmpty {
                Text("No reviews yet. Only people who bought it can leave one.")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textTertiary)
            } else {
                ForEach(showAllReviews ? app.shopProductReviews
                        : Array(app.shopProductReviews.prefix(3))) { review in
                    ShopReviewRow(review: review)
                }
            }
        }
    }

    // MARK: Chrome

    /// The only way out of this page, which is why the tap target is the whole
    /// circle and not the glyph. An `Image` in a `frame` hit-tests to the drawn
    /// symbol unless it is given a shape of its own — so this read as a dead
    /// button for anything but a dead-centre tap, and a full-screen cover with
    /// no working exit is a trap.
    private var closeBar: some View {
        HStack {
            Button {
                app.closeShopProduct()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .glassCapsule(interactive: false)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    /// One bar, four states: yours, buyable, sold out, or refused with the
    /// reason.
    @ViewBuilder
    private var buyBar: some View {
        if isMine {
            ownerBar
        } else {
            VStack(spacing: 8) {
                if let refusal {
                    HStack(spacing: 10) {
                        Text(refusal)
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Empty") { app.emptyBasket() }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .buttonStyle(.plain)
                    }
                }
                if justAdded { addedReceipt }
                HStack(spacing: 12) {
                    if let selected, selected.inStock, !live.isDigital {
                        stepper(max: selected.stock)
                    }
                    Button {
                        add()
                    } label: {
                        HStack(spacing: 7) {
                            if justAdded {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            Text(buyLabel)
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(
                            canBuy ? GGColor.white : GGColor.ink(0.18)))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!canBuy)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
            .animation(.ggSnappy, value: justAdded)
        }
    }

    /// Proof the tap did something, and the way straight to the basket it did
    /// it to. Slides in over the bar and leaves on its own — the alternative,
    /// on a page that covers the basket bar entirely, was a button that looked
    /// broken the second time it was pressed.
    private var addedReceipt: some View {
        HStack(spacing: 10) {
            Image(systemName: "bag.fill.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Added to basket")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text("\(app.basketCount) \(app.basketCount == 1 ? "item" : "items") · \(EconomyStore.formatPrice(cents: app.basketTotalCents, currency: "USD"))")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.checkOutFromProduct()
            } label: {
                Text("Basket")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassCapsule(interactive: false)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 16, tint: GGColor.ink(0.10))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// The seller's own bar, in place of the buy one.
    private var ownerBar: some View {
        VStack(spacing: 6) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.manageOwnShopProduct()
            } label: {
                Text("Manage in your shop")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())

            Text("Stock, variants and the orders waiting on you live in your console.")
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    /// Adds, then keeps the receipt up for a couple of seconds. A second tap
    /// restarts the clock rather than stacking a second timer that would pull
    /// the receipt out from under the first.
    private func add() {
        guard let selected, selected.inStock else { return }
        guard app.addToBasket(live, variant: selected, quantity: quantity) else { return }
        addedResetTask?.cancel()
        withAnimation(.ggSnappy) { addedAt = Date() }
        addedResetTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.ggSnappy) { addedAt = nil }
        }
    }

    private var canBuy: Bool {
        guard let selected, selected.inStock, refusal == nil else { return false }
        // A licence bought twice charges twice and grants once, so the second
        // add is refused here rather than left to a notice nobody can see from
        // under a full-screen cover.
        if live.isDigital, app.shopBasket.contains(where: { $0.variantId == selected.id }) {
            return false
        }
        return true
    }

    private var buyLabel: String {
        guard let selected else { return "Unavailable" }
        guard selected.inStock else { return "Sold out" }
        guard refusal == nil else { return "In another basket" }
        // A download is one per basket, so the button stops offering to add a
        // second one and says what is true instead.
        if live.isDigital, app.shopBasket.contains(where: { $0.variantId == selected.id }) {
            return "In your basket"
        }
        if justAdded { return "Added" }
        let each = selected.priceCents * Int64(live.isDigital ? 1 : quantity)
        return "Add · \(EconomyStore.formatPrice(cents: each, currency: "USD"))"
    }

    private func stepper(max limit: Int) -> some View {
        HStack(spacing: 12) {
            stepButton("minus") { quantity = Swift.max(1, quantity - 1) }
            Text("\(quantity)")
                .font(.ggMono(15, .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(minWidth: 18)
            stepButton("plus") { quantity = Swift.min(Swift.max(1, limit), quantity + 1) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .glassCapsule(interactive: false)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.ggSnappy) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One review, with the seller's reply underneath it when there is one.
struct ShopReviewRow: View {
    let review: ShopReviewDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(review.authorName ?? "Someone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= review.rating ? "star.fill" : "star")
                            .font(.system(size: 8))
                    }
                }
                .foregroundStyle(GGColor.textSecondary)
                Spacer(minLength: 0)
                Text(BackendDate.relative(review.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }
            if let body = review.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reply = review.replyBody, !reply.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(GGColor.ink(0.18))
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Seller replied")
                            .font(.ggMono(9, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(GGColor.textTertiary)
                        Text(reply)
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 16, tint: GGColor.ink(0.04))
    }
}
