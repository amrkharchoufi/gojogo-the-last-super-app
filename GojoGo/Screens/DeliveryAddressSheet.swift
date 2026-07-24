import SwiftUI
import CoreLocation

// MARK: - Delivery addresses
//
// Where an order goes. Saved addresses live on the account (the `delivery`
// module), so the choice follows the user to another device instead of being a
// constant baked into the order call. Surfaces on tinted glass, matching the
// rest of GojoDelivery.

struct DeliveryAddressSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// Non-nil while the form is open: nil id = a new address, an id = editing.
    @State private var form: AddressForm? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            if let form {
                AddressFormView(form: form,
                                onCancel: { withAnimation(.ggSnappy) { self.form = nil } },
                                onSave: { save($0) })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                addressList
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .animation(.ggSnappy, value: form?.id)
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text(form == nil ? "Deliver to"
                             : (form?.editingID == nil ? "New address" : "Edit address"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text(form == nil ? "Where should we bring your order?"
                             : "Street, then anything the courier needs")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: Saved addresses

    private var addressList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if app.deliveryAddresses.isEmpty {
                    emptyState
                } else {
                    ForEach(app.deliveryAddresses) { address in
                        addressRow(address)
                    }
                }
                addButton
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private func addressRow(_ address: DeliveryAddress) -> some View {
        let selected = app.selectedDeliveryAddress?.id == address.id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            app.selectDeliveryAddress(address.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: address.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? GGColor.onAccent : GGColor.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(selected ? GGColor.white : GGColor.ink(0.08)))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(address.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                        if address.isDefault {
                            Text("DEFAULT")
                                .font(.ggMono(9, .semibold))
                                .tracking(0.6)
                                .foregroundStyle(GGColor.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(GGColor.ink(0.08)))
                        }
                    }
                    Text(address.line1)
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(1)
                    if !address.note.isEmpty {
                        Text(address.note)
                            .font(.system(size: 11))
                            .foregroundStyle(GGColor.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                }
                Menu {
                    Button {
                        withAnimation(.ggSnappy) { form = AddressForm(address) }
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        app.deleteDeliveryAddress(address.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textTertiary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
            }
            .padding(12)
            .glass(cornerRadius: 18, tint: GGColor.ink(selected ? 0.10 : 0.05))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var addButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.ggSnappy) { form = AddressForm() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("Add an address")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(GGColor.textPrimary)
            .padding(14)
            .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(GGColor.textTertiary)
            Text("No saved addresses")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Add one so a courier knows where to go.")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
    }

    private func save(_ form: AddressForm) {
        app.saveDeliveryAddress(editing: form.editingID,
                                label: form.label,
                                line1: form.line1,
                                note: form.note,
                                latitude: form.latitude,
                                longitude: form.longitude,
                                makeDefault: form.editingID == nil)
        withAnimation(.ggSnappy) { self.form = nil }
        dismiss()
    }
}

// MARK: - Add / edit form

/// Identifiable so the sheet can animate between "list" and "form".
struct AddressForm: Identifiable {
    let id = UUID()
    var editingID: UUID? = nil
    var label: String = "Home"
    var line1: String = ""
    var note: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil

    init() {}

    init(_ address: DeliveryAddress) {
        editingID = address.id
        label = address.label
        line1 = address.line1
        note = address.note
        latitude = address.latitude
        longitude = address.longitude
    }
}

private struct AddressFormView: View {
    @State var form: AddressForm
    var onCancel: () -> Void
    var onSave: (AddressForm) -> Void

    @State private var locating = false
    @State private var locationError: String? = nil
    @FocusState private var streetFocused: Bool

    private let presetLabels = ["Home", "Work", "Other"]

    private var canSave: Bool {
        !form.line1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    labelPicker
                    fieldBox(title: "Street") {
                        TextField("12 Rue Atlas, Casablanca", text: $form.line1, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...3)
                            .focused($streetFocused)
                    }
                    fieldBox(title: "Note for the courier") {
                        TextField("Floor 3, blue door, ring twice", text: $form.note, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...3)
                    }
                    locateButton
                    if let locationError {
                        Text(locationError)
                            .font(.system(size: 11))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            actions
        }
        .onAppear { streetFocused = form.editingID == nil }
    }

    private var labelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LABEL")
                .font(.ggMono(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            HStack(spacing: 8) {
                ForEach(presetLabels, id: \.self) { preset in
                    let active = form.label.caseInsensitiveCompare(preset) == .orderedSame
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggSnappy) { form.label = preset }
                    } label: {
                        Text(preset)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func fieldBox<Content: View>(title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.ggMono(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            content()
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .glass(cornerRadius: 16, tint: GGColor.ink(0.05))
        }
    }

    private var locateButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            useCurrentLocation()
        } label: {
            HStack(spacing: 10) {
                if locating {
                    ProgressView().controlSize(.small).tint(GGColor.textSecondary)
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(locating ? "Finding you…" : "Use my current location")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(GGColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glass(cornerRadius: 16, tint: GGColor.ink(0.04))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(locating)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 15)
                    .glassCapsule()
            }
            .buttonStyle(PressableStyle())

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSave(form)
            } label: {
                Text("Save address")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    /// One-shot GPS fix + reverse geocode, reusing the provider the chat
    /// location pin already uses.
    private func useCurrentLocation() {
        locating = true
        locationError = nil
        Task { @MainActor in
            defer { locating = false }
            do {
                let place = try await LiveLocationProvider.shared.currentPlace()
                form.line1 = place.name
                form.latitude = place.coordinate.latitude
                form.longitude = place.coordinate.longitude
            } catch LiveLocationProvider.LocationError.denied {
                locationError = "Location is off for GojoGo — type the street instead."
            } catch {
                locationError = "Couldn't get a fix — type the street instead."
            }
        }
    }
}
