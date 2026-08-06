import SwiftUI

// MARK: - Shop checkout (Phase 5 · M1)
//
// The one screen in this vertical where the client is deliberately not the
// authority on anything. The totals below are what the buyer was *shown* —
// shipping, tax and any discount are recomputed server-side from the shop's own
// settings, and the number that gets charged is the server's. So the sheet
// prints an estimate and says so, rather than a total that could disagree with
// the receipt by a cent and make a liar of both.
//
// A digital basket has no address and no shipping line: there is nothing to
// send anywhere, and asking for a street to deliver a file to is theatre.

struct ShopCheckoutSheet: View {
    @EnvironmentObject var app: AppState

    @State private var shipTo: String = ""
    @State private var promotionCode: String = ""
    @State private var placing = false
    @State private var error: String?
    @FocusState private var addressFocused: Bool

    private var isDigital: Bool { app.shopBasket.contains(where: \.isDigital) }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if app.shopBasket.isEmpty {
                        GGEmptyState(icon: "bag", title: "Your basket is empty")
                            .padding(.top, 40)
                    } else {
                        lines
                        if !isDigital { address }
                        promotion
                        totals
                        if let error {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(GGColor.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .glass(cornerRadius: 14, tint: GGColor.ink(0.08))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }

            if !app.shopBasket.isEmpty { payBar }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .onAppear {
            // The delivery vertical already knows where this person lives, and
            // typing it a second time is the app forgetting on their behalf.
            // Prefilled, not locked: a parcel and a pizza do not always go to
            // the same door.
            if shipTo.isEmpty, let saved = app.selectedDeliveryAddress {
                shipTo = saved.display
            }
        }
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text("Checkout")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text(app.basketSellerName.map { "From \($0)" } ?? "One order, one shop")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var lines: some View {
        VStack(spacing: 10) {
            ForEach(app.shopBasket) { line in
                HStack(spacing: 12) {
                    MediaImage(url: line.imageURL, cornerRadius: 12)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.productName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .lineLimit(2)
                        Text(line.variantLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(EconomyStore.formatPrice(cents: line.lineTotalCents, currency: "USD"))
                            .font(.ggMono(13, .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                        if line.isDigital {
                            Text("×1")
                                .font(.ggMono(11))
                                .foregroundStyle(GGColor.textTertiary)
                        } else {
                            quantityStepper(line)
                        }
                    }
                }
                .padding(12)
                .glass(cornerRadius: 16, tint: GGColor.ink(0.04))
            }
        }
    }

    private func quantityStepper(_ line: ShopBasketLine) -> some View {
        HStack(spacing: 10) {
            Button {
                app.setBasketQuantity(line.variantId, line.quantity - 1)
            } label: {
                Image(systemName: line.quantity == 1 ? "trash" : "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            Text("\(line.quantity)")
                .font(.ggMono(12, .semibold))
            Button {
                app.setBasketQuantity(line.variantId, line.quantity + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .disabled(line.quantity >= line.stock)
        }
        .foregroundStyle(GGColor.textPrimary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .glassCapsule(interactive: false)
    }

    private var address: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHIP TO")
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField("Address, flat, city", text: $shipTo, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .focused($addressFocused)
                .lineLimit(1...3)
                .padding(12)
                .glass(cornerRadius: 14, tint: GGColor.ink(0.05))
        }
    }

    private var promotion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROMO CODE")
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField("Optional", text: $promotionCode)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(12)
                .glass(cornerRadius: 14, tint: GGColor.ink(0.05))
        }
    }

    /// Goods only. Shipping and tax are the shop's own settings applied by the
    /// server, and a guess at them here would be a number the receipt disagrees
    /// with — so the sheet shows what it actually knows and names the rest.
    private var totals: some View {
        VStack(spacing: 8) {
            row("Items", EconomyStore.formatPrice(cents: app.basketTotalCents, currency: "USD"))
            if !isDigital {
                row("Shipping + tax", "at checkout", muted: true)
            }
            Divider().overlay(GGColor.hairline)
            row("Charged now", EconomyStore.formatPrice(cents: app.basketTotalCents,
                                                        currency: "USD") + "+", bold: true)
            Text(isDigital
                 ? "Paid from your GoJo balance. The download is yours the moment it goes through."
                 : "Paid from your GoJo balance and held until you confirm it arrived.")
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glass(cornerRadius: 16, tint: GGColor.ink(0.05))
    }

    private func row(_ label: String, _ value: String,
                     muted: Bool = false, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: bold ? .semibold : .regular))
                .foregroundStyle(bold ? GGColor.textPrimary : GGColor.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.ggMono(13, bold ? .semibold : .regular))
                .foregroundStyle(muted ? GGColor.textTertiary : GGColor.textPrimary)
        }
    }

    private var payBar: some View {
        Button {
            place()
        } label: {
            HStack(spacing: 8) {
                if placing {
                    ProgressView().tint(GGColor.onAccent)
                }
                Text(placing ? "Placing…" : "Place order")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(GGColor.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
        .disabled(placing)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func place() {
        addressFocused = false
        placing = true
        error = nil
        Task {
            let failure = await app.placeShopOrder(shipTo: shipTo, promotionCode: promotionCode)
            placing = false
            withAnimation(.ggSnappy) { error = failure }
        }
    }
}
