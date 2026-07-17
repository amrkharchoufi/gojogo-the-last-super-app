import SwiftUI

struct EconomyView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var category = "All"
    @State private var nearMe = false
    @State private var underBudget = false
    @State private var chromeHidden = false
    @FocusState private var searchFocused: Bool

    private var catalog: [Product] {
        [app.featuredProduct] + app.products
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

                    dealBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .zIndex(0)

                    if !app.savedProducts.isEmpty {
                        productRail(
                            title: "Keep shopping",
                            subtitle: "From your saved list",
                            products: app.savedProducts
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

                    Color.clear.frame(height: tabBarInset)
                }
                .padding(.top, 56)
            }
            .scrollDismissesKeyboard(.immediately)
            .trackScrollChrome(hidden: $chromeHidden)

            topChrome
                .autoHideChrome(chromeHidden)
        }
    }

    // MARK: - Chrome

    private var topChrome: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GOJOGO")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Wordmark(size: 20, trailing: "economy")
            }
            Spacer(minLength: 0)
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
                    withAnimation(.easeOut(duration: 0.15)) { query = "" }
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
                withAnimation(.easeOut(duration: 0.2)) { nearMe.toggle() }
            } label: {
                MonoChip(text: "near me", active: nearMe)
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { underBudget.toggle() }
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
                                Circle().fill(active ? GGColor.white : Color.white.opacity(0.08))
                            )
                            .overlay(
                                Circle().strokeBorder(
                                    active ? Color.clear : Color.white.opacity(0.1),
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
                        withAnimation(.easeOut(duration: 0.2)) { category = cat }
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
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
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
                    Button { app.closeProduct() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.black.opacity(0.45)))
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
        .background(GGColor.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    withAnimation { app.toggleSaveProduct(product.id) }
                } label: {
                    Image(systemName: product.saved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .glassCapsule(interactive: false)
                }
                .buttonStyle(PressableStyle())

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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
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
                                .foregroundStyle(msg.fromUser ? Color.black : Color.white)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(msg.fromUser ? Color.white : Color.white.opacity(0.12))
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
                        .foregroundStyle(Color.black)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white))
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("List something nearby")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)

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

                    Button {
                        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let listing = Product(
                            name: title,
                            price: price.isEmpty ? "$—" : (price.hasPrefix("$") ? price : "$\(price)"),
                            meta: "you · just now",
                            gradient: app.user.avatarGradient,
                            category: category,
                            seller: app.user.handle,
                            condition: "Like new",
                            distance: "0 km",
                            description: notes.isEmpty ? "Listed by you on GojoGo Economy." : notes
                        )
                        withAnimation {
                            app.products.insert(listing, at: 0)
                            posted = true
                        }
                        app.schedulePersist()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            app.showSellSheet = false
                        }
                    } label: {
                        Text(posted ? "Listed ✓" : "Publish listing")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GGColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .buttonStyle(PressableStyle())
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
