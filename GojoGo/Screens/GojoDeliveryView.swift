import SwiftUI
import CoreLocation
import MapboxMaps

// MARK: - GojoDelivery root

struct GojoDeliveryView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            GGColor.bg.ignoresSafeArea()

            if app.deliveryStatus != nil {
                DeliveryTrackingView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
            } else if app.selectedDeliveryRestaurant != nil {
                DeliveryRestaurantView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                DeliveryBrowseView()
                    .transition(.opacity)
            }

            if let notice = app.deliveryNotice {
                DeliveryNoticeBanner(message: notice) { app.dismissDeliveryNotice() }
                    .padding(.horizontal, 16)
                    // Clears the section header / map chrome rather than
                    // sitting on top of the wordmark.
                    .padding(.top, 66)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.ggOverlay, value: app.selectedDeliveryRestaurantID)
        .animation(.ggOverlay, value: app.deliveryStatus != nil)
        .sheet(isPresented: $app.showDeliveryCheckout) {
            DeliveryCheckoutSheet()
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(GGColor.sheetBG)
        }
        .sheet(isPresented: $app.showMerchantPartner) {
            MerchantPartnerView()
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(GGColor.sheetBG)
        }
        .sheet(isPresented: $app.showDeliveryAddressSheet) {
            DeliveryAddressSheet()
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(GGColor.sheetBG)
        }
    }
}

// MARK: - Notice
//
// The delivery screens are optimistic — the tracking view opens before the
// order lands. This is how a failure (or a refused cancel) gets said out loud.

private struct DeliveryNoticeBanner: View {
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

// MARK: - Browse (delivery home)

private struct DeliveryBrowseView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                // Keep filters outside the scroll so chips stay tappable
                // (nested horizontal ScrollView + vertical ScrollView eats Button hits).
                VStack(alignment: .leading, spacing: 18) {
                    header
                    addressRow
                    searchField
                    categoryStrip
                }
                .padding(.top, 8)
                .padding(.bottom, 14)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if app.filteredDeliveryRestaurants.isEmpty {
                            emptyState
                        } else {
                            if SampleData.deliveryPromoImageURL != nil {
                                promoBanner
                            }

                            if !app.deliveryPastOrders.isEmpty {
                                orderAgainRail
                            }

                            fastestRail
                            allRestaurants
                        }

                        Color.clear.frame(height: tabBarInset + (app.deliveryCart.isEmpty ? 12 : 70))
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .refreshable { await app.refreshDelivery() }
            }

            if !app.deliveryCart.isEmpty {
                DeliveryCartBar()
                    .padding(.horizontal, 16)
                    .padding(.bottom, tabBarInset - 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.ggNav, value: app.deliveryCart.isEmpty)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GOJODELIVERY")
                    .font(.ggMono(12, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Wordmark(size: 22, trailing: "delivery")
            }
            Spacer()
            // Shown only to a restaurant's owner (restaurants are created in
            // Gojo Admin, so there is nothing here for anyone else). Beside it,
            // the courier prototype, still waiting on Phase 3 dispatch.
            MerchantHeaderButton()
            PartnerHeaderButton(role: .courier)
        }
        .padding(.horizontal, 20)
    }

    private var addressRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            app.showDeliveryAddressSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                Text("Deliver to")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                Text(app.deliveryAddressLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(GGColor.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())

    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            TextField("Restaurants, dishes, cuisines", text: $app.deliverySearch)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .autocorrectionDisabled()
            if !app.deliverySearch.isEmpty {
                Button {
                    withAnimation(.ggSnappy) { app.deliverySearch = "" }
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
        .glass(cornerRadius: 16, fillOpacity: 0.06, borderOpacity: 0.1)
        .padding(.horizontal, 16)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SampleData.deliveryCategories, id: \.name) { cat in
                    let active = app.deliveryCategory == cat.name
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggSnappy) { app.deliveryCategory = cat.name }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(cat.name)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(active ? GGColor.white : GGColor.ink(0.08))
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var promoBanner: some View {
        Group {
            if let url = SampleData.deliveryPromoImageURL {
                ZStack(alignment: .bottomLeading) {
                    MediaImage(url: url, cornerRadius: 20)
                        .frame(height: 130)
                        .overlay(
                            LinearGradient(colors: [Color.black.opacity(0.75), Color.black.opacity(0.05)],
                                           startPoint: .leading, endPoint: .trailing)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FIRST ORDER")
                            .font(.ggMono(10, .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Color.white.opacity(0.75))
                        Text("Free delivery all week")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                        Text("On orders over $10")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var orderAgainRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Order again")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(app.deliveryPastOrders) { order in
                        VStack(alignment: .leading, spacing: 6) {
                            MediaImage(url: order.imageURL, cornerRadius: 14)
                                .frame(width: 150, height: 90)
                            Text(order.restaurantName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(GGColor.textPrimary)
                                .lineLimit(1)
                            Text("\(order.dateLabel) · \(order.totalLabel)")
                                .font(.system(size: 11))
                                .foregroundStyle(GGColor.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(width: 150)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var fastestRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Fastest near you")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(app.filteredDeliveryRestaurants.sorted(by: { $0.etaMinutes < $1.etaMinutes }).prefix(4)) { r in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            app.openDeliveryRestaurant(r.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topLeading) {
                                    MediaImage(url: r.imageURL, cornerRadius: 16)
                                        .frame(width: 210, height: 120)
                                    if let promo = r.promo {
                                        promoChip(promo)
                                            .padding(8)
                                    }
                                }
                                Text(r.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(GGColor.textPrimary)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                    Text(String(format: "%.1f", r.rating))
                                        .font(.ggMono(11, .semibold))
                                    Text("· \(r.etaMinutes) min")
                                        .font(.system(size: 11))
                                        .foregroundStyle(GGColor.textTertiary)
                                }
                                .foregroundStyle(GGColor.textSecondary)
                            }
                            .frame(width: 210, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var allRestaurants: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("All restaurants")
            VStack(spacing: 14) {
                ForEach(app.filteredDeliveryRestaurants) { r in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.openDeliveryRestaurant(r.id)
                    } label: {
                        restaurantCard(r)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func restaurantCard(_ r: DeliveryRestaurant) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                MediaImage(url: r.imageURL, cornerRadius: 18)
                    .frame(height: 160)
                if let promo = r.promo {
                    promoChip(promo)
                        .padding(10)
                }
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(r.etaMinutes) min")
                            .font(.ggMono(11, .semibold))
                            .foregroundStyle(GGColor.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(GGColor.white))
                            .padding(10)
                    }
                }
            }
            .frame(height: 160)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(r.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                        Text(String(format: "%.1f (%@)", r.rating, r.reviews))
                            .font(.ggMono(11, .medium))
                    }
                    .foregroundStyle(GGColor.textSecondary)
                }
                Text("\(r.cuisine) · Delivery \(r.feeLabel == "Free" ? "free" : r.feeLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func promoChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(GGColor.onAccent)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(GGColor.white))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(GGColor.textPrimary)
            .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        GGEmptyState(
            icon: "fork.knife",
            title: app.deliveryRestaurants.isEmpty
                ? "No restaurants yet"
                : "No restaurants match that",
            message: app.deliveryRestaurants.isEmpty
                ? "Delivery partners will show up here when they're nearby."
                : nil
        )
    }
}

// MARK: - Restaurant detail

private struct DeliveryRestaurantView: View {
    @EnvironmentObject var app: AppState

    private var restaurant: DeliveryRestaurant {
        app.selectedDeliveryRestaurant
            ?? app.deliveryRestaurants.first
            ?? DeliveryRestaurant(
                name: "Restaurant", cuisine: "", rating: 0,
                reviews: "0", etaMinutes: 0, feeLabel: "—")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The reader is here for one reason: a storefront hero can carry a
            // button that points at a dish or a section, and a button that
            // scrolls to what it names is the difference between a page the
            // owner arranged and a decorative header.
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        hero
                        info
                        storefront(proxy)
                        menu
                        Color.clear.frame(height: tabBarInset + (app.deliveryCart.isEmpty ? 12 : 70))
                    }
                }
                .refreshable { await app.reloadDeliveryMenu(restaurant.id) }
            }

            if !app.deliveryCart.isEmpty {
                DeliveryCartBar()
                    .padding(.horizontal, 16)
                    .padding(.bottom, tabBarInset - 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.ggNav, value: app.deliveryCart.isEmpty)
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            MediaImage(url: restaurant.imageURL, cornerRadius: 0)
                .frame(height: 210)
                .overlay(
                    LinearGradient(colors: [Color.black.opacity(0.55), .clear, Color.black.opacity(0.45)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .ignoresSafeArea(edges: .top)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.closeDeliveryRestaurant()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .glassCapsule(tint: Color.black.opacity(0.45), interactive: false, dense: true)
            }
            .buttonStyle(PressableStyle())
            .padding(.leading, 16)
            .padding(.top, 8)
        }
        .frame(height: 210)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(restaurant.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                    Text(String(format: "%.1f (%@)", restaurant.rating, restaurant.reviews))
                        .font(.ggMono(12, .semibold))
                }
                Text("· \(restaurant.etaMinutes) min")
                    .font(.system(size: 13))
                Text("· Delivery \(restaurant.feeLabel == "Free" ? "free" : restaurant.feeLabel)")
                    .font(.system(size: 13))
            }
            .foregroundStyle(GGColor.textSecondary)

            if !restaurant.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(restaurant.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(GGColor.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(GGColor.ink(0.07)))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(restaurant.menu) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.horizontal, 20)

                    VStack(spacing: 0) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { i, item in
                            menuRow(item)
                                // Scroll targets for a storefront button. Ids
                                // are the server's, which is what lets a block
                                // authored in a console point into this list.
                                .id(item.id)
                            if i < section.items.count - 1 {
                                Divider().background(GGColor.ink(0.07))
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
                    .padding(.horizontal, 16)
                }
                .id(section.id)
            }
        }
    }

    private func menuRow(_ item: DeliveryMenuItem) -> some View {
        let qty = app.deliveryQty(of: item)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    if item.popular {
                        Text("Popular")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(GGColor.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(GGColor.white))
                    }
                }
                Text(item.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
                    .lineLimit(2)
                Text(String(format: "$%.2f", item.price))
                    .font(.ggMono(13, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer(minLength: 8)

            ZStack(alignment: .bottomTrailing) {
                MediaImage(url: item.imageURL, cornerRadius: 12)
                    .frame(width: 74, height: 74)

                if qty == 0 {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.addDeliveryItem(item, from: restaurant)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(GGColor.onAccent)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(GGColor.white))
                            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    }
                    .buttonStyle(PressableStyle())
                    .offset(x: 6, y: 6)
                } else {
                    HStack(spacing: 0) {
                        stepperButton("minus") { app.decrementDeliveryItem(item) }
                        Text("\(qty)")
                            .font(.ggMono(13, .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .frame(minWidth: 22)
                        stepperButton("plus") { app.addDeliveryItem(item, from: restaurant) }
                    }
                    .background(Capsule().fill(GGColor.surface2))
                    .overlay(Capsule().strokeBorder(GGColor.ink(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .offset(x: 6, y: 6)
                }
            }
        }
        .padding(14)
    }

    // MARK: Storefront (Phase 2e · Milestone 4)
    //
    // The page the owner arranged, rendered read-only above the menu. There is
    // no editor here and there won't be one: this is GoJoAdmin's Studio
    // contract, and iOS's whole job is to draw what it wrote — skipping, in
    // silence, any block it doesn't recognise.

    @ViewBuilder
    private func storefront(_ proxy: ScrollViewProxy) -> some View {
        if !restaurant.storefront.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(restaurant.storefront) { block in
                    switch block {
                    case .hero(let hero):   storefrontHero(hero, proxy)
                    case .rail(let rail):   storefrontRail(rail)
                    case .promo(let promo): storefrontPromo(promo)
                    case .text(let text):   storefrontText(text)
                    case .info:             storefrontInfo()
                    }
                }
            }
        }
    }

    private func storefrontHero(_ hero: StorefrontHero, _ proxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = hero.mediaURL {
                MediaImage(url: url, cornerRadius: 18)
                    .frame(height: 180)
                    .overlay(
                        LinearGradient(colors: [.clear, Color.black.opacity(0.65)],
                                       startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    )
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(GGColor.ink(0.08))
                    .frame(height: 140)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(hero.headline)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                if let subheadline = hero.subheadline {
                    Text(subheadline)
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(2)
                }
                // Both or neither — the server refuses a labelled button with
                // nowhere to go, so one check covers the pair.
                if let label = hero.ctaLabel, let target = hero.ctaTarget {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggNav) { proxy.scrollTo(target.id, anchor: .top) }
                    } label: {
                        Text(label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(GGColor.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 2)
                }
            }
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    /// A rail of dishes. Ids are resolved against the menu this screen already
    /// has, so a featured dish that sold out is simply absent — the card can
    /// never offer something checkout would refuse.
    @ViewBuilder
    private func storefrontRail(_ rail: StorefrontRail) -> some View {
        let items = rail.itemIds.compactMap(menuItem)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let title = rail.title {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.horizontal, 20)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { item in
                            railCard(item, emphasised: rail.featured)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func railCard(_ item: DeliveryMenuItem, emphasised: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                MediaImage(url: item.imageURL, cornerRadius: 0)
                    .frame(width: 152, height: 104)
                    .clipped()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    app.addDeliveryItem(item, from: restaurant)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(GGColor.white))
                        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                }
                .buttonStyle(PressableStyle())
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1)
                Text(String(format: "$%.2f", item.price))
                    .font(.ggMono(12, .semibold))
                    .foregroundStyle(GGColor.textSecondary)
            }
            .frame(width: 152, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .frame(width: 152)
        // Clip before the glass background, or the photo's square top corners
        // sit proud of the card's rounded ones.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glass(cornerRadius: 16, fillOpacity: emphasised ? 0.09 : 0.05, borderOpacity: 0.08)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            app.addDeliveryItem(item, from: restaurant)
        }
    }

    /// The block names a promotion by id and nothing else, so what is drawn is
    /// always the live offer — a banner cannot say 20% while the discount says
    /// 10%. A promotion that has ended renders nothing at all.
    @ViewBuilder
    private func storefrontPromo(_ promo: StorefrontPromo) -> some View {
        if let deal = app.deliveryPromotion(promo.promotionId, at: restaurant.id) {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(GGColor.ink(0.08)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(deal.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    if !deal.code.isEmpty {
                        Text(deal.code)
                            .font(.ggMono(11, .semibold))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                }
                Spacer(minLength: 8)

                if !deal.code.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.applyDeliveryPromotionCode(deal.code)
                        app.showDeliveryNotice("\(deal.code) applied to your order.")
                    } label: {
                        Text(app.deliveryPromotionCode == deal.code ? "Applied" : "Use")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(GGColor.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(app.deliveryPromotionCode == deal.code)
                }
            }
            .padding(14)
            .glass(cornerRadius: 16, fillOpacity: 0.06, borderOpacity: 0.08)
            .padding(.horizontal, 16)
        }
    }

    private func storefrontText(_ text: StorefrontText) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = text.title {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Text(text.body)
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)
        .padding(.horizontal, 16)
    }

    /// Everything here is read live off the restaurant. An info block that
    /// carried its own copy of the delivery fee would be wrong the day the owner
    /// changed it, which is why the server refuses one that tries.
    private func storefrontInfo() -> some View {
        HStack(spacing: 0) {
            infoTile("clock", "\(restaurant.etaMinutes) min", "Delivery")
            Divider().frame(height: 30).background(GGColor.ink(0.07))
            infoTile("bag", restaurant.feeLabel == "Free" ? "Free" : restaurant.feeLabel, "Fee")
            Divider().frame(height: 30).background(GGColor.ink(0.07))
            infoTile("star.fill", String(format: "%.1f", restaurant.rating), "\(restaurant.reviews) reviews")
        }
        .padding(.vertical, 12)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)
        .padding(.horizontal, 16)
    }

    private func infoTile(_ icon: String, _ value: String, _ caption: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            Text(value)
                .font(.ggMono(13, .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(GGColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func menuItem(_ id: UUID) -> DeliveryMenuItem? {
        for section in restaurant.menu {
            if let item = section.items.first(where: { $0.id == id }) { return item }
        }
        return nil
    }

    private func stepperButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Floating cart bar

private struct DeliveryCartBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            app.showDeliveryCheckout = true
        } label: {
            HStack(spacing: 10) {
                Text("\(app.deliveryCartCount)")
                    .font(.ggMono(13, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(GGColor.ink(0.14)))
                Text("View cart")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                Spacer()
                Text(String(format: "$%.2f", app.deliveryCartTotal))
                    .font(.ggMono(14, .semibold))
                    .foregroundStyle(GGColor.onAccent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Capsule().fill(GGColor.white))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Checkout sheet

private struct DeliveryCheckoutSheet: View {
    @EnvironmentObject var app: AppState
    /// The address sheet is presented from here rather than through AppState so
    /// it stacks over checkout instead of fighting the root view's sheet slot.
    @State private var showAddresses = false
    /// What's typed in the code field. The applied one lives in AppState —
    /// this is only what the keyboard has produced so far.
    @State private var promoCode = ""

    private var restaurant: DeliveryRestaurant? {
        guard let id = app.deliveryCartRestaurantID else { return nil }
        return app.deliveryRestaurants.first(where: { $0.id == id })
    }

    private var needsAddress: Bool {
        app.deliveryNeedsAddress(for: app.deliveryCartRestaurantID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    cartLines
                    // A live restaurant is a real payment: the totals, the tip
                    // and the discount all come from the server's quote. A
                    // SampleData one keeps the offline demo's arithmetic.
                    if app.deliveryCartIsLive {
                        tipPicker
                        promotionField
                        quotedBreakdown
                    } else {
                        feeBreakdown
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showAddresses = true
                    } label: {
                        detailRow(icon: "location.fill", title: "Deliver to",
                                  value: app.deliveryAddressLabel)
                    }
                    .buttonStyle(PressableStyle())
                    if app.deliveryCartIsLive {
                        Button {
                            app.showWallet = true
                        } label: {
                            detailRow(icon: "wallet.bifold.fill", title: "Paying with",
                                      value: "GoJo Wallet · \(app.walletBalanceLabel)")
                        }
                        .buttonStyle(PressableStyle())
                    } else {
                        detailRow(icon: "creditcard.fill", title: "Paying with", value: "Apple Pay")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            placeOrderButton
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .task {
            await app.refreshWallet()
            await app.refreshDeliveryQuote()
        }
        // Re-quotes whenever the basket changes. Keyed on the line count and
        // total quantity rather than the array itself: a cart line carries a
        // menu item, and making that whole graph Equatable to watch it would be
        // a lot of conformance for one integer's worth of signal.
        .onChange(of: app.deliveryCart.reduce(0) { $0 + $1.qty * 31 + 1 }) { _, _ in
            Task { await app.refreshDeliveryQuote() }
        }
        .sheet(isPresented: $showAddresses) {
            DeliveryAddressSheet()
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(GGColor.sheetBG)
        }
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text(restaurant?.name ?? "Your cart")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            if let r = restaurant {
                Text("Arrives in about \(r.etaMinutes)–\(r.etaMinutes + 10) min")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var cartLines: some View {
        VStack(spacing: 0) {
            ForEach(Array(app.deliveryCart.enumerated()), id: \.element.id) { i, line in
                HStack(spacing: 12) {
                    MediaImage(url: line.item.imageURL, cornerRadius: 10)
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.item.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .lineLimit(1)
                        Text(String(format: "$%.2f", line.item.price))
                            .font(.ggMono(11, .medium))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        sheetStepper("minus") { app.decrementDeliveryItem(line.item) }
                        Text("\(line.qty)")
                            .font(.ggMono(13, .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .frame(minWidth: 22)
                        sheetStepper("plus") {
                            if let r = restaurant { app.addDeliveryItem(line.item, from: r) }
                        }
                    }
                    .background(Capsule().fill(GGColor.ink(0.08)))
                }
                .padding(.vertical, 10)
                if i < app.deliveryCart.count - 1 {
                    Divider().background(GGColor.ink(0.07))
                }
            }
        }
        .padding(.horizontal, 14)
        .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    private var feeBreakdown: some View {
        VStack(spacing: 8) {
            feeRow("Subtotal", app.deliveryCartSubtotal)
            feeRow("Delivery fee", app.deliveryFeeAmount, freeWhenZero: true)
            feeRow("Service fee", app.deliveryServiceFee)
            Divider().background(GGColor.ink(0.1))
            HStack {
                Text("Total")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer()
                Text(String(format: "$%.2f", app.deliveryCartTotal))
                    .font(.ggMono(15, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }
        }
        .padding(14)
        .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    // MARK: Paid checkout (Phase 2e M3)

    /// The server's numbers, not ours. Every line here is read off the quote —
    /// including the discount, which is why the code field sends a code and
    /// never an amount.
    private var quotedBreakdown: some View {
        VStack(spacing: 8) {
            if let quote = app.deliveryQuote {
                quoteRow("Subtotal", quote.subtotalCents)
                if quote.discountCents > 0 {
                    quoteRow(quote.promotionLabel.isEmpty ? "Discount" : quote.promotionLabel,
                             -quote.discountCents)
                }
                quoteRow("Delivery fee", quote.deliveryFeeCents, freeWhenZero: true)
                quoteRow("Service fee", quote.serviceFeeCents)
                if quote.tipCents > 0 { quoteRow("Courier tip", quote.tipCents) }
                Divider().background(GGColor.ink(0.1))
                HStack {
                    Text("Total")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Spacer()
                    Text(WalletStore.money(quote.totalCents, currency: quote.currency))
                        .font(.ggMono(15, .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                }
                if !quote.walletCovers {
                    // Said before they commit, with the exact number, rather
                    // than after a refused checkout.
                    Text("Your wallet is short by \(WalletStore.money(quote.shortfallMinor, currency: quote.currency)) — top up to order.")
                        .explanatory(12)
                        .foregroundStyle(GGColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack {
                    Text(app.deliveryQuoting ? "Pricing your order…" : "Total")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                    Spacer()
                    if app.deliveryQuoting { ProgressView().scaleEffect(0.7) }
                }
            }
        }
        .padding(14)
        .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    private var tipPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tip your courier")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            HStack(spacing: 8) {
                ForEach(AppState.deliveryTipOptions, id: \.self) { cents in
                    let selected = app.deliveryTipCents == cents
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.setDeliveryTip(cents)
                    } label: {
                        Text(cents == 0 ? "None" : WalletStore.money(cents))
                            .font(.ggMono(12, .semibold))
                            .foregroundStyle(selected ? GGColor.onAccent : GGColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(selected ? GGColor.white : GGColor.ink(0.08)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            Text("Couriers keep 100% of every tip.")
                .explanatory(11)
                .foregroundStyle(GGColor.textTertiary)
        }
        .padding(14)
        .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    private var promotionField: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            TextField("Promo code", text: $promoCode)
                .font(.ggMono(13, .medium))
                .foregroundStyle(GGColor.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { app.applyDeliveryPromotionCode(promoCode) }
            if !promoCode.isEmpty {
                Button("Apply") { app.applyDeliveryPromotionCode(promoCode) }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
        }
        .padding(14)
        .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    private func quoteRow(_ label: String, _ cents: Int, freeWhenZero: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
                .lineLimit(1)
            Spacer()
            Text(cents == 0 && freeWhenZero ? "Free" : WalletStore.money(cents))
                .font(.ggMono(13, .medium))
                .foregroundStyle(GGColor.textSecondary)
        }
    }

    private func feeRow(_ label: String, _ amount: Double, freeWhenZero: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
            Spacer()
            Text(amount == 0 && freeWhenZero ? "Free" : String(format: "$%.2f", amount))
                .font(.ggMono(13, .medium))
                .foregroundStyle(GGColor.textSecondary)
        }
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(GGColor.ink(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GGColor.textTertiary)
        }
        .padding(12)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    private func sheetStepper(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }

    private var placeOrderButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // Nowhere to deliver to yet — ask for that first instead of
            // bouncing off the backend.
            if needsAddress {
                showAddresses = true
            } else {
                app.placeDeliveryOrder()
            }
        } label: {
            HStack {
                Text(needsAddress ? "Add a delivery address" : "Place order")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                // The server's total once it has quoted one; a live cart never
                // shows a number this app worked out for itself.
                Text(app.deliveryQuote.map { WalletStore.money($0.totalCents, currency: $0.currency) }
                     ?? String(format: "$%.2f", app.deliveryCartTotal))
                    .font(.ggMono(15, .semibold))
            }
            .foregroundStyle(GGColor.onAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
        .disabled(app.deliveryCart.isEmpty)
        .opacity(app.deliveryCart.isEmpty ? 0.4 : 1)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

// MARK: - Live order tracking

private struct DeliveryTrackingView: View {
    @EnvironmentObject var app: AppState
    @State private var viewport: Viewport = .camera(
        center: CLLocationCoordinate2D(latitude: 33.5731, longitude: -7.5898),
        zoom: 13.5, bearing: 22, pitch: 52
    )

    private let home = CLLocationCoordinate2D(latitude: 33.5731, longitude: -7.5898)

    private var restaurantCoord: CLLocationCoordinate2D {
        let r = app.deliveryOrderRestaurant
        return CLLocationCoordinate2D(latitude: r?.latitude ?? 33.5793,
                                      longitude: r?.longitude ?? -7.6030)
    }

    private var courierCoord: CLLocationCoordinate2D {
        let t = app.deliveryCourierProgress
        return CLLocationCoordinate2D(
            latitude: restaurantCoord.latitude + (home.latitude - restaurantCoord.latitude) * t,
            longitude: restaurantCoord.longitude + (home.longitude - restaurantCoord.longitude) * t
        )
    }

    private var showCourier: Bool {
        guard let status = app.deliveryStatus else { return false }
        return status >= .delivering && status != .delivered
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DeliveryMapView(
                viewport: $viewport,
                restaurant: restaurantCoord,
                home: home,
                courier: showCourier ? courierCoord : nil,
                showRoute: app.deliveryStatus != nil && app.deliveryStatus != .delivered
            )

            LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GOJODELIVERY")
                            .font(.ggMono(12, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(GGColor.textSecondary)
                        Wordmark(size: 22, trailing: "delivery")
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
            }

            statusSheet
                .padding(.horizontal, 16)
                .padding(.bottom, tabBarInset - 12)
        }
        .onAppear {
            MapboxOptions.accessToken = MapboxConfig.accessToken
            refreshCamera(animated: false)
        }
        .onChange(of: app.deliveryStatus) { _, _ in refreshCamera(animated: true) }
        .onChange(of: app.deliveryCourierProgress) { _, _ in refreshCamera(animated: true) }
    }

    private func refreshCamera(animated: Bool) {
        let next = DeliveryCamera.fit(
            restaurant: restaurantCoord,
            home: home,
            followCourier: showCourier ? courierCoord : nil
        )
        if animated {
            withViewportAnimation(.easeInOut(duration: 0.55)) { viewport = next }
        } else {
            viewport = next
        }
    }

    @ViewBuilder
    private var statusSheet: some View {
        if app.deliveryStatus == .delivered {
            deliveredSheet
        } else {
            progressSheet
        }
    }

    private var progressSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.deliveryStatus?.label ?? "")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(app.deliveryStatus?.detail ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                }
                Spacer()
                Text("\(app.deliveryEtaMinutes) min")
                    .font(.ggMono(13, .semibold))
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(GGColor.white))
            }

            timeline

            if let courier = app.deliveryCourier {
                HStack(spacing: 12) {
                    UserAvatar(size: 44, letter: String(courier.name.prefix(1)), imageURL: courier.avatarURL)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(courier.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                            Text(String(format: "%.2f · %@", courier.rating, courier.vehicle))
                                .font(.ggMono(11, .medium))
                        }
                        .foregroundStyle(GGColor.textSecondary)
                    }
                    Spacer()
                    courierAction("phone.fill")
                    courierAction("message.fill")
                }
                .padding(12)
                .glass(cornerRadius: 16)
            }

            if let r = app.deliveryOrderRestaurant {
                HStack {
                    Text(r.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(app.deliveryOrderTotalLabel)
                        .font(.ggMono(13, .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                }
            }

            if app.canCancelDeliveryOrder {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    app.cancelDeliveryOrder()
                } label: {
                    Text("Cancel order")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glass(cornerRadius: 16)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(18)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.52), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var timeline: some View {
        let steps: [DeliveryOrderStatus] = [.confirmed, .preparing, .courierToRestaurant, .delivering]
        let current = app.deliveryStatus ?? .confirmed
        return HStack(spacing: 6) {
            ForEach(steps, id: \.rawValue) { step in
                Capsule()
                    .fill(step <= current ? GGColor.white : GGColor.ink(0.14))
                    .frame(height: 4)
            }
        }
    }

    private func courierAction(_ icon: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(GGColor.ink(0.1)))
        }
        .buttonStyle(PressableStyle())
    }

    private var deliveredSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(GGColor.white)

            Text("Delivered")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)

            if let r = app.deliveryOrderRestaurant {
                Text("\(r.name) · \(app.deliveryOrderTotalLabel)")
                    .explanatory(14)
                    .foregroundStyle(GGColor.textSecondary)
            }

            Text("How was your order?")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.deliveryRating = star
                    } label: {
                        Image(systemName: star <= app.deliveryRating ? "star.fill" : "star")
                            .font(.system(size: 26))
                            .foregroundStyle(GGColor.white.opacity(star <= app.deliveryRating ? 1 : 0.28))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.vertical, 4)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                app.finishDeliveryOrder()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.52), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
