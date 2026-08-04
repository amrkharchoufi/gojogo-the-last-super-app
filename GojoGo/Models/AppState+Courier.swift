import SwiftUI

// MARK: - Courier Mode, for real (Phase 4 M1) — with a handoff that proves
// something (Phase 4 M2)
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
//
// M2 left both verbs where they were and changed what they carry. "I have the
// food" now takes the code the counter reads out, and "I handed it over" takes
// the customer's PIN, a photo, or neither, depending on the mode. Neither one
// throws on a wrong answer: a refusal comes back as a `HandoffResult` with the
// server's own sentence, and this file's job is to hold that sentence on screen
// without losing what the courier typed to get it.

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
            let fresh = try await DeliveryStore.shared.courierJob()
            // This runs on a four-second poll, so it must not be allowed to wipe
            // a refusal the courier is still reading. Only a *different* job —
            // or the same one that has moved — clears the handoff state.
            if fresh?.id != courierJob?.id || fresh?.status != courierJob?.status {
                clearCourierHandoff()
            }
            courierJob = fresh
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

    /// Forgets the last refusal. Called when the job moves, and after a success.
    func clearCourierHandoff() {
        courierHandoffNotice = nil
        courierAttemptsLeft = -1
        courierSupportUnlocked = false
    }

    // MARK: The two verbs

    /// They have the food, and can prove they were told so at the counter.
    ///
    /// From here the customer can no longer cancel, which is why it is a
    /// deliberate tap and not something the app infers from a position near the
    /// restaurant — being *at* a counter is not the same as having what is on
    /// it. The code is the same fact stated harder: the only way to know it is
    /// to be standing where somebody can read it to you.
    ///
    /// A wrong code is not an error and is not treated like one. The typed
    /// digits stay in the field, because a courier who mistyped one of six is
    /// being asked to fix a digit, not to start again with cold food in a bag.
    func courierPickedUp(code: String) {
        guard let job = courierJob, !courierHandoffBusy else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        courierHandoffBusy = true
        Task {
            defer { courierHandoffBusy = false }
            do {
                let result = try await DeliveryStore.shared
                    .courierPickedUp(job.id, code: code.filter(\.isNumber))
                apply(result)
                if result.accepted {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            } catch {
                // A genuine failure — the wrong status, somebody else's order, a
                // dead network. Not a wrong code, which never gets here.
                courierHandoffNotice = Self.message(from: error,
                                                    fallback: "Couldn't confirm the pickup.")
                await refreshCourierJob()
            }
        }
    }

    /// Handed over. This is the tap that settles the order and pays them — so
    /// the wallet is stale the moment it returns, and so is the dispatch
    /// registry, which has just freed them for the next offer.
    ///
    /// `pin` is nil for a CONFIRM order and for the photo path, and that is
    /// different from an empty string — which is why an empty one is sent
    /// through as an empty one rather than tidied into nil on the way out.
    ///
    /// **An empty PIN is a deliberate submission and the server counts it as a
    /// wrong attempt on purpose.** A courier at a door nobody answers has no
    /// PIN to type and never will have, and three empty submissions are the
    /// route to the photo fallback that exists for exactly that doorstep. So
    /// nothing here — and nothing on the screen — may quietly refuse to send
    /// one: coercing it to nil would ask the server the CONFIRM question
    /// instead, and closing the button on an empty field would leave somebody
    /// standing outside a silent flat with no way forward at all.
    func courierDelivered(pin: String?) {
        guard let job = courierJob, !courierHandoffBusy else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        courierHandoffBusy = true
        Task {
            defer { courierHandoffBusy = false }
            do {
                let result = try await DeliveryStore.shared
                    .courierDelivered(job.id, pin: pin.map { $0.filter(\.isNumber) })
                if result.accepted {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    clearCourierHandoff()
                    courierJob = nil
                    await refreshCourierDeliveries()
                    await refreshDispatch()
                    await refreshWallet()
                    await refreshWorkerWallet()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    apply(result)
                }
            } catch {
                courierHandoffNotice = Self.message(from: error,
                                                    fallback: "Couldn't confirm the delivery.")
                await refreshCourierJob()
            }
        }
    }

    /// The contactless path, and the way out of a PIN nobody can produce.
    ///
    /// Presign, PUT the bytes to the URL the server signed, then hand over with
    /// no pin. Nothing about the object is the app's to choose: the server mints
    /// the key, stamps it on the order in the same transaction, and names the
    /// content type — so there is no key travelling back up to be swapped, and
    /// no format for this app to negotiate.
    ///
    /// Which is why the bytes are re-encoded rather than sent as picked. A
    /// signature is over a `Content-Type`, and an iPhone hands the library
    /// picker HEIC: PUT those bytes under the `image/jpeg` the server signed and
    /// the customer's proof of delivery is a file nothing will open. Downscaled
    /// on the way through as well — this is evidence of a doorstep, not a
    /// photograph of one, and it is uploaded on cellular by somebody who wants
    /// to get back on the scooter.
    ///
    /// Three steps, one spinner. A courier standing at a door does not care
    /// which of them is running, only whether they can put the phone away.
    func courierHandOverWithPhoto(_ picked: Data) {
        guard let job = courierJob, !courierProofUploading, !courierHandoffBusy else { return }
        // The flag goes up before the re-encode, not after it: decoding and
        // scaling a 12-megapixel photo is long enough to be felt, and a screen
        // that sits there doing nothing visible is a screen somebody taps again.
        courierProofUploading = true
        guard let jpeg = Self.proofJpeg(picked) else {
            courierProofUploading = false
            courierHandoffNotice = "Couldn't read that photo — try taking another."
            return
        }
        Task {
            do {
                let presign = try await DeliveryStore.shared.courierProofUpload(job.id)
                try await APIClient.shared.upload(to: presign.uploadUrl, data: jpeg,
                                                  contentType: presign.contentType)
                courierProofUploading = false
                courierDelivered(pin: nil)
            } catch {
                courierProofUploading = false
                courierHandoffNotice = Self.message(from: error,
                                                    fallback: "Couldn't send that photo.")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    /// A picked image as JPEG bytes, no longer than 1600px on its long edge.
    /// Nil only when the data was not an image at all, which is the one case
    /// worth telling the courier about rather than uploading anyway.
    private static func proofJpeg(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 1600 else { return image.jpegData(compressionQuality: 0.8) }
        let scale = 1600 / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let scaled = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: 0.8)
    }

    /// Adopts a refusal: the server's sentence, the count, and whether the
    /// photo fallback has opened. Never composes a message of its own — only
    /// the server knows whether this was the attempt that ran out.
    private func apply(_ result: HandoffResultDTO) {
        if let job = result.job { courierJob = job }
        courierHandoffNotice = result.accepted ? nil : result.message
        courierAttemptsLeft = result.attemptsLeft
        courierSupportUnlocked = result.supportUnlocked
    }

    // MARK: Talking to the person waiting

    /// Opens the thread the server made when this delivery was assigned.
    ///
    /// The same navigation as the marketplace's "Message seller" — leave the
    /// cover, land in My World, open the id — because there is one way into a
    /// conversation in this app. What a courier needs it for is the half of a
    /// delivery an address cannot carry: which gate, which bell, whether the
    /// dog is friendly.
    func messageDeliveryCustomer() {
        guard let id = courierJob?.conversationId else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        closePartnerDashboard()
        openJobConversation(id)
    }

    // MARK: What the dashboard renders

    /// "Collect from Forno Nero" / "Deliver to Home" — the one instruction that
    /// should be readable at a glance on a scooter.
    ///
    /// On a multi-stop run (Phase 4 M3) it names the counter that is next, not
    /// the order: a courier at the second restaurant needs to read one line and
    /// know where they are standing.
    var courierInstruction: String? {
        guard let job = courierJob else { return nil }
        return job.isCollected ? "Deliver to \(job.addressLabel)"
                               : "Collect from \(job.merchantName)"
    }

    /// "Pickup 2 of 3" — drawn only when there is more than one counter, since
    /// a run of one has nothing to count.
    var courierStopProgress: String? {
        guard let job = courierJob, job.hasMultipleStops, !job.isCollected else { return nil }
        let done = job.counters.filter(\.collected).count
        return "Pickup \(done + 1) of \(job.counters.count)"
    }

    /// The stops still to collect, so the screen can list the counters after
    /// this one — a courier planning a route wants to know the second stop
    /// before they leave the first.
    var courierRemainingStops: [CourierStopDTO] {
        guard let job = courierJob, !job.isCollected else { return [] }
        return job.remainingStops
    }

    /// Whether the camera is the thing to lead with, for either of the two
    /// reasons it can be.
    ///
    /// The first is what the customer asked for: a `PHOTO` order is somebody
    /// saying *leave it at the door*, and leading with a PIN field on it would
    /// be the app quietly not passing on an instruction — the courier knocks,
    /// waits, and eventually discovers from a refusal message what the person
    /// inside told us twenty minutes ago. The second is the fallback: the PIN
    /// has been failed to the limit and the server has said the photo is now
    /// the only thing that will work.
    ///
    /// Both promote the camera and neither *hides* anything — the PIN field
    /// stays on screen underneath, which is what keeps a mode the app has
    /// misread from ever dead-ending a delivery. The emphasis is a guess the
    /// screen is allowed to make; what completes the handoff is still only ever
    /// the server's answer.
    var courierPhotoIsTheWayOut: Bool {
        guard let job = courierJob, job.isCollected else { return false }
        return courierSupportUnlocked || job.wantsPhoto
    }
}
