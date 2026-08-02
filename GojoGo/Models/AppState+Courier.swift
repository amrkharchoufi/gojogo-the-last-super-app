import SwiftUI

// MARK: - Courier Mode, for real (Phase 4 M1)
//
// Courier Mode was the emptiest screen in the app. Everything a courier needs to
// *find* work — going online, reporting a position, an offer card, accepting it
// — has been real since Phase 3 M1, shared with Driver Mode because dispatch
// does not care what the job is. And then nothing happened, because nothing ever
// asked dispatch for a courier: `delivery` walked its orders along a simulated
// timeline and drew a courier from four hardcoded names.
//
// This file is the other half. Once a courier accepts a DELIVERY offer, there is
// an actual order to collect and hand over, and these are the only two verbs
// that belong to *this* module rather than to dispatch — which is why the file
// is short. A courier does not get a second copy of the availability toggle.

extension AppState {

    /// Whether the person on this screen is registered as a courier at all.
    var isCourier: Bool { dispatchWorkers.contains { $0.kind == "COURIER" } }

    // MARK: Reading

    /// The one delivery they are carrying, if any.
    ///
    /// Read from `delivery` rather than derived from `dispatchAssignment`: the
    /// assignment says which job, and this says what is in the bag, where the
    /// restaurant is, and what it pays. Two modules, two answers, and the app
    /// asks each of them for what it owns.
    func refreshCourierJob() async {
        guard backendConnected, isCourier else { return }
        do {
            courierJob = try await DeliveryStore.shared.courierJob()
        } catch {
            #if DEBUG
            print("Courier job refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    func refreshCourierDeliveries() async {
        guard backendConnected, isCourier else { return }
        courierDeliveries = (try? await DeliveryStore.shared.courierDeliveries()) ?? []
    }

    // MARK: The two verbs

    /// They have the food. From here the customer can no longer cancel, which
    /// is why it is a deliberate tap and not something the app infers from a
    /// position near the restaurant — being *at* a counter is not the same as
    /// having what is on it.
    func courierPickedUp() {
        guard let job = courierJob else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                courierJob = try await DeliveryStore.shared.courierPickedUp(job.id)
            } catch {
                showWalletNotice(Self.message(from: error,
                                              fallback: "Couldn't confirm the pickup."))
                await refreshCourierJob()
            }
        }
    }

    /// Handed over. This is the tap that settles the order and pays them — so
    /// the wallet is stale the moment it returns, and so is the dispatch
    /// registry, which has just freed them for the next offer.
    func courierDelivered() {
        guard let job = courierJob else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            do {
                _ = try await DeliveryStore.shared.courierDelivered(job.id)
                courierJob = nil
                await refreshCourierDeliveries()
                await refreshDispatch()
                await refreshWallet()
            } catch {
                showWalletNotice(Self.message(from: error,
                                              fallback: "Couldn't confirm the delivery."))
                await refreshCourierJob()
            }
        }
    }

    // MARK: What the dashboard renders

    /// "Collect from Forno Nero" / "Deliver to Home" — the one instruction that
    /// should be readable at a glance on a scooter.
    var courierInstruction: String? {
        guard let job = courierJob else { return nil }
        return job.isCollected ? "Deliver to \(job.addressLabel)"
                               : "Collect from \(job.merchantName)"
    }
}
