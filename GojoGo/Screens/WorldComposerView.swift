import SwiftUI
import PhotosUI

/// Publish a GojoMessages post or story.
///
/// The audience picker is the whole point of this screen. There is no "public"
/// option and there never will be — a GojoMessages post reaches the author's
/// contacts or the circles they picked, and nobody else. Everything published
/// here is invisible to the public `social` feed, which is a separate product.
struct WorldComposerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var kind = "post"
    @State private var text = ""
    @State private var picked: [PhotosPickerItem] = []
    @State private var images: [Data] = []
    @State private var audience: WorldPostAudience = .contacts
    @State private var circleIDs: Set<UUID> = []
    @State private var busy = false
    @State private var error: String?
    /// Circle creation is a *nested* sheet owned by this screen rather than a
    /// swap of the shared `worldSheet` item — reassigning the binding that is
    /// presenting you is how a sheet ends up dismissing itself and presenting
    /// nothing.
    @State private var showCircleEditor = false

    private var canPublish: Bool {
        let hasBody = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
        let hasAudience = audience == .contacts || !circleIDs.isEmpty
        return hasBody && hasAudience && !busy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    kindPicker
                    composer
                    photoRow
                    audienceSection
                    if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .background(IMColor.sheetBG.ignoresSafeArea())
            .navigationTitle(kind == "story" ? "New story" : "New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Sharing…" : "Share") { publish() }
                        .disabled(!canPublish)
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: picked) { _, items in
                Task { await load(items) }
            }
            .onAppear { kind = app.worldComposerKind }
            .sheet(isPresented: $showCircleEditor) {
                WorldCircleEditor(circle: nil)
                    .environmentObject(app)
            }
        }
    }

    private var kindPicker: some View {
        Picker("Kind", selection: $kind) {
            Text("Post").tag("post")
            Text("Story").tag("story")
        }
        .pickerStyle(.segmented)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(kind == "story" ? "Say something…" : "What's happening?",
                      text: $text, axis: .vertical)
                .lineLimit(4...10)
                .font(.system(size: 16))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(IMColor.inputFill))
            if kind == "story" {
                Text("Disappears after 24 hours.")
                    .font(.system(size: 12))
                    .foregroundStyle(IMColor.secondary)
            }
        }
    }

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotosPicker(selection: $picked, maxSelectionCount: 6, matching: .images) {
                Label(images.isEmpty ? "Add photos" : "\(images.count) selected",
                      systemImage: "photo.on.rectangle")
                    .font(.system(size: 15, weight: .medium))
            }
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                            MediaImage(data: data, cornerRadius: 12)
                                .frame(width: 78, height: 78)
                                .clipped()
                        }
                    }
                }
            }
        }
    }

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who can see this")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IMColor.secondary)
                .textCase(.uppercase)

            ForEach(WorldPostAudience.allCases) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { audience = option }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: audience == option ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(audience == option ? IMColor.blue : IMColor.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(IMColor.label)
                            Text(option.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(IMColor.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(IMColor.inputFill))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if audience == .circles {
                circlePicker
            }

            Text("Never shown on the public GojoGo feed.")
                .font(.system(size: 12))
                .foregroundStyle(IMColor.secondary)
        }
    }

    @ViewBuilder
    private var circlePicker: some View {
        if app.worldCircles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("You haven't made a circle yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(IMColor.secondary)
                Button("Create one") { showCircleEditor = true }
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.leading, 4)
        } else {
            VStack(spacing: 0) {
                ForEach(app.worldCircles) { circle in
                    Button {
                        if circleIDs.contains(circle.id) {
                            circleIDs.remove(circle.id)
                        } else {
                            circleIDs.insert(circle.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: circle.colorHex))
                                .frame(width: 12, height: 12)
                            Text(circle.name)
                                .font(.system(size: 15))
                                .foregroundStyle(IMColor.label)
                            Spacer()
                            Text("\(circle.memberIDs.count)")
                                .font(.system(size: 13))
                                .foregroundStyle(IMColor.secondary)
                            Image(systemName: circleIDs.contains(circle.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(circleIDs.contains(circle.id)
                                                 ? IMColor.blue : IMColor.secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(IMColor.inputFill))
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var out: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                out.append(data)
            }
        }
        images = out
    }

    private func publish() {
        busy = true
        error = nil
        Task {
            let ok = await app.publishWorldContent(
                kind: kind, text: text, imageData: images,
                audience: audience, circleIDs: Array(circleIDs))
            busy = false
            if ok {
                dismiss()
            } else {
                error = "Couldn't share that. Try again."
            }
        }
    }
}
