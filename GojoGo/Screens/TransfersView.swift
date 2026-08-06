import SwiftUI
import UniformTypeIdentifiers

// MARK: - Ownership transfers (Phase 5 · M2)
//
// A car, a plot, a plate — anything where what changes hands is a title rather
// than a parcel. One screen serves both ends: every row carries both ids, so
// whether you see "name your price" or "pay" is a fact about you and not a mode
// the app was put into.
//
// The order of the machine is the part worth understanding, and the screen
// spells it out rather than hiding it behind a progress bar: **the money goes
// into escrow before anybody checks the paperwork.** That is deliberate — a
// reviewer's time is only ever spent on a deal that is real — and it means a
// buyer who has paid is *waiting on a human*, which is the one state where
// silence would be unbearable. So `PAYMENT_HELD` says so in as many words.

struct TransfersView: View {
    @EnvironmentObject var app: AppState

    @State private var pricing: TransferDTO?
    @State private var cancelling: TransferDTO?
    @State private var confirmingReceipt: TransferDTO?
    @State private var uploadingFor: TransferDTO?
    @State private var pickingDocument = false
    @State private var uploading = false

    var body: some View {
        VStack(spacing: 0) {
            if let notice = app.economyNotice {
                EconomyNoticeBanner(message: notice) { app.dismissEconomyNotice() }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if app.transfers.isEmpty {
                        GGEmptyState(icon: "doc.text.magnifyingglass",
                                     title: "No transfers",
                                     message: "Enquiries on listings that come with paperwork show up here.")
                            .padding(.top, 30)
                    } else {
                        ForEach(app.transfers) { transfer in
                            row(transfer)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .refreshable { await app.refreshTransfers() }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .animation(.ggOverlay, value: app.economyNotice)
        .task { await app.refreshTransfers() }
        .sheet(item: $pricing) { transfer in
            TransferPriceSheet(transfer: transfer)
                .environmentObject(app)
                .presentationDetents([.height(280)])
                .presentationBackground(GGColor.sheetBG)
        }
        .alert("Confirm it's yours?", isPresented: Binding(
            get: { confirmingReceipt != nil },
            set: { if !$0 { confirmingReceipt = nil } }
        )) {
            Button("Not yet", role: .cancel) { confirmingReceipt = nil }
            Button("It's mine") {
                if let transfer = confirmingReceipt { app.confirmTransferReceived(transfer.id) }
                confirmingReceipt = nil
            }
        } message: {
            Text("This releases the escrow to the seller. Only do it once the title is actually in your name.")
        }
        .alert("Cancel this transfer?", isPresented: Binding(
            get: { cancelling != nil },
            set: { if !$0 { cancelling = nil } }
        )) {
            Button("Keep it", role: .cancel) { cancelling = nil }
            Button("Cancel", role: .destructive) {
                if let transfer = cancelling {
                    app.cancelTransfer(transfer.id, note: "Cancelled in app")
                }
                cancelling = nil
            }
        } message: {
            Text("Anything held goes back to the buyer in full.")
        }
        // Presentation and target are kept apart on purpose. Driving
        // `isPresented` off `uploadingFor` meant dismissal cleared the very
        // thing `onCompletion` needs, and the two orderings are not ours to
        // guarantee — a race whose losing side is a file that silently never
        // uploads. A plain flag presents; `uploadingFor` only carries the target.
        .fileImporter(isPresented: $pickingDocument,
                      allowedContentTypes: [.pdf, .image, .data],
                      allowsMultipleSelection: false) { result in
            handleDocument(result)
        }
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text("Transfers")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Deals with paperwork behind them")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private func row(_ transfer: TransferDTO) -> some View {
        let selling = app.isTransferSeller(transfer)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(selling ? "SELLING" : "BUYING")
                    .font(.ggMono(9, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(GGColor.textTertiary)
                Spacer(minLength: 0)
                Text(transfer.step.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.listingTitle ?? "Listing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                if let vin = transfer.vinSerial, !vin.isEmpty {
                    Text(vin)
                        .font(.ggMono(11))
                        .foregroundStyle(GGColor.textTertiary)
                }
                Text(transfer.priceCents == nil ? "No price agreed yet" : transfer.priceLabel)
                    .font(.ggMono(15, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }

            Text(selling ? sellerHint(transfer) : transfer.step.buyerHint)
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if transfer.flaggedManual {
                Text("Above the automatic limit — this one is being settled by hand.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }

            actions(transfer, selling: selling)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
        .onAppear {
            if app.openTransferID == nil { app.openTransferID = transfer.id }
        }
    }

    /// "Papers" until the server has told us how many; the count once it has.
    /// A backend without the field is not the same as a transfer with nothing
    /// attached, so the bare label stands in rather than a confident "0".
    private func attachedLabel(_ transfer: TransferDTO) -> String {
        guard let count = transfer.documentCount else { return "Papers" }
        return count == 0 ? "Papers" : "Papers \(count)"
    }

    private func attachedAccessibilityLabel(_ transfer: TransferDTO) -> String {
        guard let count = transfer.documentCount else { return "Papers" }
        switch count {
        case 0:  return "Papers, none attached"
        case 1:  return "Papers, 1 attached"
        default: return "Papers, \(count) attached"
        }
    }

    private func sellerHint(_ transfer: TransferDTO) -> String {
        switch transfer.step {
        case .inquiry: return "Somebody's interested. Name a price to move it on."
        case .offerAccepted: return "Waiting for them to pay into escrow."
        case .paymentHeld:
            // Still asking for papers after they've been sent reads as though
            // the upload didn't take.
            if let count = transfer.documentCount, count > 0 {
                return "Money is held. Your paperwork is with a reviewer."
            }
            return "Money is held. Upload the paperwork so a reviewer can check it."
        case .docsConfirmed: return "Papers checked. Hand it over and they'll confirm."
        case .transferred: return "They've confirmed — the money is on its way to you."
        case .released: return "Paid."
        case .cancelled: return "Cancelled."
        }
    }

    @ViewBuilder
    private func actions(_ transfer: TransferDTO, selling: Bool) -> some View {
        HStack(spacing: 10) {
            // Seller only. `presign`/`attach` both 404 anyone who isn't the
            // seller, so offering this to the buyer was a button whose only
            // possible outcome was an error — and the paperwork is the
            // seller's to produce anyway.
            if selling, transfer.step == .paymentHeld || transfer.step == .docsConfirmed {
                Button {
                    app.openTransferID = transfer.id
                    app.loadTransferDocuments(transfer.id)
                    uploadingFor = transfer
                    pickingDocument = true
                } label: {
                    HStack(spacing: 5) {
                        if uploading { ProgressView().tint(GGColor.textPrimary) }
                        Image(systemName: "paperclip")
                            .font(.system(size: 11, weight: .semibold))
                        // The count is the receipt. Without it an upload that
                        // silently failed looked exactly like one that worked.
                        Text(attachedLabel(transfer))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .glassCapsule(interactive: false)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(attachedAccessibilityLabel(transfer))
            }

            Spacer(minLength: 0)

            switch (transfer.step, selling) {
            case (.inquiry, true):
                primary("Name a price") { pricing = transfer }
            case (.inquiry, false):
                Text("Waiting on them")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textTertiary)
            case (.offerAccepted, false):
                secondary("Cancel") { cancelling = transfer }
                primary("Pay \(transfer.priceLabel)") { app.payTransfer(transfer.id) }
            case (.paymentHeld, false):
                secondary("Cancel + refund") { cancelling = transfer }
            case (.docsConfirmed, false):
                primary("It's mine") { confirmingReceipt = transfer }
            default:
                EmptyView()
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(GGColor.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(GGColor.textSecondary)
            .buttonStyle(.plain)
    }

    private func handleDocument(_ result: Result<[URL], Error>) {
        let transfer = uploadingFor
        uploadingFor = nil
        guard case .success(let urls) = result, let url = urls.first,
              let transfer else { return }
        uploading = true
        Task {
            defer { uploading = false }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // A paper that can't be read is worth saying out loud: the reviewer
            // is waiting on it, and silence here reads as "sent".
            guard let data = try? Data(contentsOf: url) else {
                app.showEconomyNotice("Couldn't read that file.")
                return
            }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            if let failure = await app.uploadTransferDocument(
                transfer.id, data: data,
                label: url.lastPathComponent, contentType: type) {
                app.showEconomyNotice(failure)
                return
            }
            // The count lives on the transfer, not on the upload's reply, so
            // the card only says "Papers 1" once the row is re-read.
            await app.refreshTransfers()
        }
    }
}

/// The seller's number. Nothing is held by naming it — the buyer's `pay` is
/// what moves money — so this sheet is a price, not a charge.
struct TransferPriceSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let transfer: TransferDTO
    @State private var price = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text("Name your price")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(transfer.listingTitle ?? "This listing")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }
            .padding(.top, 20)

            TextField("0.00", text: $price)
                .keyboardType(.decimalPad)
                .font(.ggMono(26, .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .padding(14)
                .glass(cornerRadius: 16, tint: GGColor.ink(0.06))
                .padding(.horizontal, 18)

            Text("They pay this into escrow. It only reaches you once the paperwork is checked and they confirm the transfer.")
                .font(.system(size: 11))
                .foregroundStyle(GGColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }

            Button {
                guard let cents = EconomyStore.parseCents(price), cents > 0 else {
                    withAnimation(.ggSnappy) { error = "Put a number in." }
                    return
                }
                saving = true
                error = nil
                Task {
                    let failure = await app.acceptTransferOffer(transfer.id, priceCents: cents)
                    saving = false
                    if failure == nil { dismiss() } else {
                        withAnimation(.ggSnappy) { error = failure }
                    }
                }
            } label: {
                Text(saving ? "Setting…" : "Set price")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(saving)
            .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
    }
}
