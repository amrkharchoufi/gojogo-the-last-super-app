import SwiftUI

// MARK: - Emergency contacts (Phase 3 · Milestone 5)
//
// The list SOS reaches. Two things about it are deliberate and easy to get
// wrong:
//
//   * **A phone number is all it takes.** Most people's emergency contact is
//     not on GojoGo, and a picker that only offered accounts would leave this
//     list empty for almost everybody at the moment it mattered. A contact who
//     *is* on GojoGo gets a push the instant the button is pressed; everybody
//     else gets a message sent from the person's own phone, from their own
//     number, which is the one their family actually opens.
//   * **The screen says what it can and cannot do.** It does not promise that
//     these people will be called. It promises they will be told, and shows how.

struct EmergencyContactsView: View {
    @EnvironmentObject var app: AppState

    @State private var name = ""
    @State private var phone = ""
    @State private var relationship = ""
    @State private var adding = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    explainer
                    if app.emergencyContacts.isEmpty && !adding {
                        empty
                    } else {
                        ForEach(app.emergencyContacts) { contact in
                            row(contact)
                        }
                    }
                    if adding {
                        form
                    } else if app.emergencyContacts.count < app.emergencyContactsMax {
                        addButton
                    } else {
                        Text("That's the maximum of \(app.emergencyContactsMax). "
                             + "Remove one to add somebody else.")
                            .font(.gg(12))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .task { await app.loadEmergencyContacts() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EMERGENCY CONTACTS")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Text(app.emergencyContacts.isEmpty
                     ? "Nobody yet"
                     : "\(app.emergencyContacts.count) of \(app.emergencyContactsMax)")
                    .font(.gg(22, .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            Button { app.showEmergencyContacts = false } label: {
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

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("If you press SOS during a trip, these are the people we tell.")
                .font(.gg(13))
                .foregroundStyle(GGColor.textPrimary)
            Text("Anyone who is also on GojoGo gets a notification straight away, "
                 + "with a link that follows your trip live. For everybody else we "
                 + "write the message and your phone sends it — so it arrives from "
                 + "your number, not from an app they've never heard of.")
                .font(.gg(12))
                .foregroundStyle(GGColor.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.badge.key")
                .font(.system(size: 28))
                .foregroundStyle(GGColor.textSecondary)
            Text("No contacts yet")
                .font(.gg(15, .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text("This takes a minute now and nothing at all later.")
                .font(.gg(12))
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: Rows

    private func row(_ contact: EmergencyContactDTO) -> some View {
        HStack(spacing: 12) {
            UserAvatar(size: 40, letter: String(contact.name.prefix(1)), imageURL: nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.gg(15, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                HStack(spacing: 6) {
                    Text(contact.phone)
                        .font(.ggMono(12))
                        .foregroundStyle(GGColor.textSecondary)
                    if let relationship = contact.relationship, !relationship.isEmpty {
                        Text("· \(relationship)")
                            .font(.gg(12))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                }
                // The one fact that changes what happens when the button is
                // pressed, so it is said on the row rather than in a footnote.
                Text(contact.linkedProfileId == nil
                     ? "You'll send them a message"
                     : "Gets a notification instantly")
                    .font(.ggMono(10, .medium))
                    .foregroundStyle(contact.linkedProfileId == nil
                                     ? GGColor.textSecondary : GGColor.accent)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await app.removeEmergencyContact(contact.id) }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(GGColor.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glass(cornerRadius: 18)
    }

    private var addButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { adding = true }
            nameFocused = true
        } label: {
            Label("Add a contact", systemImage: "plus")
                .font(.gg(14, .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .glass(cornerRadius: 16)
        }
        .buttonStyle(PressableStyle())
    }

    private var form: some View {
        VStack(spacing: 10) {
            field("Name", text: $name, keyboard: .default).focused($nameFocused)
            field("Phone number", text: $phone, keyboard: .phonePad)
            field("Relationship (optional)", text: $relationship, keyboard: .default)
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { adding = false }
                    clear()
                } label: {
                    Text("Cancel")
                        .font(.gg(14, .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glass(cornerRadius: 14)
                }
                .buttonStyle(PressableStyle())

                Button {
                    Task {
                        await app.addEmergencyContact(
                            name: name.trimmingCharacters(in: .whitespaces),
                            phone: phone.trimmingCharacters(in: .whitespaces),
                            relationship: relationship.trimmingCharacters(in: .whitespaces))
                        withAnimation(.easeInOut(duration: 0.2)) { adding = false }
                        clear()
                    }
                } label: {
                    Text(app.emergencyContactsBusy ? "Saving…" : "Save")
                        .font(.gg(14, .semibold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(GGColor.accent))
                }
                .buttonStyle(PressableStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
            }
        }
        .padding(14)
        .glass(cornerRadius: 18)
    }

    private func field(_ placeholder: String, text: Binding<String>,
                       keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .font(.gg(15))
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .phonePad ? .never : .words)
            .autocorrectionDisabled(keyboard == .phonePad)
            .foregroundStyle(GGColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(GGColor.surface))
    }

    private var canSave: Bool {
        !app.emergencyContactsBusy
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && phone.trimmingCharacters(in: .whitespaces).count >= 3
    }

    private func clear() {
        name = ""
        phone = ""
        relationship = ""
    }
}
