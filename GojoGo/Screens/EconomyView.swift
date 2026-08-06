import SwiftUI
import PhotosUI

struct EconomyView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var category = "All"
    @State private var nearMe = false
    @State private var underBudget = false
    @State private var chromeHidden = false
    @FocusState private var searchFocused: Bool

    /// Browse only ever shows live listings — a seller's paused or sold items
    /// stay on their own shelf, even when something seeded them into the catalog
    /// (a thread's listing card, "View in marketplace").
    private var catalog: [Product] {
        ([app.featuredProduct] + app.products)
            .filter { !$0.name.isEmpty && $0.status == .active }
    }

    private var filtered: [Product] {
        catalog.filter { p in
            let catOK = category == "All" || p.category == category
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let queryOK = q.isEmpty
                || p.name.lowercased().contains(q)
                || p.meta.lowercased().contains(q)
                || p.seller.lowercased().contains(q)
            let nearOK = !nearMe || (kilometers(of: p).map { $0 <= 3.0 } ?? true)
            let budgetOK = !underBudget || (dollars(of: p).map { $0 <= 300 } ?? true)
            return catOK && queryOK && nearOK && budgetOK
        }
    }

    private var deals: [Product] {
        Array(filtered.sorted { (dollars(of: $0) ?? 9999) < (dollars(of: $1) ?? 9999) }.prefix(8))
    }

    private var topPicks: [Product] {
        Array(filtered.filter { $0.id != app.featuredProduct.id }.prefix(8))
    }

    private func kilometers(of p: Product) -> Double? {
        Double(p.distance.replacingOccurrences(of: "km", with: "")
            .trimmingCharacters(in: .whitespaces))
    }

    private func dollars(of p: Product) -> Int? {
        let digits = p.price.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private func categoryIcon(_ name: String) -> String {
        switch name {
        case "All": return "square.grid.2x2.fill"
        case "Phones": return "iphone"
        case "Cameras": return "camera.fill"
        case "Fashion": return "tshirt.fill"
        case "Home": return "lamp.desk.fill"
        case "Sports": return "figure.run"
        default: return "tag.fill"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            GGBackground()

            // Three catalogs on one tab (Phase 5): the C2C shelf that has been
            // here since 2b M1, the merchant shops, and bookable services. They
            // share the chrome and nothing else — each owns its own scroll view,
            // so switching segments never leaves one screen's offset on another.
            switch app.economySegment {
            case .marketplace: marketplaceScroll
            case .shops:       ShopsSection(chromeHidden: $chromeHidden)
            case .services:    ServicesSection(chromeHidden: $chromeHidden)
            }

            topChrome
                .autoHideChrome(chromeHidden)

            if let notice = app.economyNotice {
                EconomyNoticeBanner(message: notice) { app.dismissEconomyNotice() }
                    .padding(.horizontal, 16)
                    // Clears the wordmark row rather than sitting on top of it.
                    .padding(.top, 108)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
            }

            // The basket rides above every segment: adding something in Shops
            // and then wandering into Services must not lose it.
            if !app.shopBasket.isEmpty, app.economySegment != .marketplace {
                basketBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, tabBarInset - 12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.ggOverlay, value: app.economyNotice)
        .animation(.ggSnappy, value: app.shopBasket.count)
        .task {
            // Each segment loads itself on first appearance; this only covers
            // the case of landing straight back on a non-default one.
            switch app.economySegment {
            case .marketplace: break
            case .shops:       await app.refreshShops()
            case .services:    await app.refreshServices()
            }
            // Whether the Transfers chip exists at all is an answer only the
            // server has, so it is asked once when the tab opens rather than
            // added to the connect chain everybody pays for.
            await app.refreshTransfers()
        }
    }

    /// What Economy has always been: the peer-to-peer shelf.
    private var marketplaceScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                locationRow
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                filterChips
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                departmentStrip
                    .padding(.top, 16)
                    .zIndex(1)

                if catalog.isEmpty {
                    GGEmptyState(
                        icon: "bag",
                        title: "No listings yet",
                        message: "Be the first to sell something nearby.",
                        actionTitle: "Sell an item",
                        action: { app.showSellSheet = true }
                    )
                    .padding(.top, 40)
                } else {
                    if !filtered.isEmpty {
                        dealBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .zIndex(0)
                    }

                    let saved = catalog.filter(\.saved)
                    if !saved.isEmpty {
                        productRail(
                            title: "Keep shopping",
                            subtitle: "From your saved list",
                            products: saved
                        )
                        .padding(.top, 22)
                    }

                    productRail(
                        title: "Today's deals",
                        subtitle: "Best prices near you",
                        products: deals
                    )
                    .padding(.top, 22)

                    productRail(
                        title: category == "All" ? "Inspired by your browsing" : "More in \(category)",
                        subtitle: "Top picks nearby",
                        products: topPicks
                    )
                    .padding(.top, 22)

                    resultsGrid
                        .padding(.horizontal, 16)
                        .padding(.top, 22)
                }

                Color.clear.frame(height: tabBarInset)
            }
            .padding(.top, 98)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await app.refreshEconomy() }
        .trackScrollChrome(hidden: $chromeHidden)
    }

    // MARK: - Chrome

    private var topChrome: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GOJOGO")
                        .font(.ggMono(11, .semibold))
                        .tracking(0.6)
                        .foregroundStyle(GGColor.textSecondary)
                    Wordmark(size: 20, trailing: "economy")
                }
                Spacer(minLength: 0)
                segmentActions
            }
            segmentPicker
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            TopScrim()
                .allowsHitTesting(false)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }

    /// The trailing chrome is per segment, because "the thing you'd want next"
    /// is: your own listings when browsing the shelf, your orders when browsing
    /// shops, your bookings when browsing services.
    @ViewBuilder
    private var segmentActions: some View {
        switch app.economySegment {
        case .marketplace:
            // Only once there is one. A transfer is a rare thing to be doing,
            // and a permanent chip for it would be chrome most people never
            // have a use for.
            if !app.transfers.isEmpty {
                chromeChip(icon: "doc.text", label: "Transfers") { app.openTransfers() }
            }
            if app.canManageListings { sellerHubButton }
            Button {
                app.showSellSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Sell")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(GGColor.onAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
        case .shops:
            if app.isSeller {
                chromeChip(icon: "storefront", label: "Your shop") { app.openSellerConsole() }
            }
            chromeChip(icon: "shippingbox", label: "Orders") {
                app.showShopOrders = true
            }
        case .services:
            if app.isServiceProvider {
                chromeChip(icon: "calendar.badge.clock", label: "Your work") {
                    app.openProviderConsole()
                }
            }
            chromeChip(icon: "calendar", label: "Bookings") {
                app.showBookings = true
            }
        }
    }

    private func chromeChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(GGColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassCapsule(interactive: false)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var segmentPicker: some View {
        HStack(spacing: 8) {
            ForEach(EconomySegment.allCases) { segment in
                let active = app.economySegment == segment
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.ggSnappy) { app.economySegment = segment }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: segment.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(segment.label)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    /// One basket, one shop — so the bar names the shop rather than a count of
    /// items, which is the fact that decides whether the next tap is allowed.
    private var basketBar: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            app.showShopCheckout = true
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bag.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(app.basketCount)")
                        .font(.ggMono(9, .bold))
                        .foregroundStyle(GGColor.white)
                        .padding(3)
                        .background(Circle().fill(GGColor.onAccent))
                        .offset(x: 8, y: -7)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Basket")
                        .font(.system(size: 14, weight: .bold))
                    if let shop = app.basketSellerName {
                        Text(shop)
                            .font(.system(size: 11))
                            .opacity(0.8)
                    }
                }
                Spacer(minLength: 0)
                Text(EconomyStore.formatPrice(cents: app.basketTotalCents, currency: "USD"))
                    .font(.ggMono(14, .semibold))
            }
            .foregroundStyle(GGColor.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Capsule().fill(GGColor.white))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        }
        .buttonStyle(PressableStyle())
    }

    /// Way into the seller's own shelf. Carries the live count so a seller can
    /// see at a glance that they still have something up, without opening it.
    private var sellerHubButton: some View {
        let live = app.sellerListings.filter { $0.status == .active }.count
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            app.openSellerHub()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 11, weight: .semibold))
                Text(live > 0 ? "Selling \(live)" : "Selling")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(GGColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassCapsule(interactive: false)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Your listings")
    }

    private var locationRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                Text("Deliver to")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                Text("Home · Casablanca")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(GGColor.textTertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            TextField("Search Economy", text: $query)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !query.isEmpty {
                Button {
                    withAnimation(.ggSnappy) { query = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(GGColor.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glass(cornerRadius: 14, fillOpacity: 0.06, borderOpacity: 0.1)
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.ggSnappy) { nearMe.toggle() }
            } label: {
                MonoChip(text: "near me", active: nearMe)
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.ggSnappy) { underBudget.toggle() }
            } label: {
                MonoChip(text: "≤ $300", active: underBudget)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Text("\(filtered.count) results")
                .font(.ggMono(11, .medium))
                .foregroundStyle(GGColor.textTertiary)
        }
    }

    // MARK: - Departments (Amazon icon strip)

    private var departmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(SampleData.economyCategories, id: \.self) { cat in
                    let active = category == cat
                    VStack(spacing: 7) {
                        Image(systemName: categoryIcon(cat))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                            .frame(width: 52, height: 52)
                            .background(
                                Circle().fill(active ? GGColor.white : GGColor.ink(0.08))
                            )
                            .overlay(
                                Circle().strokeBorder(
                                    active ? Color.clear : GGColor.ink(0.1),
                                    lineWidth: 0.5
                                )
                            )
                        Text(cat)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(active ? GGColor.textPrimary : GGColor.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(width: 64)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggSnappy) { category = cat }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Deal banner

    private var dealBanner: some View {
        let p = filtered.contains(where: { $0.id == app.featuredProduct.id })
            ? app.featuredProduct
            : (filtered.first ?? app.featuredProduct)
        return Button {
            app.openProduct(p)
        } label: {
            ZStack(alignment: .bottomLeading) {
                MediaImage(url: p.imageURL, cornerRadius: 18)
                    .frame(maxWidth: .infinity)
                    .frame(height: 168)
                    .clipped()
                    .allowsHitTesting(false)

                LinearGradient(
                    colors: [Color.black.opacity(0.82), Color.black.opacity(0.15), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 6) {
                    Text("TODAY'S DEAL")
                        .font(.ggMono(10, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text(p.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(p.price)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(GGColor.accent)
                        Text(p.condition)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
                .padding(16)
                .allowsHitTesting(false)
            }
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        // GeometryReader inside MediaImage can inflate hit testing past the
        // visual frame and steal taps from the category strip above.
        .frame(height: 168)
        .clipped()
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Horizontal rails

    private func productRail(title: String, subtitle: String, products: [Product]) -> some View {
        Group {
            if !products.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(GGColor.textPrimary)
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(GGColor.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Text("See all")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                    .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(products) { product in
                                Button { app.openProduct(product) } label: {
                                    railCard(product)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func railCard(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                MediaImage(url: product.imageURL, cornerRadius: 12)
                    .frame(width: 128, height: 128)
                saveButton(product)
                    .padding(6)
            }
            Text(product.price)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text(product.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GGColor.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 32, alignment: .topLeading)
            Text(product.distance)
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)
        }
        .frame(width: 128, alignment: .leading)
    }

    // MARK: - Results grid

    private var resultsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(query.isEmpty
                      ? (category == "All" ? "Browse all listings" : category)
                      : "Results for “\(query)”")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer(minLength: 0)
                Text("\(filtered.count)")
                    .font(.ggMono(12, .medium))
                    .foregroundStyle(GGColor.textTertiary)
            }

            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Text("No listings match those filters.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                    Text("Try widening the distance or budget.")
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 16
                ) {
                    ForEach(filtered) { product in
                        Button { app.openProduct(product) } label: {
                            gridCard(product)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func gridCard(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                MediaImage(url: product.imageURL, cornerRadius: 12)
                    .aspectRatio(1, contentMode: .fit)
                saveButton(product)
                    .padding(8)
            }
            // Amazon-style: price first, then title
            Text(product.price)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text(product.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GGColor.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 34, alignment: .topLeading)
            Text("\(product.condition) · \(product.distance)")
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveButton(_ product: Product) -> some View {
        Button {
            withAnimation(.ggSnappy) {
                app.toggleSaveProduct(product.id)
            }
        } label: {
            Image(systemName: product.saved ? "heart.fill" : "heart")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(product.saved ? Color.white : Color.white.opacity(0.95))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notice
//
// The marketplace screens move optimistically (a paused listing leaves the grid
// before the server confirms). This is how a refused edit or relist gets said
// out loud instead of silently reverting.

/// Not private: the seller hub is a sheet *over* Economy, so it has to render
/// its own copy — a banner behind a sheet is a banner nobody reads.
struct EconomyNoticeBanner: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GGColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GGColor.textTertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.10), floating: true)
    }
}

// MARK: - Product detail

struct ProductDetailView: View {
    @EnvironmentObject var app: AppState
    let productID: UUID

    private var product: Product {
        app.liveProduct(id: productID) ?? Product(name: "Listing", price: "—", gradient: SampleData.g1)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    MediaImage(url: product.imageURL, cornerRadius: 0)
                        .frame(height: 360)
                        .clipped()
                    HStack(spacing: 10) {
                        // Reporting a listing (2e M5). Not offered on your own —
                        // a seller reporting themselves is a queue item with
                        // nothing in it to decide, and the server refuses it.
                        if !EconomyStore.shared.isOwn(product.id) {
                            Menu {
                                Button(role: .destructive) {
                                    app.openReport(.listing, id: product.id, label: product.name)
                                } label: {
                                    Label("Report listing", systemImage: "flag")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.black.opacity(0.45)))
                            }
                        }
                        Button { app.closeProduct() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                        }
                    }
                    .padding(16)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(product.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(GGColor.textPrimary)
                        Spacer()
                        Text(product.price)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(GGColor.accent)
                    }

                    HStack(spacing: 8) {
                        MonoChip(text: product.category, active: true)
                        MonoChip(text: product.condition)
                        MonoChip(text: product.distance)
                    }

                    // A saved listing can go sold or come down under the buyer.
                    if product.status != .active {
                        HStack(spacing: 8) {
                            Image(systemName: product.status.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(product.status == .sold
                                 ? "Sold — this one's gone."
                                 : "Taken down by the seller for now.")
                                .font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(GGColor.textSecondary)
                        .padding(12)
                        .glass(cornerRadius: 14, tint: GGColor.ink(0.06))
                    }

                    HStack(spacing: 12) {
                        UserAvatar(size: 40, letter: String(product.seller.prefix(1)).uppercased())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.seller)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(GGColor.textPrimary)
                            Text("Verified seller · usually replies in < 1h")
                                .font(.system(size: 12))
                                .foregroundStyle(GGColor.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.1)

                    Text(product.description)
                        .font(.system(size: 15))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineSpacing(4)

                    Text("More from nearby")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(app.products.filter { $0.id != product.id }.prefix(4)) { p in
                                Button { app.openProduct(p) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        MediaImage(url: p.imageURL, cornerRadius: 14)
                                            .frame(width: 130, height: 130)
                                        Text(p.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(GGColor.textPrimary)
                                            .lineLimit(1)
                                        Text(p.price)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(GGColor.accent)
                                    }
                                    .frame(width: 130, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 110)
            }
        }
        .refreshable { await app.refreshEconomy() }
        .background(GGColor.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    withAnimation { app.toggleSaveProduct(product.id) }
                } label: {
                    Image(systemName: product.saved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(width: 52, height: 52)
                        .glassCapsule(interactive: false)
                }
                .buttonStyle(PressableStyle())

                if EconomyStore.shared.isOwn(product.id) {
                    // Your own listing — there's no one to message, so the CTA
                    // is the thing you actually came here to do.
                    Button {
                        app.manageListing(product.id)
                    } label: {
                        Text("Manage listing")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GGColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .buttonStyle(PressableStyle())
                } else if EconomyStore.shared.isTransfer(product.id) {
                    // A title changes hands here, not a parcel. Enquiring is
                    // free — the escrow comes later, once the seller has named
                    // a price — so this is a question rather than a purchase.
                    Button {
                        app.startTransfer(listingId: product.id)
                    } label: {
                        Text("Enquire · escrow")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GGColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .buttonStyle(PressableStyle())
                } else {
                    Button {
                        app.openSellerChat(for: product)
                    } label: {
                        Text("Message \(product.seller)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GGColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        // This screen is a fullScreenCover, so the root's copy cannot present
        // over it and stands down while a listing is open.
        .safetyPresentations(active: true)
    }
}

// MARK: - Seller chat

struct SellerChatView: View {
    @EnvironmentObject var app: AppState

    private var product: Product? { app.messagingProduct }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product?.seller ?? "Seller")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(product?.name ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button { app.closeSellerChat() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GGColor.textSecondary)
                        .frame(width: 32, height: 32)
                        .glassCapsule(interactive: false)
                }
            }
            .padding(16)

            if let p = product {
                HStack(spacing: 10) {
                    MediaImage(url: p.imageURL, cornerRadius: 10)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.price)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(GGColor.accent)
                        Text(p.meta)
                            .font(.system(size: 11))
                            .foregroundStyle(GGColor.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button { app.openProduct(p) } label: {
                        Text("View")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .glassCapsule(interactive: false)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.1)
                .padding(.horizontal, 16)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(app.sellerChat) { msg in
                        HStack {
                            if msg.fromUser { Spacer(minLength: 40) }
                            Text(msg.text)
                                .font(.system(size: 14))
                                .foregroundStyle(msg.fromUser ? GGColor.onAccent : GGColor.textPrimary)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(msg.fromUser ? GGColor.white : GGColor.ink(0.12))
                                )
                            if !msg.fromUser { Spacer(minLength: 40) }
                        }
                    }
                }
                .padding(16)
            }

            HStack(spacing: 10) {
                TextField("Message…", text: $app.sellerDraft)
                    .font(.system(size: 15))
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .glassCapsule(interactive: false)
                Button {
                    app.sendSellerMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(16)
        }
        .background(GGColor.bg.ignoresSafeArea())
    }
}

// MARK: - Sell sheet

struct SellListingSheet: View {
    @EnvironmentObject var app: AppState
    @State private var title = ""
    @State private var price = ""
    @State private var category = "Home"
    @State private var notes = ""
    @State private var posted = false
    @State private var publishing = false
    @State private var publishError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("List something nearby")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)

                    photoPicker

                    field("Title", text: $title)
                    field("Price", text: $price)

                    Text("Category")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SampleData.economyCategories.filter { $0 != "All" }, id: \.self) { cat in
                                Button { category = cat } label: {
                                    MonoChip(text: cat, active: category == cat)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    field("Details", text: $notes, lines: true)

                    if let publishError {
                        Text(publishError)
                            .font(.system(size: 13))
                            .foregroundStyle(GGColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }

                    // "Listed ✓" waits for the server. It used to appear on the
                    // tap itself, which said the listing was up whether or not
                    // anything had been published — and the form is kept on a
                    // failure so the seller can retry without retyping it.
                    Button {
                        guard !title.trimmingCharacters(in: .whitespaces).isEmpty,
                              !publishing, !posted else { return }
                        publishing = true
                        withAnimation { publishError = nil }
                        Task {
                            let failure = await app.createListing(
                                title: title, price: price, category: category,
                                notes: notes, imageData: photoData)
                            publishing = false
                            guard failure == nil else {
                                withAnimation { publishError = failure }
                                return
                            }
                            withAnimation { posted = true }
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            app.showSellSheet = false
                        }
                    } label: {
                        Text(publishing ? "Publishing…" : (posted ? "Listed ✓" : "Publish listing"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GGColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(GGColor.white))
                            .opacity(publishing ? 0.7 : 1)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(publishing || posted)
                }
                .padding(20)
            }
            .background(GGColor.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { app.showSellSheet = false }
                        .foregroundStyle(GGColor.textSecondary)
                }
            }
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22))
                        Text("Add a photo")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(GGColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.1)
        }
        .buttonStyle(.plain)
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, lines: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            Group {
                if lines {
                    TextField(label, text: text, axis: .vertical)
                        .lineLimit(3...6)
                } else {
                    TextField(label, text: text)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(GGColor.textPrimary)
            .padding(14)
            .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.1)
        }
    }
}
