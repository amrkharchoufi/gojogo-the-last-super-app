import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Your shop (Phase 5 · M1 + M2)
//
// The economy sibling of the restaurant dashboard, and the surface GoJoAdmin's
// Economy module will drive later with the owner's own JWT — same endpoints, no
// admin mirror (ARCHITECTURE §10b). Five tabs, in the order a seller's day
// actually goes: what's waiting (orders), what's for sale (catalog), what's on
// offer (promotions), what came in (money), and the settings nobody opens twice.
//
// The order queue is first on purpose. Everything else here can wait a day; an
// order that hasn't been posted is somebody who has already paid.

struct SellerConsoleView: View {
    @EnvironmentObject var app: AppState

    @State private var tab: Tab = .orders
    @State private var editing: EditingProduct?
    @State private var shipping: ShopOrderDTO?
    @State private var showPromotionForm = false

    private enum Tab: String, CaseIterable, Identifiable {
        case orders, catalog, promotions, money, settings
        var id: String { rawValue }
        var label: String {
            switch self {
            case .orders: return "Orders"
            case .catalog: return "Catalog"
            case .promotions: return "Offers"
            case .money: return "Money"
            case .settings: return "Shop"
            }
        }
    }

    /// A product being created (nil id) or edited. Held here rather than in
    /// AppState: an unsaved form is this screen's business and nobody else's.
    struct EditingProduct: Identifiable {
        let id: UUID
        let product: ShopProductDTO?
        init(_ product: ShopProductDTO?) {
            self.id = product?.id ?? UUID()
            self.product = product
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let notice = app.economyNotice {
                EconomyNoticeBanner(message: notice) { app.dismissEconomyNotice() }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            tabs
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    switch tab {
                    case .orders: orders
                    case .catalog: catalog
                    case .promotions: promotions
                    case .money: money
                    case .settings: settings
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .refreshable { await app.refreshSellerConsole() }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .animation(.ggOverlay, value: app.economyNotice)
        .task { await app.refreshSellerConsole() }
        .sheet(item: $editing) { target in
            ShopProductEditor(product: target.product)
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationBackground(GGColor.sheetBG)
        }
        .sheet(item: $shipping) { order in
            ShipOrderSheet(order: order)
                .environmentObject(app)
                .presentationDetents([.height(260)])
                .presentationBackground(GGColor.sheetBG)
        }
        .sheet(isPresented: $showPromotionForm) {
            PromotionEditor()
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationBackground(GGColor.sheetBG)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR SHOP")
                    .font(.ggMono(10, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(GGColor.textTertiary)
                Text(app.myShop?.displayName ?? "Loading…")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer(minLength: 0)
            if app.myShop?.suspended == true {
                Text("SUSPENDED")
                    .font(.ggMono(9, .bold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(GGColor.white))
            }
            Button {
                app.closeSellerConsole()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .glassCapsule(interactive: false)
                    // See ShopProductDetailView.closeBar: an Image in a frame
                    // hit-tests to the glyph unless it is given a shape.
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Tab.allCases) { option in
                    let active = tab == option
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggSnappy) { tab = option }
                    } label: {
                        HStack(spacing: 6) {
                            Text(option.label)
                                .font(.system(size: 13, weight: .semibold))
                            if option == .orders {
                                let waiting = app.shopOrderQueue.filter { $0.state == .placed }.count
                                if waiting > 0 {
                                    Text("\(waiting)")
                                        .font(.ggMono(11, .semibold))
                                        .opacity(0.75)
                                }
                            }
                        }
                        .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Orders

    @ViewBuilder
    private var orders: some View {
        if app.shopOrderQueue.isEmpty {
            GGEmptyState(icon: "shippingbox",
                         title: "No orders yet",
                         message: "When somebody buys, it lands here to be posted.")
                .padding(.top, 30)
        } else {
            ForEach(app.shopOrderQueue) { order in
                SellerOrderRow(
                    order: order,
                    onShip: { shipping = order },
                    onCancel: { app.cancelShopOrderAsSeller(order.id) })
            }
        }
    }

    // MARK: Catalog

    @ViewBuilder
    private var catalog: some View {
        Button {
            editing = EditingProduct(nil)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("Add a product")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(GGColor.textPrimary)
            .padding(14)
            .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())

        if app.myShopProducts.isEmpty {
            Text("Nothing in the catalog yet.")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)
                .padding(.vertical, 20)
        } else {
            ForEach(app.myShopProducts) { product in
                SellerProductRow(
                    product: product,
                    onEdit: { editing = EditingProduct(product) },
                    onToggle: { app.setShopProductActive(product.id, !product.active) })
            }
        }
    }

    // MARK: Promotions

    @ViewBuilder
    private var promotions: some View {
        Button {
            showPromotionForm = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "percent")
                    .font(.system(size: 13, weight: .bold))
                Text("New offer")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(GGColor.textPrimary)
            .padding(14)
            .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())

        if app.shopPromotions.isEmpty {
            Text("No offers running. A code is the only way a buyer gets one.")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)
                .padding(.vertical, 20)
        } else {
            ForEach(app.shopPromotions) { promotion in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(promotion.code ?? promotion.label ?? "Offer")
                            .font(.ggMono(13, .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                        Text(promotion.valueLabel
                             + (promotion.minBasketCents > 0
                                ? " · over \(EconomyStore.formatPrice(cents: Int64(promotion.minBasketCents), currency: "USD"))"
                                : ""))
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if promotion.active {
                        Button("End") { app.deactivateShopPromotion(promotion.id) }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GGColor.textSecondary)
                            .buttonStyle(.plain)
                    } else {
                        Text("Ended")
                            .font(.system(size: 11))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
            }
        }
    }

    // MARK: Money

    @ViewBuilder
    private var money: some View {
        PayeeWalletCard(wallet: app.shopWallet,
                        emptyLine: "Nothing settled yet. A sale pays out once the buyer confirms it arrived.")
    }

    // MARK: Settings

    @ViewBuilder
    private var settings: some View {
        if let shop = app.myShop {
            ShopSettingsForm(shop: shop)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(GGColor.ink(0.06))
                .frame(height: 200)
                .shimmering()
        }
    }
}

// MARK: - Rows

struct SellerOrderRow: View {
    let order: ShopOrderDTO
    let onShip: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: order.state.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(order.state.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer(minLength: 0)
                Text(order.totalLabel)
                    .font(.ggMono(14, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            .foregroundStyle(GGColor.textSecondary)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(order.lines) { line in
                    Text("\(line.quantity)× \(line.productName) · \(line.variantLabel)")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                }
                if let shipTo = order.shipTo, !shipTo.isEmpty {
                    Text(shipTo)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textTertiary)
                        .lineLimit(2)
                }
            }

            if order.state == .placed {
                HStack(spacing: 10) {
                    Button("Cancel + refund", action: onCancel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                        .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button(action: onShip) {
                        Text("Mark posted")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(GGColor.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .buttonStyle(PressableStyle())
                }
            } else if order.state == .shipped {
                Text("Waiting on the buyer to confirm it arrived — or 14 days, whichever comes first.")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
    }
}

struct SellerProductRow: View {
    let product: ShopProductDTO
    let onEdit: () -> Void
    let onToggle: () -> Void

    private var stock: Int { product.variants.filter(\.active).reduce(0) { $0 + $1.stock } }

    var body: some View {
        HStack(spacing: 12) {
            MediaImage(url: product.imageURL, cornerRadius: 12)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1)
                Text("\(product.variants.count) variant\(product.variants.count == 1 ? "" : "s") · \(stock) in stock")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
                if product.isDigital {
                    Text("Download")
                        .font(.ggMono(9, .semibold))
                        .tracking(0.6)
                        .foregroundStyle(GGColor.textTertiary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                Button(action: onToggle) {
                    Text(product.active ? "Live" : "Hidden")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(product.active ? GGColor.onAccent : GGColor.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(product.active ? GGColor.white
                                                   : GGColor.ink(0.08)))
                }
                .buttonStyle(.plain)
                Button("Edit", action: onEdit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
    }
}

/// Balances plus the statement, for whichever payee this is. Shared by both
/// Phase 5 consoles — a shop and a provider are paid the same way and the
/// screen has nothing vertical-specific in it.
struct PayeeWalletCard: View {
    let wallet: PayeeWalletDTO?
    let emptyLine: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AVAILABLE")
                    .font(.ggMono(9, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(GGColor.textTertiary)
                Text(EconomyStore.formatPrice(cents: wallet?.balances.available ?? 0,
                                              currency: wallet?.balances.currency ?? "USD"))
                    .font(.ggMono(26, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }

            if let escrow = wallet?.balances.escrow, escrow > 0 {
                Text("\(EconomyStore.formatPrice(cents: escrow, currency: wallet?.balances.currency ?? "USD")) held against orders that haven't settled.")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }

            Divider().overlay(GGColor.hairline)

            if let entries = wallet?.entries, !entries.isEmpty {
                ForEach(entries.prefix(30)) { entry in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.memo?.isEmpty == false ? entry.memo! : entry.kind)
                                .font(.system(size: 13))
                                .foregroundStyle(GGColor.textPrimary)
                                .lineLimit(1)
                            Text(BackendDate.relative(entry.createdAt))
                                .font(.system(size: 11))
                                .foregroundStyle(GGColor.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Text(entry.amountLabel)
                            .font(.ggMono(13, .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                    }
                }
            } else {
                Text(emptyLine)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 20, tint: GGColor.ink(0.05))
    }
}

// MARK: - Forms

struct ShopSettingsForm: View {
    @EnvironmentObject var app: AppState

    let shop: ShopSellerDTO

    @State private var name: String = ""
    @State private var shippingFlat: String = ""
    @State private var freeOver: String = ""
    @State private var taxPercent: String = ""
    @State private var logoURL: String?
    @State private var pick: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 12) {
                    MediaImage(url: logoURL, cornerRadius: 14)
                        .frame(width: 56, height: 56)
                        .overlay {
                            if uploading { ProgressView().tint(GGColor.textPrimary) }
                            else if logoURL == nil {
                                Image(systemName: "photo")
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundStyle(GGColor.textTertiary)
                            }
                        }
                    Text(logoURL == nil ? "Add a shop logo" : "Change logo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .onChange(of: pick) { _, item in
                guard let item else { return }
                Task {
                    defer { pick = nil }
                    uploading = true
                    defer { uploading = false }
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    logoURL = try? await APIClient.shared.uploadMedia(
                        data, contentType: APIClient.imageContentType(for: data))
                }
            }

            field("Shop name", text: $name)
            field("Flat shipping (e.g. 4.99)", text: $shippingFlat, numeric: true)
            field("Free shipping over (0 = never)", text: $freeOver, numeric: true)
            field("Tax %", text: $taxPercent, numeric: true)

            Text("Shipping and tax are applied by the server at checkout, so what a buyer is charged always comes from these numbers rather than from their phone.")
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }

            Button {
                save()
            } label: {
                Text(saving ? "Saving…" : "Save")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(saving)
        }
        .padding(16)
        .glass(cornerRadius: 20, tint: GGColor.ink(0.04))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = shop.displayName
            logoURL = shop.logoUrl
            shippingFlat = Self.money(shop.shippingFlatCents)
            freeOver = Self.money(shop.freeShippingOverCents)
            taxPercent = String(format: "%g", Double(shop.taxBps) / 100)
        }
    }

    private func field(_ label: String, text: Binding<String>, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField("", text: text)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .keyboardType(numeric ? .decimalPad : .default)
                .padding(11)
                .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            let failure = await app.saveShopSettings(ShopSellerBody(
                displayName: name.trimmingCharacters(in: .whitespaces),
                logoUrl: logoURL,
                shippingFlatCents: Int(EconomyStore.parseCents(shippingFlat) ?? 0),
                freeShippingOverCents: Int(EconomyStore.parseCents(freeOver) ?? 0),
                taxBps: Int((Double(taxPercent) ?? 0) * 100)))
            saving = false
            withAnimation(.ggSnappy) { error = failure }
        }
    }

    static func money(_ cents: Int) -> String {
        cents == 0 ? "" : String(format: "%.2f", Double(cents) / 100)
    }
}

/// The tracking note is free text on purpose: this system does not integrate
/// with any carrier, so pretending to validate a tracking number would be a
/// field that rejects the truth.
struct ShipOrderSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let order: ShopOrderDTO
    @State private var note: String = ""

    var body: some View {
        VStack(spacing: 14) {
            Text("Mark posted")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
                .padding(.top, 20)
            Text("The buyer sees this on their order.")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)

            TextField("Tracking number, courier, anything useful", text: $note, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .lineLimit(2...4)
                .padding(12)
                .glass(cornerRadius: 14, tint: GGColor.ink(0.05))
                .padding(.horizontal, 18)

            Button {
                app.shipShopOrder(order.id, note: note)
                dismiss()
            } label: {
                Text("Mark posted")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
    }
}

struct PromotionEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var label = ""
    @State private var kind = "PERCENT"
    @State private var value = ""
    @State private var minBasket = ""
    @State private var perUser = "1"
    @State private var saving = false
    @State private var error: String?

    private let kinds = [("PERCENT", "% off"), ("FIXED", "Amount off"), ("FREE_SHIPPING", "Free shipping")]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("New offer")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                HStack(spacing: 8) {
                    ForEach(kinds, id: \.0) { option in
                        let active = kind == option.0
                        Button {
                            withAnimation(.ggSnappy) { kind = option.0 }
                        } label: {
                            Text(option.1)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(active ? GGColor.white
                                                           : GGColor.ink(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                field("Code buyers type", text: $code)
                field("Label", text: $label)
                if kind != "FREE_SHIPPING" {
                    field(kind == "PERCENT" ? "Percent off" : "Amount off",
                          text: $value, numeric: true)
                }
                field("Minimum basket (blank = none)", text: $minBasket, numeric: true)
                field("Per buyer limit", text: $perUser, numeric: true)

                if kind == "FREE_SHIPPING" {
                    Text("Refused on a basket that already ships free — the same rule delivery uses, so a code never quietly comes off the goods instead.")
                        .font(.system(size: 11))
                        .foregroundStyle(GGColor.textTertiary)
                }

                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                }

                Button {
                    save()
                } label: {
                    Text(saving ? "Creating…" : "Create offer")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
                .disabled(saving)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
    }

    private func field(_ label: String, text: Binding<String>, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField("", text: text)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .keyboardType(numeric ? .decimalPad : .default)
                .textInputAutocapitalization(numeric ? .never : .characters)
                .autocorrectionDisabled()
                .padding(11)
                .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            let percent = Double(value) ?? 0
            let failure = await app.createShopPromotion(ShopPromotionBody(
                code: code.trimmingCharacters(in: .whitespaces).uppercased(),
                label: label.isEmpty ? code : label,
                kind: kind,
                valueBps: kind == "PERCENT" ? Int(percent * 100) : 0,
                amountCents: kind == "FIXED" ? Int(EconomyStore.parseCents(value) ?? 0) : 0,
                minBasketCents: Int(EconomyStore.parseCents(minBasket) ?? 0),
                maxDiscountCents: 0,
                perUserLimit: Int(perUser) ?? 1,
                startsAt: nil,
                endsAt: nil))
            saving = false
            if failure == nil { dismiss() } else { withAnimation(.ggSnappy) { error = failure } }
        }
    }
}
