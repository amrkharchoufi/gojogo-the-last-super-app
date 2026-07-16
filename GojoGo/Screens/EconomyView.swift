import SwiftUI

struct EconomyView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var category = "All"
    @State private var nearMe = true
    @State private var underBudget = true

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
            return catOK && queryOK
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            GGBackground(glow: GGColor.accent.opacity(0.12))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerCopy
                    searchCard
                    categoryRow
                    if !app.savedProducts.isEmpty {
                        savedRail
                    }
                    resultSpotlight
                    listingsGrid
                    Color.clear.frame(height: tabBarInset)
                }
                .padding(.horizontal, 20)
                .padding(.top, 110)
            }

            HStack {
                Text("GOJOGO ECONOMY")
                    .font(.ggMono(13, .semibold)).tracking(0.4)
                    .foregroundStyle(GGColor.textSecondary)
                Spacer()
                Button {
                    app.showSellSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Sell")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 20).padding(.top, 8)
            .background(TopScrim(), alignment: .top)
        }
    }

    private var headerCopy: some View {
        (Text("What are you looking for ")
         + Text("today?")
            .font(.system(size: 32, weight: .medium).italic())
            .foregroundColor(GGColor.accent))
            .font(.system(size: 32, weight: .bold))
            .tracking(-1)
            .foregroundColor(GGColor.textPrimary)
            .lineSpacing(2)
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Describe what you want…", text: $query, axis: .vertical)
                .font(.system(size: 14)).lineSpacing(3)
                .foregroundStyle(GGColor.textPrimary.opacity(0.92))
                .lineLimit(2...5)
            HStack(spacing: 8) {
                Button { nearMe.toggle() } label: {
                    MonoChip(text: "near me", active: nearMe)
                }
                .buttonStyle(.plain)
                Button { underBudget.toggle() } label: {
                    MonoChip(text: "≤ $300", active: underBudget)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(filtered.count)")
                    .font(.ggMono(11, .medium))
                    .foregroundStyle(GGColor.textTertiary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(GGColor.blue))
            }
        }
        .padding(18)
        .glass(cornerRadius: 22, fillOpacity: 0.06, borderOpacity: 0.12)
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SampleData.economyCategories, id: \.self) { cat in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { category = cat }
                    } label: {
                        Text(cat)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(category == cat ? Color.black : Color.white.opacity(0.7))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(category == cat ? Color.white : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var savedRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Saved")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(app.savedProducts) { product in
                        Button { app.openProduct(product) } label: {
                            productTile(product, width: 120)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var resultSpotlight: some View {
        let p = app.featuredProduct
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Best match")
            Button { app.openProduct(p) } label: {
                HStack(spacing: 12) {
                    MediaImage(url: p.imageURL, cornerRadius: 16)
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(p.name).font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(GGColor.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Text(p.price).font(.system(size: 16, weight: .bold))
                                .foregroundStyle(GGColor.accent)
                        }
                        Text(p.meta).font(.system(size: 12)).foregroundStyle(GGColor.textSecondary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            Text(p.condition)
                                .font(.ggMono(10, .medium))
                                .foregroundStyle(GGColor.textSecondary)
                            Text("·")
                                .foregroundStyle(GGColor.textTertiary)
                            Text(p.distance)
                                .font(.ggMono(10, .medium))
                                .foregroundStyle(GGColor.textSecondary)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(14)
                .glass(cornerRadius: 22, fillOpacity: 0.055, borderOpacity: 0.09)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    app.openSellerChat(for: p)
                } label: {
                    Text("Message seller")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        app.toggleSaveProduct(p.id)
                    }
                } label: {
                    Text(p.saved ? "Saved" : "Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(p.saved ? GGColor.white : GGColor.textPrimary)
                        .frame(width: 88)
                        .padding(.vertical, 11)
                        .glassCapsule(interactive: false)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private var listingsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: category == "All" ? "Near you" : category)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 12) {
                ForEach(filtered.filter { $0.id != app.featuredProduct.id }) { product in
                    Button { app.openProduct(product) } label: {
                        productTile(product, width: nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func productTile(_ product: Product, width: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                MediaImage(url: product.imageURL, cornerRadius: 16)
                    .aspectRatio(1, contentMode: .fit)
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        app.toggleSaveProduct(product.id)
                    }
                } label: {
                    Image(systemName: product.saved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            Text(product.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(product.price)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GGColor.accent)
            Text("\(product.condition) · \(product.distance)")
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
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
