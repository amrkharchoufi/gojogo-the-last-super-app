import SwiftUI
import PhotosUI

/// Your business profiles, and which identity new content is published under
/// (Phase 2e · Milestone 1).
///
/// There is no "business app" here and there never will be: a business is a
/// profile, so its page is the ordinary profile screen and its posts go through
/// the ordinary composer. This sheet only does the two things that are actually
/// new — create one, and switch which one you're publishing as.
struct BusinessProfilesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var creating = false
    @State private var editing: BusinessIdentity?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Publishing as")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)

                    VStack(spacing: 8) {
                        identityRow(name: app.user.name, handle: app.user.handle,
                                    avatarURL: app.user.avatarURL, category: "You",
                                    verified: false, active: app.actingBusinessID == nil) {
                            app.stopActingAsBusiness()
                        }
                        ForEach(app.ownedBusinesses) { business in
                            identityRow(name: business.name, handle: business.handle,
                                        avatarURL: business.avatarURL,
                                        category: business.category,
                                        verified: business.verified,
                                        active: app.actingBusinessID == business.id,
                                        onSelect: { app.actAsBusiness(business.id) },
                                        onOpen: { app.openBusinessProfile(business) },
                                        onEdit: { editing = business })
                        }
                    }

                    if app.ownedBusinesses.isEmpty {
                        emptyExplainer
                    }

                    Button {
                        creating = true
                    } label: {
                        Label("Create business profile", systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GGColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .buttonStyle(PressableStyle())

                    Text("A business profile is a profile: it can be followed, post, and run stories from day one. Selling comes later — that needs an approved application, which is also what earns the verified badge.")
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textTertiary)
                }
                .padding(20)
            }
            .background(GGColor.bg.ignoresSafeArea())
            .navigationTitle("Business profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GGColor.textSecondary)
                }
            }
            .overlay(alignment: .bottom) {
                if let notice = app.businessNotice {
                    Text(notice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .glass(cornerRadius: 14, fillOpacity: 0.12, borderOpacity: 0.16)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await app.refreshBusinessProfiles() }
        .sheet(isPresented: $creating) {
            BusinessEditorSheet(business: nil).environmentObject(app)
        }
        .sheet(item: $editing) { business in
            BusinessEditorSheet(business: business).environmentObject(app)
        }
    }

    private var emptyExplainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You don't run a business yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Create one to publish as your brand — same followers, same feed, its own name and page.")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.1)
    }

    private func identityRow(name: String, handle: String, avatarURL: String?,
                             category: String, verified: Bool, active: Bool,
                             onSelect: @escaping () -> Void,
                             onOpen: (() -> Void)? = nil,
                             onEdit: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    UserAvatar(size: 42, gradient: SocialStore.gradient(for: handle),
                               imageURL: avatarURL)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(GGColor.textPrimary)
                            if verified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(GGColor.textPrimary)
                            }
                        }
                        Text("@\(handle) · \(category)")
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: active ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(active ? GGColor.textPrimary : GGColor.ink(0.35))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if onOpen != nil || onEdit != nil {
                Menu {
                    if let onOpen {
                        Button { onOpen() } label: { Label("Open page", systemImage: "person.crop.square") }
                    }
                    if let onEdit {
                        Button { onEdit() } label: { Label("Edit details", systemImage: "pencil") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(12)
        .glass(cornerRadius: 16, fillOpacity: active ? 0.10 : 0.05, borderOpacity: active ? 0.18 : 0.1)
    }
}

/// Create or edit one business profile. The same form both ways — the only
/// difference is which call it makes and that a username is only auto-derived
/// when creating.
struct BusinessEditorSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let business: BusinessIdentity?

    @State private var name = ""
    @State private var handle = ""
    @State private var category = ""
    @State private var bio = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var website = ""
    @State private var addressLine = ""
    @State private var city = ""
    @State private var country = ""
    @State private var openingHours = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    private var isEditing: Bool { business != nil }
    private var canSave: Bool {
        !app.businessBusy && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    avatarPicker
                    field("Business name", text: $name, placeholder: "Chez Amine")
                    field("Username", text: $handle, placeholder: isEditing ? handle : "left blank = from the name",
                          autocapitalize: false)
                    field("Category", text: $category, placeholder: "Restaurant, Bakery, Studio…")
                    multilineField("About", text: $bio)

                    sectionLabel("Contact")
                    field("Phone", text: $phone, placeholder: "+212…", keyboard: .phonePad)
                    field("Email", text: $email, placeholder: "hello@…", autocapitalize: false,
                          keyboard: .emailAddress)
                    field("Website", text: $website, placeholder: "https://…", autocapitalize: false,
                          keyboard: .URL)

                    sectionLabel("Where")
                    field("Address", text: $addressLine, placeholder: "12 Rue…")
                    field("City", text: $city, placeholder: "Casablanca")
                    field("Country", text: $country, placeholder: "Morocco")

                    sectionLabel("Hours")
                    multilineField("Opening hours", text: $openingHours)

                    saveButton
                }
                .padding(20)
            }
            .background(GGColor.bg.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit business" : "New business")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GGColor.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            HStack(spacing: 12) {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else {
                    UserAvatar(size: 60,
                               gradient: SocialStore.gradient(for: business?.handle ?? name),
                               imageURL: business?.avatarURL)
                }
                Text(photoData == nil ? "Add a logo" : "Change logo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(GGColor.textSecondary)
            .padding(.top, 4)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String,
                       autocapitalize: Bool = true,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GGColor.textTertiary)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundStyle(GGColor.textPrimary)
                .textInputAutocapitalization(autocapitalize ? .sentences : .never)
                .autocorrectionDisabled(!autocapitalize)
                .keyboardType(keyboard)
                .padding(12)
                .glass(cornerRadius: 14, fillOpacity: 0.05, borderOpacity: 0.1)
        }
    }

    private func multilineField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GGColor.textTertiary)
            TextEditor(text: text)
                .font(.system(size: 15))
                .foregroundStyle(GGColor.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: 90)
                .padding(8)
                .glass(cornerRadius: 14, fillOpacity: 0.05, borderOpacity: 0.1)
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            ZStack {
                if app.businessBusy { ProgressView().tint(GGColor.onAccent) }
                else { Text(isEditing ? "Save changes" : "Create business profile") }
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

    private func load() {
        guard let business else { return }
        name = business.name
        handle = business.handle
        category = business.category
        bio = business.bio
        phone = business.phone
        email = business.email
        website = business.website
        addressLine = business.addressLine
        city = business.city
        country = business.country
        openingHours = business.openingHours
    }

    private func save() async {
        let ok: Bool
        if let business {
            ok = await app.updateBusinessProfile(
                business.id, name: name, handle: handle, category: category, bio: bio,
                phone: phone, email: email, website: website, addressLine: addressLine,
                city: city, country: country, openingHours: openingHours, avatarData: photoData)
        } else {
            ok = await app.createBusinessProfile(
                name: name, handle: handle, category: category, bio: bio,
                phone: phone, email: email, website: website, addressLine: addressLine,
                city: city, country: country, openingHours: openingHours, avatarData: photoData)
        }
        if ok { dismiss() }
    }
}
