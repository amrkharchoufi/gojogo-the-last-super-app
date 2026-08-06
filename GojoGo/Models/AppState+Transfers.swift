import SwiftUI

// MARK: - Ownership transfers (Phase 5 · M2)
//
// Buying something with paperwork behind it — a car, a plot, a plate — where
// the thing that changes hands is a title rather than a parcel. Six states and
// two parties, and the order of them is the whole design: **the escrow comes
// before the document check**, so a reviewer's time is only ever spent on a
// deal that is real.
//
// Which end of it you are is not a mode the app is put into: `sellerId` and
// `buyerId` are on every row, so one screen renders both sides and the verbs
// available are whichever ones your id makes true. There is exactly one live
// escrow per listing, enforced server-side by a partial unique index — so a
// second enquiry on a listing already in escrow is refused, by the server, with
// the sentence this screen shows.

extension AppState {

    func openTransfers() {
        showTransfers = true
    }

    func closeTransfers() {
        showTransfers = false
        openTransferID = nil
        transferDocuments = []
    }

    /// Polled while the marketplace is on screen, so it diffs before it
    /// assigns: `transfers` lives on AppState, and reassigning an identical
    /// array republishes the whole app every 30 seconds for nothing.
    func refreshTransfers() async {
        guard backendConnected else { return }
        do {
            let mine = try await ShopStore.shared.transfers()
            guard mine != transfers else { return }
            withAnimation(.easeOut(duration: 0.2)) { transfers = mine }
        } catch {
            #if DEBUG
            print("Transfers refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// True when this account is the one selling — which decides whether the
    /// screen offers "name your price" or "pay". Read from `SocialStore`, which
    /// is where this app's own profile id lives; a transfer carries both ids
    /// precisely so one screen can serve both ends.
    func isTransferSeller(_ transfer: TransferDTO) -> Bool {
        transfer.sellerId == SocialStore.shared.myProfileId
    }

    var openTransfer: TransferDTO? {
        openTransferID.flatMap { id in transfers.first { $0.id == id } }
    }

    /// Starts (or reopens) an enquiry from a transfer listing. Free by design —
    /// nothing is held until `pay`, so asking about a car costs nothing.
    func startTransfer(listingId: UUID) {
        Task {
            do {
                let transfer = try await ShopStore.shared.inquire(listingId: listingId)
                withAnimation(.ggSnappy) {
                    if let index = transfers.firstIndex(where: { $0.id == transfer.id }) {
                        transfers[index] = transfer
                    } else {
                        transfers.insert(transfer, at: 0)
                    }
                    browsingProduct = nil
                    showTransfers = true
                    openTransferID = transfer.id
                }
            } catch {
                showEconomyNotice(Self.message(
                    from: error, fallback: "Couldn't open an enquiry on that listing."))
            }
        }
    }

    /// The seller names the number, and only the seller can. Returns nil on
    /// success.
    func acceptTransferOffer(_ transferId: UUID, priceCents: Int64) async -> String? {
        do {
            applyTransfer(try await ShopStore.shared.acceptTransfer(transferId,
                                                                    priceCents: priceCents))
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't set that price.")
        }
    }

    /// Moves the money into escrow. Over the platform's cap it comes back
    /// flagged for manual settlement rather than half-held — which the row then
    /// says out loud, because a buyer who has paid deserves to know a human is
    /// now involved.
    func payTransfer(_ transferId: UUID) {
        Task {
            do {
                let transfer = try await ShopStore.shared.payTransfer(transferId)
                applyTransfer(transfer)
                await refreshWallet()
                if transfer.flaggedManual {
                    showEconomyNotice("That's above the automatic limit — someone will settle it by hand.")
                }
            } catch {
                showEconomyNotice(Self.message(from: error, fallback: "Couldn't hold that payment."))
            }
        }
    }

    /// The buyer's "it's mine" — the tap that releases the escrow to the
    /// seller. Asked twice in the UI, because nothing undoes it.
    func confirmTransferReceived(_ transferId: UUID) {
        Task {
            do {
                applyTransfer(try await ShopStore.shared.confirmTransferReceived(transferId))
                await refreshWallet()
            } catch {
                showEconomyNotice(Self.message(from: error, fallback: "Couldn't confirm that."))
            }
        }
    }

    func cancelTransfer(_ transferId: UUID, note: String) {
        Task {
            do {
                applyTransfer(try await ShopStore.shared.cancelTransfer(
                    transferId, note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
                await refreshWallet()
            } catch {
                showEconomyNotice(Self.message(from: error, fallback: "Couldn't cancel that."))
            }
        }
    }

    // MARK: Paperwork

    func loadTransferDocuments(_ transferId: UUID) {
        Task {
            let documents = (try? await ShopStore.shared.transferDocuments(transferId)) ?? []
            guard openTransferID == transferId else { return }
            withAnimation(.easeOut(duration: 0.2)) { transferDocuments = documents }
        }
    }

    /// Uploads a title, a registration, a bill of sale. Private prefix, object
    /// key only — the read link a reviewer follows is minted for them, per ask.
    func uploadTransferDocument(_ transferId: UUID, data: Data, label: String,
                                contentType: String) async -> String? {
        do {
            let document = try await ShopStore.shared.uploadTransferDocument(
                transferId, data: data, label: label, contentType: contentType)
            withAnimation(.easeOut(duration: 0.2)) { transferDocuments.insert(document, at: 0) }
            return nil
        } catch {
            return Self.message(from: error, fallback: "Couldn't upload that document.")
        }
    }

    private func applyTransfer(_ transfer: TransferDTO) {
        withAnimation(.easeOut(duration: 0.2)) {
            if let index = transfers.firstIndex(where: { $0.id == transfer.id }) {
                transfers[index] = transfer
            } else {
                transfers.insert(transfer, at: 0)
            }
        }
    }
}
