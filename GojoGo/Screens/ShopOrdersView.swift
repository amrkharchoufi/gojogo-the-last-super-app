import SwiftUI

// MARK: - Your shop orders and downloads (Phase 5 · M1 + M2)
//
// Two tabs, because a parcel and a download are different objects with
// different questions attached. A parcel has a journey and one tap on it that
// moves money — "it arrived" — and that tap is the only thing standing between
// the seller and being paid, so it is the loudest control on the row. A
// download has no journey at all: it was granted in the same transaction that
// took the money, and the only thing to do with it is open it.
//
// The confirm dialog is not politeness. Confirming receipt settles the escrow
// and there is no route back short of a dispute, which this vertical does not
// have yet — so the question is asked once, in words that say what it does.

struct ShopOrdersView: View {
    @EnvironmentObject var app: AppState

    @State private var tab: Tab = .orders
    @State private var confirming: ShopOrderDTO?
    @State private var reviewing: ShopOrderDTO?

    private enum Tab: String, CaseIterable, Identifiable {
        case orders, downloads
        var id: String { rawValue }
        var label: String { self == .orders ? "Orders" : "Downloads" }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let notice = app.economyNotice {
                EconomyNoticeBanner(message: notice) { app.dismissEconomyNotice() }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            header
            segments
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    switch tab {
                    case .orders: orders
                    case .downloads: downloads
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .refreshable {
                await app.refreshShopOrders()
                await app.refreshEntitlements()
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .animation(.ggOverlay, value: app.economyNotice)
        .task {
            await app.refreshShopOrders()
            await app.refreshEntitlements()
        }
        .alert("Confirm it arrived?", isPresented: Binding(
            get: { confirming != nil },
            set: { if !$0 { confirming = nil } }
        )) {
            Button("Not yet", role: .cancel) { confirming = nil }
            Button("It arrived") {
                if let order = confirming { app.confirmShopOrderReceived(order.id) }
                confirming = nil
            }
        } message: {
            Text("This pays the shop. Only do it once you actually have the thing — there's no undo.")
        }
        .sheet(item: $reviewing) { order in
            ShopReviewSheet(order: order)
                .environmentObject(app)
                .presentationDetents([.medium])
                .presentationBackground(GGColor.sheetBG)
        }
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text("Your purchases")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("From shops on GojoGo")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var segments: some View {
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
                        let count = option == .orders ? app.shopOrders.count : app.entitlements.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.ggMono(11, .semibold))
                                .opacity(0.7)
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
            Spacer(minLength: 0)
        }
    }

    // MARK: Orders

    @ViewBuilder
    private var orders: some View {
        if app.shopOrders.isEmpty {
            GGEmptyState(icon: "shippingbox",
                         title: "Nothing ordered yet",
                         message: "Orders from merchant shops show up here.")
                .padding(.top, 30)
        } else {
            ForEach(app.shopOrders) { order in
                ShopOrderRow(
                    order: order,
                    onConfirm: { confirming = order },
                    onCancel: { app.cancelShopOrder(order.id) },
                    onReview: { reviewing = order })
            }
        }
    }

    // MARK: Downloads

    @ViewBuilder
    private var downloads: some View {
        if app.entitlements.isEmpty {
            GGEmptyState(icon: "arrow.down.doc",
                         title: "Nothing to download",
                         message: "Files and licence keys you buy land here.")
                .padding(.top, 30)
        } else {
            ForEach(app.entitlements) { entitlement in
                EntitlementRow(entitlement: entitlement) {
                    app.openDownload(entitlement)
                }
            }
        }
    }
}

/// One order. The status word does the work at the top; the money and the one
/// live action are at the bottom.
struct ShopOrderRow: View {
    let order: ShopOrderDTO
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: order.state.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                Text(order.state.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer(minLength: 0)
                Text(BackendDate.relative(order.placedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(order.sellerName)
                    .font(.ggMono(9, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textTertiary)
                ForEach(order.lines) { line in
                    Text("\(line.quantity)× \(line.productName) · \(line.variantLabel)")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(1)
                }
            }

            if let note = order.trackingNote, !note.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .font(.system(size: 10))
                    Text(note)
                        .font(.system(size: 12))
                        .lineLimit(2)
                }
                .foregroundStyle(GGColor.textSecondary)
            }

            HStack(spacing: 10) {
                Text(order.totalLabel)
                    .font(.ggMono(15, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer(minLength: 0)
                actions
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
    }

    @ViewBuilder
    private var actions: some View {
        switch order.state {
        case .placed, .shipped:
            Button("Cancel", action: onCancel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
                .buttonStyle(.plain)
            Button(action: onConfirm) {
                Text("It arrived")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
        case .completed:
            Button(action: onReview) {
                Text("Review")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassCapsule(interactive: false)
            }
            .buttonStyle(PressableStyle())
        case .cancelled:
            EmptyView()
        }
    }
}

/// A download or a licence key. A key is shown in full and copyable — hiding
/// it behind a tap would be security theatre over something the buyer owns.
struct EntitlementRow: View {
    let entitlement: ShopEntitlementDTO
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: entitlement.isDownload ? "arrow.down.doc.fill" : "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entitlement.productName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(entitlement.fileName ?? (entitlement.isDownload ? "File" : "Licence key"))
                        .font(.system(size: 11))
                        .foregroundStyle(GGColor.textTertiary)
                }
                Spacer(minLength: 0)
                if entitlement.isDownload {
                    Button(action: onOpen) {
                        Text("Open")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(GGColor.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            if let key = entitlement.licenseKey, !key.isEmpty {
                Button {
                    UIPasteboard.general.string = key
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    HStack(spacing: 8) {
                        Text(key)
                            .font(.ggMono(12, .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                    .padding(10)
                    .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
    }
}

/// A verified-purchase review: the order it rides on is why it can be written
/// at all, so the sheet is opened from the order rather than from the product.
struct ShopReviewSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let order: ShopOrderDTO

    @State private var rating = 5
    @State private var body_: String = ""
    @State private var productID: UUID?
    @State private var posting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("How was it?")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
                .padding(.top, 20)

            if order.lines.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(order.lines) { line in
                            let active = (productID ?? order.lines.first?.productId) == line.productId
                            Button {
                                withAnimation(.ggSnappy) { productID = line.productId }
                            } label: {
                                Text(line.productName)
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
                    .padding(.horizontal, 18)
                }
            }

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggSnappy) { rating = star }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 24))
                            .foregroundStyle(star <= rating ? GGColor.white : GGColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("What should other buyers know?", text: $body_, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .lineLimit(3...6)
                .padding(12)
                .glass(cornerRadius: 14, tint: GGColor.ink(0.05))
                .padding(.horizontal, 18)

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
                    .padding(.horizontal, 18)
            }

            Button {
                post()
            } label: {
                Text(posting ? "Posting…" : "Post review")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(posting)
            .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
    }

    private func post() {
        guard let target = productID ?? order.lines.first?.productId else { return }
        posting = true
        error = nil
        Task {
            let failure = await app.reviewShopProduct(orderId: order.id, productId: target,
                                                      rating: rating, body: body_)
            posting = false
            if failure == nil { dismiss() } else { withAnimation(.ggSnappy) { error = failure } }
        }
    }
}
