import SwiftUI
import PhotosUI
import UIKit

// MARK: - Your restaurant (Phase 2b · Milestone 6)
//
// What an approved partner sees: the storefront buyers browse, the open/closed
// switch, and the menu editor. This is the half of GojoDelivery that has never
// existed — until now the catalog could only be written by a Flyway migration.
//
// Nothing here is optimistic except the open switch. Every menu mutation answers
// with the whole restaurant and the screen adopts that, because a menu editor
// that shows a dish which didn't save is how a customer orders something that
// doesn't exist. The open switch is the exception: the toggle *is* the feedback,
// so it moves at once and puts itself back (loudly) if the server refuses.
//
// Not here on purpose: incoming orders. Fulfilment runs on a server-side
// timeline until the Phase 3 `dispatch` module exists, so a kitchen "accept"
// button would be immediately overruled by the job that walks the order along.

struct MerchantDashboardBody: View {
    @EnvironmentObject var app: AppState

    /// Non-nil while the storefront form is open.
    @State private var editingStorefront = false
    /// Non-nil while a dish form is open: which section, and which dish (nil = new).
    @State private var editingDish: DishTarget? = nil
    @State private var renamingSection: MerchantMenuSection? = nil
    @State private var newSectionName = ""
    @State private var addingSection = false
    @State private var pendingSectionDelete: MerchantMenuSection? = nil

    struct DishTarget: Identifiable, Equatable {
        let sectionID: UUID
        var item: MerchantMenuItem?
        var id: String { "\(sectionID)-\(item?.id.uuidString ?? "new")" }
    }

    private var storefront: MerchantStorefront? { app.merchantStorefront }

    var body: some View {
        Group {
            if let storefront {
                if editingStorefront {
                    MerchantStorefrontForm(storefront: storefront,
                                           onCancel: { withAnimation(.ggSnappy) { editingStorefront = false } },
                                           onSave: { save($0) })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let target = editingDish {
                    MerchantDishForm(item: target.item,
                                     onCancel: { withAnimation(.ggSnappy) { editingDish = nil } },
                                     onSave: { body in
                                         app.saveMerchantItem(sectionID: target.sectionID,
                                                              itemID: target.item?.id, body)
                                         withAnimation(.ggSnappy) { editingDish = nil }
                                     })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    dashboard(storefront)
                }
            } else {
                loading
            }
        }
        .animation(.ggSnappy, value: editingStorefront)
        .animation(.ggSnappy, value: editingDish)
        .task { await app.refreshMerchantStorefront() }
        .onChange(of: app.merchantStorefront?.isSuspended) { was, now in
            // The suspension reason lives on the application; re-read it when
            // the restaurant tells us the flag flipped behind our back.
            if was == false && now == true { Task { await app.refreshMerchantPartner() } }
        }
        .alert("Delete this section?", isPresented: Binding(
            get: { pendingSectionDelete != nil },
            set: { if !$0 { pendingSectionDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingSectionDelete = nil }
            Button("Delete", role: .destructive) {
                if let section = pendingSectionDelete { app.deleteMerchantSection(section.id) }
                pendingSectionDelete = nil
            }
        } message: {
            Text(pendingSectionDelete.map {
                "“\($0.name)” and its \($0.items.count) dish\($0.items.count == 1 ? "" : "es") go with it. "
                + "Orders people already placed keep their receipts."
            } ?? "")
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView().tint(GGColor.textSecondary)
            Text("Opening your restaurant…")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Dashboard

    private func dashboard(_ store: MerchantStorefront) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                storeCard(store)
                if store.isSuspended { suspendedNote }
                statsStrip(store)
                menuHeader
                if store.menu.isEmpty {
                    emptyMenu
                } else {
                    ForEach(store.menu) { section in
                        sectionCard(section)
                    }
                }
                addSectionRow
                Color.clear.frame(height: 28)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        // Refreshes the *account* too, not just the restaurant: a suspension
        // lands on the application, and its note is what this screen shows.
        .refreshable { await app.refreshMerchantPartner() }
    }

    private func storeCard(_ store: MerchantStorefront) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if let url = store.imageURL {
                    MediaImage(url: url, cornerRadius: 14)
                        .frame(width: 54, height: 54)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(GGColor.ink(0.10))
                        .frame(width: 54, height: 54)
                        .overlay(Image(systemName: "storefront")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(GGColor.textTertiary))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                        .lineLimit(1)
                    Text(store.cuisine)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(1)
                    Text("\(store.etaMinutes) min · \(store.feeLabel)")
                        .font(.ggMono(11, .medium))
                        .foregroundStyle(GGColor.textTertiary)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.ggSnappy) { editingStorefront = true }
                } label: {
                    Text("Edit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .glassCapsule(tint: GGColor.ink(0.08), interactive: false, dense: true)
                }
                .buttonStyle(PressableStyle())
            }

            Divider().overlay(GGColor.ink(0.10))

            HStack(spacing: 10) {
                Circle()
                    .fill(store.isOpen && !store.isSuspended ? GGColor.white : GGColor.ink(0.25))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.isOpen ? "Taking orders" : "Closed")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(store.isOpen
                         ? "You're in the GojoDelivery catalog right now"
                         : "Nobody can find you until you open")
                        .font(.system(size: 11))
                        .foregroundStyle(GGColor.textTertiary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { store.isOpen },
                    set: { app.setMerchantOpen($0) }
                ))
                .labelsHidden()
                .tint(GGColor.white)
                .disabled(store.isSuspended)
            }
        }
        .padding(16)
        .glass(cornerRadius: 22, tint: GGColor.ink(0.06))
    }

    private var suspendedNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Suspended")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(app.merchantAccount?.reviewNote
                     ?? "Your restaurant is hidden while we look into something.")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.10))
    }

    private func statsStrip(_ store: MerchantStorefront) -> some View {
        HStack(spacing: 10) {
            statTile("\(store.dishCount)", "Dishes")
            statTile("\(store.availableCount)", "Available")
            statTile(store.reviewCount == 0 ? "—" : String(format: "%.1f", store.rating), "Rating")
            statTile("\(store.reviewCount)", "Reviews")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.ggMono(17, .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text(label.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.6)
                .foregroundStyle(GGColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glass(cornerRadius: 16, tint: GGColor.ink(0.05))
    }

    // MARK: Menu

    private var menuHeader: some View {
        HStack {
            Text("MENU")
                .font(.ggMono(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            Spacer()
            if app.merchantBusy {
                ProgressView().controlSize(.small).tint(GGColor.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var emptyMenu: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(GGColor.textTertiary)
            Text("No dishes yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Add a section — Starters, Tagines, Drinks — then put dishes in it. "
                 + "You can open once one dish is available.")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 22)
        .glass(cornerRadius: 20, tint: GGColor.ink(0.04))
    }

    private func sectionCard(_ section: MerchantMenuSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if renamingSection?.id == section.id {
                    TextField("Section", text: $newSectionName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .tint(GGColor.white)
                        .submitLabel(.done)
                        .onSubmit { commitRename(section) }
                    Button("Save") { commitRename(section) }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                } else {
                    Text(section.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Spacer(minLength: 0)
                    Menu {
                        Button("Add a dish") {
                            withAnimation(.ggSnappy) {
                                editingDish = DishTarget(sectionID: section.id, item: nil)
                            }
                        }
                        Button("Rename section") {
                            newSectionName = section.name
                            withAnimation(.ggSnappy) { renamingSection = section }
                        }
                        Button("Delete section", role: .destructive) {
                            pendingSectionDelete = section
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GGColor.textTertiary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                }
            }

            if section.items.isEmpty {
                Text("Nothing in this section yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textTertiary)
            } else {
                ForEach(section.items) { item in
                    dishRow(item, in: section)
                }
            }

            Button {
                withAnimation(.ggSnappy) {
                    editingDish = DishTarget(sectionID: section.id, item: nil)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add a dish")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(GGColor.textSecondary)
                .padding(.top, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glass(cornerRadius: 20, tint: GGColor.ink(0.05))
    }

    private func dishRow(_ item: MerchantMenuItem, in section: MerchantMenuSection) -> some View {
        HStack(spacing: 12) {
            if let url = item.imageURL {
                MediaImage(url: url, cornerRadius: 10)
                    .frame(width: 42, height: 42)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.isAvailable ? GGColor.textPrimary : GGColor.textTertiary)
                        .lineLimit(1)
                    if item.isPopular {
                        Text("POPULAR")
                            .font(.ggMono(8, .semibold))
                            .tracking(0.5)
                            .foregroundStyle(GGColor.onAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(GGColor.white))
                    }
                }
                Text(item.isAvailable ? item.priceLabel : "\(item.priceLabel) · Sold out")
                    .font(.ggMono(11, .medium))
                    .foregroundStyle(GGColor.textTertiary)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Edit") {
                    withAnimation(.ggSnappy) {
                        editingDish = DishTarget(sectionID: section.id, item: item)
                    }
                }
                Button(item.isAvailable ? "Mark sold out" : "Put back on the menu") {
                    app.setMerchantItemAvailable(item, !item.isAvailable)
                }
                Button("Delete", role: .destructive) { app.deleteMerchantItem(item.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textTertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 6)
        .opacity(item.isAvailable ? 1 : 0.6)
    }

    private var addSectionRow: some View {
        Group {
            if addingSection {
                HStack(spacing: 8) {
                    TextField("Starters, Tagines, Drinks…", text: $newSectionName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GGColor.textPrimary)
                        .tint(GGColor.white)
                        .submitLabel(.done)
                        .onSubmit { commitNewSection() }
                    Button("Add") { commitNewSection() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Button("Cancel") {
                        withAnimation(.ggSnappy) { addingSection = false; newSectionName = "" }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glass(cornerRadius: 16, tint: GGColor.ink(0.05))
            } else {
                Button {
                    newSectionName = ""
                    withAnimation(.ggSnappy) { addingSection = true }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add a section")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .glass(cornerRadius: 16, tint: GGColor.ink(0.05))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Actions

    private func commitNewSection() {
        let name = newSectionName.trimmed
        guard !name.isEmpty else { return }
        app.addMerchantSection(named: name)
        withAnimation(.ggSnappy) { addingSection = false; newSectionName = "" }
    }

    private func commitRename(_ section: MerchantMenuSection) {
        let name = newSectionName.trimmed
        if !name.isEmpty, name != section.name {
            app.renameMerchantSection(section.id, to: name)
        }
        withAnimation(.ggSnappy) { renamingSection = nil; newSectionName = "" }
    }

    private func save(_ body: UpdateMerchantBody) {
        Task {
            if await app.saveMerchantStorefront(body) {
                withAnimation(.ggSnappy) { editingStorefront = false }
            }
        }
    }
}

// MARK: - Storefront form

private struct MerchantStorefrontForm: View {
    @EnvironmentObject var app: AppState
    let storefront: MerchantStorefront
    var onCancel: () -> Void
    var onSave: (UpdateMerchantBody) -> Void

    @State private var name = ""
    @State private var cuisine = ""
    @State private var promo = ""
    @State private var eta = "25"
    @State private var fee = "0"
    @State private var categories = ""
    @State private var tags = ""
    @State private var imageURL: String?
    @State private var pick: PhotosPickerItem? = nil
    @State private var uploading = false
    @State private var loaded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your storefront")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Text("This is the card buyers see in GojoDelivery.")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)

                coverPicker

                field("Name", text: $name, placeholder: "Dar Zellij")
                field("Cuisine", text: $cuisine, placeholder: "Moroccan · Tagine")
                field("Promo badge", text: $promo, placeholder: "20% off — optional")

                HStack(spacing: 10) {
                    field("Prep + delivery (min)", text: $eta, placeholder: "25", keyboard: .numberPad)
                    field("Delivery fee (cents)", text: $fee, placeholder: "0", keyboard: .numberPad)
                }

                field("Browse categories", text: $categories, placeholder: "Moroccan, Healthy")
                Text("Comma-separated. These are the filter chips at the top of GojoDelivery.")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)

                field("Tags", text: $tags, placeholder: "Halal, Family, Late night")
                Text("Shown on your card. Order isn't preserved.")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)

                AccentButton(title: "Save storefront") { commit() }
                    .disabled(app.merchantBusy || uploading || name.trimmed.isEmpty
                              || cuisine.trimmed.isEmpty)
                    .opacity(app.merchantBusy || name.trimmed.isEmpty ? 0.6 : 1)
                    .padding(.top, 4)

                Button("Cancel", action: onCancel)
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textTertiary)
                    .frame(maxWidth: .infinity)

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: load)
    }

    private var coverPicker: some View {
        PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
            ZStack {
                if let imageURL {
                    MediaImage(url: imageURL, cornerRadius: 18)
                        .frame(height: 130)
                        .frame(maxWidth: .infinity)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(GGColor.ink(0.06))
                        .frame(height: 130)
                }
                if uploading {
                    ProgressView().tint(GGColor.textPrimary)
                } else if imageURL == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 20, weight: .light))
                        Text("Add a cover photo")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(GGColor.textTertiary)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                defer { pick = nil }
                uploading = true
                defer { uploading = false }
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                do {
                    imageURL = try await APIClient.shared.uploadMedia(
                        data, contentType: APIClient.imageContentType(for: data))
                } catch {
                    app.showMerchantNotice("Couldn't upload that photo.")
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        name = storefront.name
        cuisine = storefront.cuisine
        promo = storefront.promo ?? ""
        eta = String(storefront.etaMinutes)
        fee = String(storefront.deliveryFeeCents)
        categories = storefront.categories.joined(separator: ", ")
        tags = storefront.tags.joined(separator: ", ")
        imageURL = storefront.imageURL
        loaded = true
    }

    private func commit() {
        onSave(UpdateMerchantBody(
            name: name.trimmed,
            cuisine: cuisine.trimmed,
            imageUrl: imageURL,
            promo: promo.trimmed.isEmpty ? nil : promo.trimmed,
            etaMinutes: Int(eta.trimmed) ?? storefront.etaMinutes,
            deliveryFeeCents: Int(fee.trimmed) ?? storefront.deliveryFeeCents,
            latitude: storefront.latitude,
            longitude: storefront.longitude,
            categories: splitList(categories),
            tags: splitList(tags)))
    }

    private func splitList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GGColor.textTertiary)
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glass(cornerRadius: 14, tint: GGColor.ink(0.05))
        }
    }
}

// MARK: - Dish form

private struct MerchantDishForm: View {
    @EnvironmentObject var app: AppState
    let item: MerchantMenuItem?
    var onCancel: () -> Void
    var onSave: (MenuItemBody) -> Void

    @State private var name = ""
    @State private var detail = ""
    /// Typed in currency, sent in cents — the server prices every order from
    /// this number, so the conversion happens once, here.
    @State private var price = ""
    @State private var popular = false
    @State private var available = true
    @State private var imageURL: String?
    @State private var pick: PhotosPickerItem? = nil
    @State private var uploading = false
    @State private var loaded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(item == nil ? "New dish" : "Edit dish")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)

                photoPicker

                field("Name", text: $name, placeholder: "Lamb & prune tagine")
                field("Description", text: $detail, placeholder: "Slow-cooked, almonds, sesame")
                field("Price", text: $price, placeholder: "14.50", keyboard: .decimalPad)

                toggleRow("Popular", "Badges it on your menu", isOn: $popular)
                toggleRow("Available", "Sold-out dishes stay on your menu but leave the buyer's",
                          isOn: $available)

                AccentButton(title: item == nil ? "Add to menu" : "Save dish") { commit() }
                    .disabled(name.trimmed.isEmpty || priceCents == nil || uploading)
                    .opacity(name.trimmed.isEmpty || priceCents == nil ? 0.6 : 1)
                    .padding(.top, 4)

                Button("Cancel", action: onCancel)
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textTertiary)
                    .frame(maxWidth: .infinity)

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: load)
    }

    /// Accepts "14.50", "14,50" and "14" alike — a price typed with the comma
    /// this app's users use shouldn't silently become nothing.
    private var priceCents: Int? {
        let text = price.trimmed.replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, let value = Double(text), value >= 0 else { return nil }
        return Int((value * 100).rounded())
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
            ZStack {
                if let imageURL {
                    MediaImage(url: imageURL, cornerRadius: 16)
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(GGColor.ink(0.06))
                        .frame(height: 110)
                }
                if uploading {
                    ProgressView().tint(GGColor.textPrimary)
                } else if imageURL == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .light))
                        Text("Photo — optional")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(GGColor.textTertiary)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onChange(of: pick) { _, picked in
            guard let picked else { return }
            Task {
                defer { pick = nil }
                uploading = true
                defer { uploading = false }
                guard let data = try? await picked.loadTransferable(type: Data.self) else { return }
                do {
                    imageURL = try await APIClient.shared.uploadMedia(
                        data, contentType: APIClient.imageContentType(for: data))
                } catch {
                    app.showMerchantNotice("Couldn't upload that photo.")
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        if let item {
            name = item.name
            detail = item.detail
            price = String(format: "%.2f", Double(item.priceCents) / 100)
            popular = item.isPopular
            available = item.isAvailable
            imageURL = item.imageURL
        }
        loaded = true
    }

    private func commit() {
        guard let cents = priceCents else { return }
        onSave(MenuItemBody(name: name.trimmed, detail: detail.trimmed, priceCents: cents,
                            imageUrl: imageURL, popular: popular, available: available,
                            sectionId: nil))
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn).labelsHidden().tint(GGColor.white)
        }
        .padding(14)
        .glass(cornerRadius: 16, tint: GGColor.ink(0.05))
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GGColor.textTertiary)
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glass(cornerRadius: 14, tint: GGColor.ink(0.05))
        }
    }
}
