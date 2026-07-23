import SwiftUI

/// Change-username flow: live availability check (debounced) + the server-side
/// 2-month cooldown surfaced to the user. The first username (set at onboarding)
/// is free; afterwards a change is allowed once every two months.
struct ChangeUsernameSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var handle = ""
    @State private var status: HandleStatusDTO?
    @State private var availability: HandleAvailabilityDTO?
    @State private var checking = false
    @State private var saving = false
    @State private var loadingStatus = true
    @State private var errorText: String?
    @State private var checkTask: Task<Void, Never>?

    private let availableColor = Color(hex: "26E0A8")
    private let takenColor = Color(hex: "F76D8A")

    private var normalized: String {
        handle.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
    }
    private var isCurrent: Bool { normalized == app.user.handle.lowercased() }
    private var cooldownActive: Bool { status?.canChangeNow == false }
    private var canSave: Bool {
        !saving && !cooldownActive && (availability?.available ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your username is how people find and mention you. You can change it once every two months.")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)

                    if cooldownActive, let date = status?.changeAvailableAt {
                        cooldownBanner(date: date)
                    }

                    usernameField
                    statusLine

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(takenColor)
                    }

                    saveButton
                }
                .padding(20)
            }
            .background(GGColor.bg.ignoresSafeArea())
            .navigationTitle("Username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GGColor.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await loadStatus() }
        .onChange(of: handle) { _, _ in scheduleCheck() }
    }

    // MARK: Field

    private var usernameField: some View {
        HStack(spacing: 4) {
            Text("@").foregroundStyle(GGColor.textSecondary)
            TextField("username", text: $handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(GGColor.textPrimary)
                .disabled(cooldownActive || loadingStatus)
        }
        .font(.system(size: 16, weight: .medium))
        .padding(14)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.1)
        .opacity(cooldownActive ? 0.5 : 1)
    }

    @ViewBuilder
    private var statusLine: some View {
        if loadingStatus {
            label("Loading…", color: GGColor.textTertiary, systemImage: nil, spinning: true)
        } else if cooldownActive {
            EmptyView()
        } else if normalized.count < 2 {
            label("At least 2 characters (letters, numbers, _ or .)",
                  color: GGColor.textTertiary, systemImage: nil)
        } else if isCurrent {
            label("This is your current username", color: GGColor.textTertiary, systemImage: nil)
        } else if checking {
            label("Checking availability…", color: GGColor.textTertiary, systemImage: nil, spinning: true)
        } else if let a = availability {
            if a.available {
                label("@\(a.normalized) is available", color: availableColor, systemImage: "checkmark.circle.fill")
            } else if a.reason == "taken" {
                label("That username is taken", color: takenColor, systemImage: "xmark.circle.fill")
            } else {
                label("Not a valid username", color: takenColor, systemImage: "xmark.circle.fill")
            }
        }
    }

    private func label(_ text: String, color: Color, systemImage: String?, spinning: Bool = false) -> some View {
        HStack(spacing: 6) {
            if spinning {
                ProgressView().scaleEffect(0.7)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(color)
    }

    private func cooldownBanner(date: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill").foregroundStyle(GGColor.textSecondary)
            Text("You can change your username again on \(Self.formatDate(date)).")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GGColor.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.1)
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            ZStack {
                if saving { ProgressView().tint(GGColor.onAccent) }
                else { Text("Save username") }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(GGColor.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(GGColor.white))
            .opacity(canSave ? 1 : 0.4)
        }
        .buttonStyle(PressableStyle())
        .disabled(!canSave)
    }

    // MARK: Networking

    private func loadStatus() async {
        handle = app.user.handle
        guard app.backendConnected else { loadingStatus = false; return }
        status = try? await ProfileStore.shared.handleStatus()
        loadingStatus = false
    }

    private func scheduleCheck() {
        errorText = nil
        availability = nil
        checkTask?.cancel()
        guard app.backendConnected, !cooldownActive,
              normalized.count >= 2, !isCurrent else { checking = false; return }
        checking = true
        let candidate = normalized
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            let result = try? await ProfileStore.shared.checkHandle(candidate)
            if Task.isCancelled || candidate != normalized { return }
            availability = result
            checking = false
        }
    }

    private func save() async {
        errorText = nil
        saving = true
        defer { saving = false }
        do {
            try await app.changeUsername(to: normalized)
            dismiss()
        } catch {
            errorText = error.localizedDescription
            // A cooldown/taken race — refresh the gate.
            status = try? await ProfileStore.shared.handleStatus()
        }
    }

    private static func formatDate(_ iso: String) -> String {
        guard let date = BackendDate.parse(iso) else { return iso }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}
