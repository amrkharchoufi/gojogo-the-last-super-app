import SwiftUI
import PhotosUI

// MARK: - Your listings (Phase 2b · Milestone 5)
//
// Selling used to be one-way: publish and hope. This is the other half — the
// seller's own shelf, where a listing gets edited, paused, marked sold, or
// deleted, and where the numbers the marketplace produced (saves, views) are
// visible at all. Paused and sold listings live *only* here; browse never shows
// them, so this screen is the reason a sale doesn't look like a deletion.
//
// Design follows the Economy sheets: tinted glass cards, mono labels for
// numbers, one ink capsule for the primary action per surface.

struct SellerListingsView: View {
    @EnvironmentObject var app: AppState

    @State private var filter: StatusFilter = .all
    @State private var pendingDelete: SellerListing? = nil

    /// "All" plus the three real statuses — the shelf is fetched whole and
    /// filtered here, so switching segments is instant.
    private enum StatusFilter: Hashable, CaseIterable {
        case all, active, paused, sold

        var status: ListingStatus? {
            switch self {
            case .all: return nil
            case .active: return .active
            case .paused: return .paused
            case .sold: return .sold
            }
        }

        var label: String { status?.label ?? "All" }
    }

    private var visible: [SellerListing] {
        guard let status = filter.status else { return app.sellerListings }
        return app.sellerListings.filter { $0.status == status }
    }

    private func count(_ filter: StatusFilter) -> Int {
        guard let status = filter.status else { return app.sellerListings.count }
        return app.sellerListings.filter { $0.status == status }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // This sheet covers Economy, so it renders the notice itself —
            // otherwise a refused edit fails silently right where it happened.
            // In the layout rather than over it: the shelf is short, and a
            // banner floating across the stat tiles hides the numbers the
            // seller is checking against.
            if let notice = app.economyNotice {
                EconomyNoticeBanner(message: notice) { app.dismissEconomyNotice() }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            header
            if let listing = app.editingListing {
                ListingEditForm(
                    listing: listing,
                    onCancel: { withAnimation(.ggSnappy) { app.editingListing = nil } },
                    onSave: { app.saveListingEdits(listing.id, $0) })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                shelf
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .animation(.ggSnappy, value: app.editingListing?.id)
        .animation(.ggOverlay, value: app.economyNotice)
        .task { await app.refreshSellerListings() }
        .alert("Delete this listing?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let listing = pendingDelete { app.deleteListing(listing.id) }
                pendingDelete = nil
            }
        } message: {
            Text(pendingDelete.map {
                "“\($0.title)” disappears for good, saves and all. Mark it sold instead if it went."
            } ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 3) {
            Text(app.editingListing == nil ? "Your listings" : "Edit listing")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text(app.editingListing == nil
                 ? "What the marketplace did with them"
                 : "Buyers see these changes right away")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: Shelf

    private var shelf: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                statsStrip
                if !app.sellerListings.isEmpty {
                    segments
                }

                if app.sellerListingsLoading && app.sellerListings.isEmpty {
                    loadingRows
                } else if app.sellerListings.isEmpty {
                    emptyShelf
                } else if visible.isEmpty {
                    emptyFilter
                } else {
                    ForEach(visible) { listing in
                        SellerListingRow(
                            listing: listing,
                            onEdit: { withAnimation(.ggSnappy) { app.editingListing = listing } },
                            onStatus: { app.setListingStatus(listing.id, $0) },
                            onView: { app.openListingFromShelf(listing) },
                            onDelete: { pendingDelete = listing })
                    }
                }

                newListingButton
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .refreshable { await app.refreshSellerListings() }
    }

    /// Server-computed totals, so they cover every listing rather than the page
    /// on screen. Falls back to counting what's loaded before the first fetch.
    private var statsStrip: some View {
        let stats = app.sellerStats
        return HStack(spacing: 10) {
            statTile(value: stats?.active ?? count(.active), label: "LIVE")
            statTile(value: stats?.saves ?? app.sellerListings.reduce(0) { $0 + $1.saveCount },
                     label: "SAVES")
            statTile(value: stats?.views ?? app.sellerListings.reduce(0) { $0 + $1.viewCount },
                     label: "VIEWS")
            statTile(value: stats?.sold ?? count(.sold), label: "SOLD")
        }
    }

    private func statTile(value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.ggMono(19, .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text(label)
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glass(cornerRadius: 16, tint: GGColor.ink(0.05))
    }

    private var segments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StatusFilter.allCases, id: \.self) { option in
                    let active = filter == option
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggSnappy) { filter = option }
                    } label: {
                        HStack(spacing: 6) {
                            Text(option.label)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(count(option))")
                                .font(.ggMono(11, .semibold))
                                .opacity(0.7)
                        }
                        .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                        .padding(.horizontal, 13)
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

    private var newListingButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            app.closeSellerHub()
            app.showSellSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("List something else")
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

    // MARK: Empty / loading

    private var emptyShelf: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(GGColor.textTertiary)
            Text("Nothing listed yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Post something and it shows up here with its saves and views.")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.04))
    }

    private var emptyFilter: some View {
        Text(filter == .sold ? "Nothing sold yet." : "Nothing \(filter.label.lowercased()) right now.")
            .font(.system(size: 13))
            .foregroundStyle(GGColor.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }

    private var loadingRows: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(GGColor.ink(0.06))
                    .frame(height: 96)
                    .shimmering()
            }
        }
    }
}

// MARK: - One listing on the shelf

private struct SellerListingRow: View {
    let listing: SellerListing
    var onEdit: () -> Void
    var onStatus: (ListingStatus) -> Void
    var onView: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MediaImage(url: listing.imageURL, cornerRadius: 12)
                    .frame(width: 64, height: 64)
                    .opacity(listing.status == .active ? 1 : 0.55)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(listing.priceLabel)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(GGColor.textPrimary)
                        statusPill
                        Spacer(minLength: 0)
                    }
                    Text(listing.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(listing.timelineLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(GGColor.textTertiary)
                        .lineLimit(1)
                }

                Menu {
                    Button { onEdit() } label: { Label("Edit listing", systemImage: "pencil") }
                    Button { onView() } label: {
                        Label("View in marketplace", systemImage: "eye")
                    }
                    Divider()
                    ForEach(otherStatuses, id: \.self) { status in
                        Button { onStatus(status) } label: {
                            Label(Self.statusAction(status), systemImage: status.icon)
                        }
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: {
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

            HStack(spacing: 14) {
                metric(icon: "heart.fill", value: listing.saveCount, noun: "save")
                metric(icon: "eye.fill", value: listing.viewCount, noun: "view")
                Spacer(minLength: 0)
                // The one action a seller reaches for on this row, one tap deep.
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onStatus(primaryAction)
                } label: {
                    Text(Self.statusAction(primaryAction))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .glassCapsule(interactive: false)
                }
                .buttonStyle(PressableStyle())

                Button { onEdit() } label: {
                    Text("Edit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(12)
        .glass(cornerRadius: 18, tint: GGColor.ink(listing.status == .active ? 0.07 : 0.04))
    }

    /// Live → mark sold (the common ending). Paused or sold → put it back up.
    private var primaryAction: ListingStatus {
        listing.status == .active ? .sold : .active
    }

    private var otherStatuses: [ListingStatus] {
        ListingStatus.allCases.filter { $0 != listing.status }
    }

    private static func statusAction(_ status: ListingStatus) -> String {
        switch status {
        case .active: return "Relist"
        case .paused: return "Pause"
        case .sold: return "Mark sold"
        }
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Image(systemName: listing.status.icon)
                .font(.system(size: 8, weight: .bold))
            Text(listing.status.label.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(listing.status == .active ? GGColor.textPrimary : GGColor.textTertiary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(GGColor.ink(listing.status == .active ? 0.12 : 0.06)))
    }

    private func metric(icon: String, value: Int, noun: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text("\(value) \(value == 1 ? noun : noun + "s")")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(GGColor.textTertiary)
    }
}

// MARK: - Edit form
//
// A full replacement of the listing: every field posts back, photos included.
// Status deliberately isn't here — pausing and marking sold are row actions, so
// a relist stays one tap instead of a form round-trip.

private struct ListingEditForm: View {
    let listing: SellerListing
    var onCancel: () -> Void
    var onSave: (ListingBody) -> Void

    @State private var title: String
    @State private var price: String
    @State private var category: String
    @State private var condition: String
    @State private var location: String
    @State private var details: String
    @State private var imageURLs: [String]
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var uploading = false
    @State private var uploadError: String? = nil

    private static let conditions = ["New", "Like new", "Good", "Fair", "For parts"]
    private static let maxPhotos = 10

    init(listing: SellerListing, onCancel: @escaping () -> Void,
         onSave: @escaping (ListingBody) -> Void) {
        self.listing = listing
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: listing.title)
        _price = State(initialValue: Self.priceField(listing.priceCents))
        _category = State(initialValue: listing.category)
        _condition = State(initialValue: listing.condition)
        _location = State(initialValue: listing.locationLabel)
        _details = State(initialValue: listing.description)
        _imageURLs = State(initialValue: listing.imageURLs)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !uploading
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    photoStrip
                    if let uploadError {
                        Text(uploadError)
                            .font(.system(size: 11))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                    fieldBox(title: "Title") {
                        TextField("Leica M6", text: $title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...2)
                    }
                    fieldBox(title: "Price · \(listing.currency)") {
                        TextField("Leave empty for “on ask”", text: $price)
                            .textFieldStyle(.plain)
                            .keyboardType(.decimalPad)
                    }
                    chipPicker(title: "Category",
                               options: SampleData.economyCategories.filter { $0 != "All" },
                               selection: $category)
                    chipPicker(title: "Condition", options: Self.conditions, selection: $condition)
                    fieldBox(title: "Pickup area") {
                        TextField("Maarif, Casablanca", text: $location)
                            .textFieldStyle(.plain)
                    }
                    fieldBox(title: "Details") {
                        TextField("Anything a buyer would ask about", text: $details,
                                  axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...7)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            actions
        }
    }

    // MARK: Photos

    private var photoStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PHOTOS")
                .font(.ggMono(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(imageURLs.enumerated()), id: \.element) { index, url in
                        ZStack(alignment: .topTrailing) {
                            MediaImage(url: url, cornerRadius: 14)
                                .frame(width: 92, height: 92)
                            Button {
                                withAnimation(.ggSnappy) {
                                    imageURLs.removeAll { $0 == url }
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                            }
                            .buttonStyle(.plain)
                            .padding(5)
                        }
                        // The first photo is the one browse and the deal banner
                        // show, so say which one that is.
                        .overlay(alignment: .bottomLeading) {
                            if index == 0 {
                                Text("COVER")
                                    .font(.ggMono(8, .semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.black.opacity(0.55)))
                                    .padding(5)
                            }
                        }
                    }
                    if imageURLs.count < Self.maxPhotos {
                        addPhotoTile
                    }
                }
            }
        }
    }

    private var addPhotoTile: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            VStack(spacing: 5) {
                if uploading {
                    ProgressView().controlSize(.small).tint(GGColor.textSecondary)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Add")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(GGColor.textSecondary)
            .frame(width: 92, height: 92)
            .glass(cornerRadius: 14, tint: GGColor.ink(0.05))
        }
        .buttonStyle(.plain)
        .disabled(uploading)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            uploadPhoto(item)
        }
    }

    /// Photos go to S3 first — the listing stores URLs, so a save can't half
    /// commit an image that never uploaded.
    private func uploadPhoto(_ item: PhotosPickerItem) {
        uploading = true
        uploadError = nil
        Task {
            defer {
                uploading = false
                photoItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    uploadError = "Couldn't read that photo."
                    return
                }
                let payload = UIImage(data: data)?.jpegData(compressionQuality: 0.9) ?? data
                let url = try await APIClient.shared.uploadMedia(payload, contentType: "image/jpeg")
                withAnimation(.ggSnappy) { imageURLs.append(url) }
            } catch {
                uploadError = "That photo didn't upload — try again."
            }
        }
    }

    // MARK: Fields

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
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .glass(cornerRadius: 16, tint: GGColor.ink(0.05))
        }
    }

    private func chipPicker(title: String, options: [String],
                            selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.ggMono(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.ggSnappy) { selection.wrappedValue = option }
                        } label: {
                            MonoChip(text: option, active: selection.wrappedValue == option)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { onCancel() } label: {
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
                onSave(edits())
            } label: {
                Text("Save changes")
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

    private func edits() -> ListingBody {
        ListingBody(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            priceCents: EconomyStore.parseCents(price),
            currency: listing.currency,
            category: category,
            condition: condition,
            locationLabel: location.trimmingCharacters(in: .whitespacesAndNewlines),
            description: details,
            imageUrls: imageURLs)
    }

    /// Cents → a plain editable number ("1200", "1200.50"), so what the seller
    /// types parses straight back into cents. Nil price stays empty = "on ask".
    private static func priceField(_ cents: Int64?) -> String {
        guard let cents else { return "" }
        let whole = cents / 100
        let fraction = abs(cents % 100)
        return fraction == 0 ? "\(whole)" : "\(whole).\(String(format: "%02d", fraction))"
    }
}
