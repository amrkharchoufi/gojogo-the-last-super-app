import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Adding and editing a product (Phase 5 · M1 + M2)
//
// A product has no price. Every price, every stock count and every SKU lives on
// a variant, and a product must have at least one — so the form always opens
// with one row already there rather than letting somebody save a product that
// cannot be bought.
//
// Removing a variant row does not delete anything: the server retires it, and
// an order line that pointed at it keeps pointing at it forever. The form says
// so, because "remove" that does not remove is the kind of thing a seller
// discovers at the wrong moment.
//
// Kind is fixed at creation. A product that has sold as a download cannot
// become a parcel without lying about what past orders delivered, so the picker
// disappears once the product exists.

struct ShopProductEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let product: ShopProductDTO?

    @State private var name = ""
    @State private var description = ""
    @State private var category = ""
    @State private var brand = ""
    @State private var specs = ""
    @State private var imageURLs: [String] = []
    @State private var rows: [VariantRow] = [VariantRow()]
    @State private var isDigital = false
    @State private var licenseKeys = false

    @State private var pick: PhotosPickerItem?
    @State private var uploading = false
    @State private var showFileImporter = false
    @State private var attaching = false
    @State private var assetName: String?

    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false

    /// One variant row in the form. Prices are held as typed text so a
    /// half-typed "12." is not rounded under the seller's fingers.
    struct VariantRow: Identifiable, Equatable {
        var id = UUID()
        var serverID: UUID?
        var label = ""
        var sku = ""
        var price = ""
        var stock = ""
        var active = true
    }

    private var isNew: Bool { product == nil }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(isNew ? "New product" : "Edit product")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                photos
                if isNew { kindPicker }
                field("Name", text: $name)
                field("Category", text: $category)
                field("Brand", text: $brand)
                multiline("Description", text: $description)
                multiline("Specs", text: $specs)
                variants
                if isDigital { digitalAsset }

                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glass(cornerRadius: 12, tint: GGColor.ink(0.08))
                }

                Button { save() } label: {
                    Text(saving ? "Saving…" : (isNew ? "Add to catalog" : "Save changes"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
                .disabled(saving)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .onAppear(perform: load)
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { result in
            handleFile(result)
        }
    }

    // MARK: Photos

    private var photos: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach(imageURLs, id: \.self) { url in
                    MediaImage(url: url, cornerRadius: 12)
                        .frame(width: 64, height: 64)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.ggSnappy) { imageURLs.removeAll { $0 == url } }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(GGColor.textPrimary)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                        }
                }
                PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(GGColor.ink(0.07))
                        .frame(width: 64, height: 64)
                        .overlay {
                            if uploading { ProgressView().tint(GGColor.textPrimary) }
                            else {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(GGColor.textTertiary)
                            }
                        }
                }
                Spacer(minLength: 0)
            }
            .onChange(of: pick) { _, item in
                guard let item else { return }
                Task {
                    defer { pick = nil }
                    uploading = true
                    defer { uploading = false }
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    if let url = try? await APIClient.shared.uploadMedia(
                        data, contentType: APIClient.imageContentType(for: data)) {
                        withAnimation(.ggSnappy) { imageURLs.append(url) }
                    }
                }
            }
        }
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach([false, true], id: \.self) { digital in
                let active = isDigital == digital
                Button {
                    withAnimation(.ggSnappy) { isDigital = digital }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: digital ? "arrow.down.doc" : "shippingbox")
                            .font(.system(size: 11, weight: .semibold))
                        Text(digital ? "Download" : "Ships")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Variants

    private var variants: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VARIANTS")
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)

            ForEach($rows) { $row in
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Label (e.g. Large / Blue)", text: $row.label)
                            .font(.system(size: 13))
                            .padding(10)
                            .glass(cornerRadius: 10, tint: GGColor.ink(0.06))
                        if rows.count > 1 {
                            Button {
                                withAnimation(.ggSnappy) { rows.removeAll { $0.id == row.id } }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 15))
                                    .foregroundStyle(GGColor.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Price", text: $row.price)
                            .keyboardType(.decimalPad)
                            .font(.ggMono(13))
                            .padding(10)
                            .glass(cornerRadius: 10, tint: GGColor.ink(0.06))
                        TextField("Stock", text: $row.stock)
                            .keyboardType(.numberPad)
                            .font(.ggMono(13))
                            .padding(10)
                            .glass(cornerRadius: 10, tint: GGColor.ink(0.06))
                        TextField("SKU", text: $row.sku)
                            .font(.ggMono(13))
                            .autocorrectionDisabled()
                            .padding(10)
                            .glass(cornerRadius: 10, tint: GGColor.ink(0.06))
                    }
                }
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
            }

            Button {
                withAnimation(.ggSnappy) { rows.append(VariantRow()) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add a variant")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(GGColor.textSecondary)
            }
            .buttonStyle(.plain)

            if !isNew {
                Text("A variant you remove is retired, not deleted — orders that bought it keep their line.")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }
        }
    }

    // MARK: The digital half

    private var digitalAsset: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT THE BUYER GETS")
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)

            HStack(spacing: 8) {
                ForEach([false, true], id: \.self) { keys in
                    let active = licenseKeys == keys
                    Button {
                        withAnimation(.ggSnappy) { licenseKeys = keys }
                    } label: {
                        Text(keys ? "Licence key" : "A file")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            if licenseKeys {
                Text("A key is generated for each buyer at the moment they pay. Nothing to upload.")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            } else if isNew {
                Text("Save the product first, then attach the file — the upload needs somewhere to attach to.")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            } else {
                Button {
                    showFileImporter = true
                } label: {
                    HStack(spacing: 8) {
                        if attaching { ProgressView().tint(GGColor.textPrimary) }
                        Image(systemName: "paperclip")
                            .font(.system(size: 12, weight: .semibold))
                        Text(assetName ?? "Attach the file")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(12)
                    .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(attaching)
                Text("Buyers get a fresh signed link every time they ask, so the file itself is never public.")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }
        }
    }

    // MARK: Fields

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField("", text: text)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .padding(11)
                .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
        }
    }

    private func multiline(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.ggMono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
            TextField("", text: text, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .lineLimit(2...6)
                .padding(11)
                .glass(cornerRadius: 12, tint: GGColor.ink(0.06))
        }
    }

    // MARK: Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let product else { return }
        name = product.name
        description = product.description ?? ""
        category = product.category ?? ""
        brand = product.brand ?? ""
        specs = product.specs ?? ""
        imageURLs = product.imageUrls
        isDigital = product.isDigital
        rows = product.variants.map { variant in
            VariantRow(serverID: variant.id,
                       label: variant.label,
                       sku: variant.sku ?? "",
                       price: String(format: "%.2f", Double(variant.priceCents) / 100),
                       stock: "\(variant.stock)",
                       active: variant.active)
        }
        if rows.isEmpty { rows = [VariantRow()] }
    }

    private func save() {
        let live = rows.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            withAnimation(.ggSnappy) { error = "Give the product a name." }
            return
        }
        guard !live.isEmpty else {
            withAnimation(.ggSnappy) { error = "A product needs at least one variant to be bought." }
            return
        }
        saving = true
        error = nil
        Task {
            let failure = await app.saveShopProduct(product?.id, ShopProductBody(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description,
                category: category.trimmingCharacters(in: .whitespaces),
                brand: brand.trimmingCharacters(in: .whitespaces),
                specs: specs,
                imageUrls: imageURLs,
                variants: live.map { row in
                    ShopVariantBody(id: row.serverID,
                                    sku: row.sku.isEmpty ? nil : row.sku,
                                    label: row.label.trimmingCharacters(in: .whitespaces),
                                    priceCents: EconomyStore.parseCents(row.price) ?? 0,
                                    stock: Int(row.stock) ?? 0,
                                    active: row.active)
                },
                kind: isDigital ? "DIGITAL" : "PHYSICAL"))
            saving = false
            // A digital product with licence keys needs its generator attached
            // once; doing it here rather than behind a second tap is what keeps
            // "save" from producing something nobody can be given.
            if failure == nil, isDigital, licenseKeys, let id = product?.id {
                _ = await app.attachDigitalAsset(to: id, data: nil, fileName: "",
                                                 contentType: "", licenseKeys: true)
            }
            if failure == nil { dismiss() } else { withAnimation(.ggSnappy) { error = failure } }
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first,
              let productId = product?.id else { return }
        attaching = true
        Task {
            defer { attaching = false }
            // Security-scoped: a file the picker handed us is not ours to read
            // without asking, and forgetting to stop leaks the scope.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                withAnimation(.ggSnappy) { error = "Couldn't read that file." }
                return
            }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            let failure = await app.attachDigitalAsset(to: productId, data: data,
                                                       fileName: url.lastPathComponent,
                                                       contentType: type, licenseKeys: false)
            withAnimation(.ggSnappy) {
                error = failure
                if failure == nil { assetName = url.lastPathComponent }
            }
        }
    }
}
