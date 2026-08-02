import SwiftUI

// MARK: - The safety pack, on the trip screen (Phase 3 · Milestone 5)
//
// Three surfaces, and the design of each follows from how badly the moment is
// going for the person using it.
//
//   * **Share trip** is one tap and reversible. Somebody about to get into a
//     car should not have to think about it, and sharing by accident costs
//     nothing.
//   * **SOS** is one tap and a confirmation. An alarm raised by accident is a
//     person explaining themselves to their family at midnight; an alarm that
//     needs three taps is one nobody raises in time. Once raised it does not
//     un-raise — the flag is what an operator sees, and an alarm that can be
//     talked away is one somebody under pressure will be talked into removing.
//   * **The verification card** is the opposite: it is a bonus, it appears
//     after the trip, and it is entirely dismissible.
//
// Nothing here composes its own wording for the emergency number or the
// message. Both come from the server, because a client that wrote its own would
// eventually write a different one.

// MARK: Share + SOS, under the driver card

struct TripSafetyBar: View {
    @EnvironmentObject var app: AppState
    @State private var showingShareSheet = false
    @State private var shareText = ""

    var body: some View {
        HStack(spacing: 10) {
            shareButton
            sosButton
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityShareSheet(text: shareText)
        }
    }

    private var shareButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                guard let message = await app.shareTrip() else { return }
                shareText = message
                showingShareSheet = true
            }
        } label: {
            Label(app.tripShare == nil ? "Share trip" : "Share again",
                  systemImage: "location.north.line")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .glass(cornerRadius: 14)
        }
        .buttonStyle(PressableStyle())
        .disabled(app.shareBusy)
    }

    private var sosButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            app.confirmingSos = true
        } label: {
            Label("SOS", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.85, green: 0.16, blue: 0.16)))
        }
        .buttonStyle(PressableStyle())
        .disabled(app.sosBusy)
    }
}

/// The line under the driver card once a link is out, so "am I still sharing
/// this?" is answerable without opening anything.
struct TripShareStatus: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if let share = app.tripShare {
            HStack(spacing: 8) {
                Circle()
                    .fill(GGColor.accent)
                    .frame(width: 6, height: 6)
                Text(share.viewCount > 0
                     ? "Sharing this trip · opened \(share.viewCount)×"
                     : "Sharing this trip")
                    .font(.ggMono(11, .medium))
                    .foregroundStyle(GGColor.textSecondary)
                Spacer()
                Button {
                    Task { await app.stopSharingTrip() }
                } label: {
                    Text("Stop")
                        .font(.ggMono(11, .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: The SOS sheet

/// What SOS turns into: a number to dial and the contacts we could not reach on
/// our own.
///
/// The app does not place the call. It puts the number under a thumb — a phone
/// that starts dialling emergency services by itself is a phone people turn this
/// feature off on, and being one tap from it is the difference that matters.
struct SosSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL
    @State private var showingShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let sos = app.sos {
                        raised(sos)
                    } else {
                        confirmation
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .sheet(isPresented: $showingShareSheet) {
            ActivityShareSheet(text: app.sos?.message ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.sos == nil ? "SOS" : "SOS RAISED")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(app.sos == nil
                                     ? GGColor.textSecondary
                                     : Color(red: 0.85, green: 0.16, blue: 0.16))
                Text(app.sos == nil ? "Are you in trouble?" : "Help is being told")
                    .font(.gg(22, .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            Button { app.confirmingSos = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(GGColor.surface))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: Before

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This flags your trip for our team, tells your emergency contacts "
                 + "where you are, and gives you a live link to send anyone else.")
                .font(.gg(13))
                .foregroundStyle(GGColor.textPrimary)
            if app.emergencyContacts.isEmpty {
                Text("You haven't added any emergency contacts yet — you can still "
                     + "raise this, and we'll give you a link to send.")
                    .font(.gg(12))
                    .foregroundStyle(GGColor.textSecondary)
            }
            Text("It can't be undone.")
                .font(.gg(12, .semibold))
                .foregroundStyle(GGColor.textSecondary)

            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                Task { await app.raiseSos() }
            } label: {
                Text(app.sosBusy ? "Raising…" : "Raise SOS")
                    .font(.gg(16, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.85, green: 0.16, blue: 0.16)))
            }
            .buttonStyle(PressableStyle())
            .disabled(app.sosBusy)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 20)
    }

    // MARK: After

    private func raised(_ sos: SosDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // First and largest, because everything else on this screen is a
            // consolation prize next to it.
            Button {
                guard let url = app.emergencyDialURL else { return }
                openURL(url)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "phone.fill")
                    Text("Call \(sos.emergencyNumber)")
                }
                .font(.gg(17, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.85, green: 0.16, blue: 0.16)))
            }
            .buttonStyle(PressableStyle())

            VStack(alignment: .leading, spacing: 6) {
                Text(sos.notifiedCount > 0
                     ? "\(sos.notifiedCount) of your contacts \(sos.notifiedCount == 1 ? "has" : "have") been notified"
                     : "Your trip is flagged and a live link is ready")
                    .font(.gg(14, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                if !sos.unreachable.isEmpty {
                    Text("These aren't on GojoGo, so the message has to come from you:")
                        .font(.gg(12))
                        .foregroundStyle(GGColor.textSecondary)
                    ForEach(sos.unreachable) { contact in
                        contactRow(contact)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: 18)

            Button {
                showingShareSheet = true
            } label: {
                Label("Send my live link", systemImage: "square.and.arrow.up")
                    .font(.gg(14, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .glass(cornerRadius: 16)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func contactRow(_ contact: EmergencyContactDTO) -> some View {
        HStack(spacing: 10) {
            Text(contact.name)
                .font(.gg(14, .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Spacer()
            Button {
                guard let url = smsURL(to: contact.phone,
                                       body: app.sos?.message ?? "") else { return }
                openURL(url)
            } label: {
                Text("Text them")
                    .font(.ggMono(12, .semibold))
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(GGColor.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    /// The phone's own composer, pre-filled. It is the person's number the
    /// message arrives from, which is the whole reason this is not a server-side
    /// SMS even once one is possible.
    private func smsURL(to phone: String, body: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        let encoded = body.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics) ?? ""
        return URL(string: "sms:\(digits)&body=\(encoded)")
    }
}

// MARK: Community vehicle verification

/// The card that appears after a trip, asking whether the car was the car.
///
/// Five questions and no score. Each is a different way the car could be wrong,
/// and the server treats anything short of five yesses as a problem — so the
/// screen must not imply that four out of five is a pass, and must not let a
/// tired person tap through it in one gesture.
struct VehicleVerificationSheet: View {
    @EnvironmentObject var app: AppState
    let invite: VerificationInviteDTO

    @State private var driverMatched = true
    @State private var photosMatched = true
    @State private var plateMatched = true
    @State private var roadworthy = true
    @State private var noFraud = true
    @State private var comment = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    car
                    questions
                    if !allYes {
                        note
                    }
                    submit
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VERIFY A VEHICLE")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Text("Was it the right car?")
                    .font(.gg(22, .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            Button { app.openVerification = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(GGColor.surface))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var car: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(invite.carLine)
                .font(.gg(16, .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("You rode with \(invite.driverFirstName). Nobody but a passenger "
                 + "can check this — we only ever saw a photo of the paperwork.")
                .font(.gg(12))
                .foregroundStyle(GGColor.textSecondary)
            if invite.rewardMinor > 0 {
                Text("\(invite.rewardText) for answering")
                    .font(.ggMono(12, .semibold))
                    .foregroundStyle(GGColor.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18)
    }

    private var questions: some View {
        VStack(spacing: 0) {
            toggle("The driver was the person in the app", $driverMatched)
            Divider().overlay(GGColor.hairline)
            toggle("The car looked like its photos", $photosMatched)
            Divider().overlay(GGColor.hairline)
            toggle("The plate matched \(invite.vehiclePlate)", $plateMatched)
            Divider().overlay(GGColor.hairline)
            toggle("The car seemed roadworthy", $roadworthy)
            Divider().overlay(GGColor.hairline)
            toggle("Nothing about the trip felt like a scam", $noFraud)
        }
        .padding(.horizontal, 14)
        .glass(cornerRadius: 18)
    }

    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Text(label)
                .font(.gg(14))
                .foregroundStyle(GGColor.textPrimary)
        }
        .tint(GGColor.accent)
        .padding(.vertical, 12)
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tell us what was wrong")
                .font(.gg(13, .semibold))
                .foregroundStyle(GGColor.textPrimary)
            TextField("A different plate, a different driver…", text: $comment, axis: .vertical)
                .font(.gg(14))
                .lineLimit(2...4)
                .foregroundStyle(GGColor.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(GGColor.surface))
            // Said plainly, because it is a real consequence for a real person
            // and somebody flipping a switch deserves to know what it does.
            Text("This takes the driver off the road until somebody reviews it.")
                .font(.gg(12))
                .foregroundStyle(GGColor.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18)
    }

    private var submit: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                await app.answerVerification(invite,
                    driverMatched: driverMatched, photosMatched: photosMatched,
                    plateMatched: plateMatched, roadworthy: roadworthy,
                    noFraud: noFraud, comment: comment)
            }
        } label: {
            Text(app.verificationBusy
                 ? "Sending…"
                 : (allYes ? "Confirm this vehicle" : "Report a problem"))
                .font(.gg(16, .bold))
                .foregroundStyle(allYes ? GGColor.onAccent : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 16)
                    .fill(allYes ? GGColor.accent : Color(red: 0.85, green: 0.16, blue: 0.16)))
        }
        .buttonStyle(PressableStyle())
        .disabled(app.verificationBusy)
    }

    private var allYes: Bool {
        driverMatched && photosMatched && plateMatched && roadworthy && noFraud
    }
}

/// The prompt on the travel screen. Small, dismissible, and never in the way of
/// somebody trying to get somewhere.
struct VerificationInviteCard: View {
    @EnvironmentObject var app: AppState
    let invite: VerificationInviteDTO

    var body: some View {
        Button {
            app.openVerification = invite
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 18))
                    .foregroundStyle(GGColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Was \(invite.vehicleLabel) the right car?")
                        .font(.gg(14, .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(invite.rewardMinor > 0
                         ? "Takes a few seconds · \(invite.rewardText)"
                         : "Takes a few seconds")
                        .font(.ggMono(11, .medium))
                        .foregroundStyle(GGColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
            }
            .padding(14)
            .glass(cornerRadius: 18)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: The system share sheet

/// UIKit's share sheet, for the one thing SwiftUI's `ShareLink` cannot do here:
/// send a sentence the *server* wrote, with the link already inside it.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
    }
}
