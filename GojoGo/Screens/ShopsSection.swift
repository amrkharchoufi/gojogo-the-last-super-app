import SwiftUI

// MARK: - Shops: the merchant catalog (Phase 5 · M1)
//
// The Economy tab's second segment. Where Marketplace is one person selling one
// thing, this is a provisioned shop with a catalog — so the card carries a shop
// name, a rating and a "from" price, because a product with three variants has
// no single price to print.
//
// The grid is deliberately plainer than Marketplace's rails. There are no deals
// banners or "inspired by your browsing" strips here, because a rail that ranks
// things needs a signal to rank them by, and inventing one out of the first page
// the server happened to send is a recommendation nobody made.

struct ShopsSection: View {
    @EnvironmentObject var app: AppState
    @Binding var chromeHidden: Bool
    /// Measured by the chrome that floats above this scroll, not assumed.
    var chromeHeight: CGFloat = ChromeMetrics.assumedHeight

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    /// Categories the loaded page actually contains, plus All. Built from the
    /// catalog rather than hardcoded: a shop selling anything the app never
    /// anticipated still gets a chip.
    private var categories: [String] {
        let live = Set(app.shopProducts.compactMap { $0.category }.filter { !$0.isEmpty })
        return ["All"] + live.sorted()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if categories.count > 1 {
                    categoryChips
                        .padding(.top, 4)
                }

                if app.shopLoading && app.shopProducts.isEmpty {
                    loadingGrid
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                } else if app.shopProducts.isEmpty {
                    GGEmptyState(
                        icon: "bag",
                        title: "No shops open yet",
                        message: app.isSeller
                            ? "Your shop is approved — add a product and it shows up here."
                            : "Merchant shops appear here as they open.",
                        actionTitle: app.isSeller ? "Open your shop" : nil,
                        action: app.isSeller ? { app.openSellerConsole() } : nil)
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(app.shopProducts) { product in
                            ShopProductCard(product: product) {
                                app.openShopProduct(product)
                            }
                            .onAppear { app.loadMoreShopsIfNeeded(after: product.id) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }

                Color.clear.frame(height: tabBarInset + (app.shopBasket.isEmpty ? 0 : 60))
            }
            .padding(.top, chromeHeight)
        }
        .refreshable { await app.refreshShops() }
        .trackScrollChrome(hidden: $chromeHidden)
        .task {
            if app.shopProducts.isEmpty { await app.refreshShops() }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    let active = app.shopCategory == category
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.selectShopCategory(category)
                    } label: {
                        Text(category)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(GGColor.ink(0.06))
                    .frame(height: 210)
                    .shimmering()
            }
        }
    }
}

/// One product in the grid. Prints "from" against the cheapest live variant,
/// and says *sold out* rather than showing a price nobody can pay.
struct ShopProductCard: View {
    let product: ShopProductDTO
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    MediaImage(url: product.imageURL, cornerRadius: 0)
                        .frame(height: 132)
                        .clipped()
                    if product.isDigital {
                        badge("Download", icon: "arrow.down.circle.fill")
                            .padding(8)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(product.sellerName)
                        .font(.ggMono(9, .semibold))
                        .tracking(0.6)
                        .foregroundStyle(GGColor.textTertiary)
                        .lineLimit(1)
                    Text(product.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        if product.anyInStock {
                            // "From" only when the variants disagree — printing
                            // it on a single-variant product is a hedge about a
                            // price that is exactly the price.
                            if product.variants.count > 1 {
                                Text("from")
                                    .font(.system(size: 10))
                                    .foregroundStyle(GGColor.textTertiary)
                            }
                            Text(product.priceLabel)
                                .font(.ggMono(13, .semibold))
                                .foregroundStyle(GGColor.textPrimary)
                        } else {
                            Text("Sold out")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GGColor.textTertiary)
                        }
                        Spacer(minLength: 0)
                        if let rating = product.averageRating, product.ratingCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                Text(String(format: "%.1f", rating))
                                    .font(.ggMono(10, .semibold))
                            }
                            .foregroundStyle(GGColor.textSecondary)
                        }
                    }
                }
                .padding(10)
            }
            .background(GGColor.ink(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(GGColor.hairline, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func badge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(GGColor.onAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(GGColor.white))
    }
}
