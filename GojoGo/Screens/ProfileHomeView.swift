import SwiftUI
import PhotosUI

// MARK: - Profile Home tab (customizable canvas)

/// The user's composable Home page: a vertical stack of blocks they arrange,
/// title, and fill with their own posts, pictures and videos. First profile tab.
struct ProfileHomeTab: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL
    @State private var viewingMedia: ProfileHomeMedia?
    let isOwn: Bool
    let blocks: [ProfileHomeBlock]

    private var editing: Bool { isOwn && app.profileHomeEditing }

    var body: some View {
        VStack(spacing: 14) {
            if isOwn { customizeBar }

            if blocks.isEmpty {
                emptyState
            } else {
                ForEach(blocks) { block in
                    blockRow(block)
                }
            }

            if editing { addBlockButton }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .onAppear { if isOwn { app.seedProfileHomeIfNeeded() } }
        .fullScreenCover(item: $viewingMedia) { media in
            HomeMediaViewer(media: media)
        }
    }

    // MARK: Customize toggle

    private var customizeBar: some View {
        HStack(spacing: 8) {
            if editing {
                Text("Arrange, edit, or add blocks")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textTertiary)
            }
            Spacer(minLength: 0)
            if editing {
                Button {
                    app.shuffleProfileHome()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Capsule().fill(GGColor.ink(0.12)))
                }
                .buttonStyle(PressableStyle())
            }
            Button {
                app.toggleProfileHomeEditing()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: editing ? "checkmark" : "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                    Text(editing ? "Done" : "Customize")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(editing ? GGColor.onAccent : GGColor.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(editing ? GGColor.white : GGColor.ink(0.12)))
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: Block row (content + edit chrome)

    @ViewBuilder
    private func blockRow(_ block: ProfileHomeBlock) -> some View {
        if editing {
            ZStack(alignment: .topTrailing) {
                blockContent(block)
                    .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { app.editingHomeBlockID = block.id }
                editControls(block)
                    .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(GGColor.ink(0.18))
            )
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else {
            blockContent(block)
        }
    }

    private func editControls(_ block: ProfileHomeBlock) -> some View {
        let idx = blocks.firstIndex(where: { $0.id == block.id }) ?? 0
        let last = blocks.count - 1
        return HStack(spacing: 2) {
            ctrl("chevron.up") { app.moveHomeBlock(block.id, by: -1) }
                .disabled(idx == 0).opacity(idx == 0 ? 0.35 : 1)
            ctrl("chevron.down") { app.moveHomeBlock(block.id, by: 1) }
                .disabled(idx == last).opacity(idx == last ? 0.35 : 1)
            ctrl("pencil") { app.editingHomeBlockID = block.id }
            ctrl("trash") { app.deleteHomeBlock(block.id) }
        }
        .padding(.horizontal, 4)
        .frame(height: 34)
        .glassCapsule(tint: Color.black.opacity(0.4), interactive: false, dense: true)
    }

    private func ctrl(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Block content by kind

    @ViewBuilder
    private func blockContent(_ block: ProfileHomeBlock) -> some View {
        switch block.kind {
        case .heading:  headingBlock(block)
        case .banner:   bannerBlock(block)
        case .text:     textBlock(block)
        case .featured: featuredBlock(block)
        case .media:    mediaBlock(block)
        case .gallery:  galleryBlock(block)
        case .link:     linkBlock(block)
        }
    }

    // Banner — wide cover picture or video
    @ViewBuilder
    private func bannerBlock(_ block: ProfileHomeBlock) -> some View {
        if let m = block.media.first {
            Button {
                if !editing, m.isVideo { viewingMedia = m }
            } label: {
                ZStack(alignment: .bottomLeading) {
                    mediaThumb(m, corner: 0)
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    if !block.title.isEmpty {
                        LinearGradient(colors: [Color.black.opacity(0.6), .clear],
                                       startPoint: .bottom, endPoint: .center)
                        Text(block.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(16)
                    }
                    if m.isVideo {
                        mutedChip
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(12)
                    }
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(GGColor.ink(0.08), lineWidth: 0.5))
            }
            .buttonStyle(PressableStyle())
        } else {
            placeholder(icon: "photo.on.rectangle.angled", text: "Banner",
                        sub: "Add a cover photo or video")
        }
    }

    // Free-standing pictures & videos
    @ViewBuilder
    private func mediaBlock(_ block: ProfileHomeBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !block.title.isEmpty {
                Text(block.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            if block.media.isEmpty {
                placeholder(icon: "photo.stack", text: "No media yet",
                            sub: "Add pictures and clips")
            } else {
                let cols = max(1, min(3, block.columns))
                let ar: CGFloat = cols == 1 ? (5.0 / 4.0) : 1
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols),
                          spacing: 6) {
                    ForEach(block.media) { m in
                        Button {
                            if !editing { viewingMedia = m }
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                mediaThumb(m, corner: 12)
                                    .aspectRatio(ar, contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                if m.isVideo { mutedChip.padding(6) }
                            }
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline media: videos autoplay muted & looping in place; images render still.
    @ViewBuilder
    private func mediaThumb(_ m: ProfileHomeMedia, corner: CGFloat) -> some View {
        if m.isVideo, let v = m.videoURL, !v.isEmpty {
            ShortVideoPlayer(urlString: v, isActive: true, isMuted: true,
                             videoGravity: .resizeAspectFill)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        } else if m.isVideo {
            MediaImage(url: m.posterURL, cornerRadius: corner)
        } else {
            MediaImage(url: m.imageURL, data: m.imageData, cornerRadius: corner)
        }
    }

    /// Small "tap for sound" hint shown over an autoplaying, muted clip.
    private var mutedChip: some View {
        Image(systemName: "speaker.slash.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.black.opacity(0.45)))
    }

    // Heading
    @ViewBuilder
    private func headingBlock(_ block: ProfileHomeBlock) -> some View {
        let inner = VStack(alignment: .leading, spacing: 4) {
            Text(block.title.isEmpty ? "Heading" : block.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(block.style == .accent ? GGColor.onAccent : GGColor.textPrimary)
            if !block.text.isEmpty {
                Text(block.text)
                    .font(.ny(14))
                    .foregroundStyle(block.style == .accent
                                     ? GGColor.onAccent.opacity(0.8) : GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        switch block.style {
        case .plain:
            inner.padding(.vertical, 4)
        case .card:
            inner.padding(16).glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
        case .accent:
            inner.padding(18)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(GGColor.white))
        }
    }

    // Text note
    private func textBlock(_ block: ProfileHomeBlock) -> some View {
        Text(block.text.isEmpty ? "Tap to write something…" : block.text)
            .font(.ny(15))
            .foregroundStyle(block.text.isEmpty ? GGColor.textTertiary : GGColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    // Featured post (hero)
    @ViewBuilder
    private func featuredBlock(_ block: ProfileHomeBlock) -> some View {
        if let post = app.homeBlockPosts(block).first {
            Button {
                if !editing { app.openPostViewer(post.id) }
            } label: {
                ZStack(alignment: .bottomLeading) {
                    postThumb(post, corner: 0)
                        .frame(height: 250)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    LinearGradient(colors: [Color.black.opacity(0.72), .clear],
                                   startPoint: .bottom, endPoint: .center)
                    VStack(alignment: .leading, spacing: 4) {
                        if !block.title.isEmpty {
                            Text(block.title.uppercased())
                                .font(.ggMono(10, .semibold))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        if let cap = post.text, !cap.isEmpty {
                            Text(cap)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(16)
                }
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(GGColor.ink(0.08), lineWidth: 0.5))
            }
            .buttonStyle(PressableStyle())
        } else {
            placeholder(icon: "star.square", text: block.title.isEmpty ? "Featured post" : block.title,
                        sub: "Pick a post to spotlight")
        }
    }

    // Gallery
    @ViewBuilder
    private func galleryBlock(_ block: ProfileHomeBlock) -> some View {
        let items = app.homeBlockPosts(block)
        VStack(alignment: .leading, spacing: 10) {
            if !block.title.isEmpty {
                Text(block.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            if items.isEmpty {
                placeholder(icon: "square.grid.2x2", text: "Empty gallery",
                            sub: "Add posts to fill this out")
            } else {
                let cols = max(1, min(3, block.columns))
                let ar: CGFloat = cols == 1 ? (5.0 / 4.0) : 1
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols),
                          spacing: 6) {
                    ForEach(items) { post in
                        Button {
                            if !editing { app.openPostViewer(post.id) }
                        } label: {
                            postThumb(post, corner: 12)
                                .aspectRatio(ar, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Link button
    @ViewBuilder
    private func linkBlock(_ block: ProfileHomeBlock) -> some View {
        let accent = block.style == .accent
        Button {
            guard !editing else { return }
            if let url = URL(string: block.url), UIApplication.shared.canOpenURL(url) {
                openURL(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .bold))
                Text(block.title.isEmpty ? "Open link" : block.title)
                    .font(.system(size: 15, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(accent ? GGColor.onAccent : GGColor.textPrimary)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent ? GGColor.white : GGColor.ink(0.12)))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Shared pieces

    @ViewBuilder
    func postThumb(_ post: Post, corner: CGFloat) -> some View {
        if post.imageURL != nil || post.imageData != nil {
            MediaImage(url: post.imageURL, data: post.imageData, cornerRadius: corner)
        } else {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(GGColor.ink(0.08))
                Text(post.text ?? "Post")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(5)
                    .padding(10)
            }
        }
    }

    private func placeholder(icon: String, text: String, sub: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(GGColor.textTertiary)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            Text(sub)
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(GGColor.ink(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(GGColor.ink(0.08), lineWidth: 0.5))
    }

    private var addBlockButton: some View {
        Button {
            app.showHomeBlockPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add block")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(GGColor.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(GGColor.ink(0.2)))
        }
        .buttonStyle(PressableStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 34))
                .foregroundStyle(GGColor.textTertiary)
            Text("Make this space yours")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Add headings, notes, featured posts and galleries — arranged exactly how you want.")
                .font(.ny(14))
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if isOwn {
                Button {
                    if !app.profileHomeEditing { app.toggleProfileHomeEditing() }
                    app.showHomeBlockPicker = true
                } label: {
                    Text("Add your first block")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .padding(.horizontal, 22)
                        .frame(height: 46)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }
}

// MARK: - Full-screen media viewer (banner / media tap)

struct HomeMediaViewer: View {
    let media: ProfileHomeMedia
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if media.isVideo {
                RemoteVideoPlayer(urlString: media.videoURL, posterURL: media.posterURL)
                    .ignoresSafeArea()
            } else {
                MediaImage(url: media.imageURL, data: media.imageData, cornerRadius: 0)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(PressableStyle())
                }
                Spacer()
            }
            .padding(16)
            .padding(.top, 20)
        }
    }
}

// MARK: - Block type picker

struct ProfileHomeBlockPicker: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(GGColor.ink(0.18)).frame(width: 36, height: 5).padding(.top, 8)
            Text("Add a block")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(ProfileHomeBlockKind.allCases) { kind in
                        Button {
                            app.addHomeBlock(kind)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: kind.icon)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(GGColor.textPrimary)
                                    .frame(width: 46, height: 46)
                                    .background(Circle().fill(GGColor.ink(0.08)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.label)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(GGColor.textPrimary)
                                    Text(kind.blurb)
                                        .font(.system(size: 12))
                                        .foregroundStyle(GGColor.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(GGColor.textTertiary)
                            }
                            .padding(12)
                            .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
    }
}

// MARK: - Block editor

struct ProfileHomeBlockEditor: View {
    @EnvironmentObject var app: AppState
    @State private var draft: ProfileHomeBlock
    @State private var photoItem: PhotosPickerItem?

    init(block: ProfileHomeBlock) {
        _draft = State(initialValue: block)
    }

    private var multiSelect: Bool { draft.kind == .gallery }
    private var picksPosts: Bool { draft.kind == .featured || draft.kind == .gallery }
    private var picksMedia: Bool { draft.kind == .banner || draft.kind == .media }
    private var bannerMode: Bool { draft.kind == .banner }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch draft.kind {
                    case .heading:  headingFields
                    case .banner:   bannerFields
                    case .text:     textFields
                    case .featured: featuredFields
                    case .media:    mediaFields
                    case .gallery:  galleryFields
                    case .link:     linkFields
                    }
                    if picksPosts { postPicker }
                    if picksMedia { mediaPicker }
                    deleteButton
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .onChange(of: draft) { _, new in app.updateHomeBlock(new) }
        .onChange(of: photoItem) { _, item in importPhoto(item) }
    }

    private var header: some View {
        HStack {
            Text("Edit \(draft.kind.label.lowercased())")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Spacer()
            Button {
                app.updateHomeBlock(draft)
                app.editingHomeBlockID = nil
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // Field groups
    private var headingFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Title", text: $draft.title, placeholder: "Section title")
            multilineField("Subtitle", text: $draft.text, placeholder: "Optional supporting line")
            stylePicker
        }
    }

    private var textFields: some View {
        multilineField("Your note", text: $draft.text, placeholder: "Write anything…", minHeight: 120)
    }

    private var featuredFields: some View {
        field("Label", text: $draft.title, placeholder: "e.g. Latest drop")
    }

    private var galleryFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Title", text: $draft.title, placeholder: "e.g. Selected work")
            columnsPicker
        }
    }

    private var linkFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Label", text: $draft.title, placeholder: "e.g. My website")
            field("URL", text: $draft.url, placeholder: "https://…", keyboard: .URL, autocaps: .never)
            stylePicker
        }
    }

    private var bannerFields: some View {
        field("Caption", text: $draft.title, placeholder: "Optional text over the banner")
    }

    private var mediaFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Title", text: $draft.title, placeholder: "e.g. Moodboard")
            columnsPicker
        }
    }

    // MARK: media picker (banner / photos & video)

    private var mediaPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                label(bannerMode ? "Cover" : "Media")
                Spacer()
                if !bannerMode {
                    Text("\(draft.media.count) added")
                        .font(.ggMono(11, .medium))
                        .foregroundStyle(GGColor.textTertiary)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Import photo")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Capsule().fill(GGColor.ink(0.1)))
                }
            }

            if !draft.media.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(draft.media) { m in
                            selectedMediaThumb(m)
                        }
                    }
                }
            }

            label("From your library")
            if SampleData.homeMediaLibrary.isEmpty {
                Text("Import a photo above — there’s no sample media library.")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                          spacing: 6) {
                    ForEach(SampleData.homeMediaLibrary) { m in
                        libraryCell(m)
                    }
                }
            }
        }
    }

    private func selectedMediaThumb(_ m: ProfileHomeMedia) -> some View {
        ZStack(alignment: .topTrailing) {
            editorThumb(m)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if m.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                draft.media.removeAll { $0.id == m.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(GGColor.white))
            }
            .padding(3)
        }
    }

    private func libraryCell(_ m: ProfileHomeMedia) -> some View {
        let selected = draft.media.contains { $0.sameAsset(as: m) }
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            toggleMedia(m)
        } label: {
            ZStack {
                editorThumb(m)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? GGColor.white : Color.clear, lineWidth: 2))
                if m.isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(GGColor.white))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private func editorThumb(_ m: ProfileHomeMedia) -> some View {
        if m.isVideo {
            MediaImage(url: m.posterURL, cornerRadius: 10)
        } else {
            MediaImage(url: m.imageURL, data: m.imageData, cornerRadius: 10)
        }
    }

    private func toggleMedia(_ m: ProfileHomeMedia) {
        if bannerMode {
            draft.media = (draft.media.first?.sameAsset(as: m) == true) ? [] : [m]
        } else if let i = draft.media.firstIndex(where: { $0.sameAsset(as: m) }) {
            draft.media.remove(at: i)
        } else {
            draft.media.append(m)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    let m = ProfileHomeMedia(imageData: data)
                    if bannerMode { draft.media = [m] } else { draft.media.append(m) }
                    photoItem = nil
                }
            }
        }
    }

    // Style picker (heading / link)
    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Style")
            HStack(spacing: 8) {
                ForEach(ProfileHomeStyle.allCases) { style in
                    let active = draft.style == style
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.18)) { draft.style = style }
                    } label: {
                        Text(style.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var columnsPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Columns")
            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { n in
                    let active = draft.columns == n
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.18)) { draft.columns = n }
                    } label: {
                        Text("\(n)")
                            .font(.ggMono(15, .semibold))
                            .foregroundStyle(active ? GGColor.onAccent : GGColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Capsule().fill(active ? GGColor.white : GGColor.ink(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Post picker
    private var postPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                label(multiSelect ? "Posts" : "Post")
                Spacer()
                if multiSelect {
                    Text("\(draft.postIDs.count) selected")
                        .font(.ggMono(11, .medium))
                        .foregroundStyle(GGColor.textTertiary)
                }
            }
            if app.myPosts.isEmpty {
                Text("You have no posts yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textTertiary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                          spacing: 6) {
                    ForEach(app.myPosts) { post in
                        pickCell(post)
                    }
                }
            }
        }
    }

    private func pickCell(_ post: Post) -> some View {
        let selected = draft.postIDs.contains(post.id)
        let order = draft.postIDs.firstIndex(of: post.id).map { $0 + 1 }
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            toggle(post.id)
        } label: {
            ZStack(alignment: .topTrailing) {
                thumb(post)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? GGColor.white : Color.clear, lineWidth: 2))
                if selected {
                    Group {
                        if multiSelect, let order {
                            Text("\(order)").font(.ggMono(11, .bold)).foregroundStyle(GGColor.onAccent)
                        } else {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .black))
                                .foregroundStyle(GGColor.onAccent)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(GGColor.white))
                    .padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private func thumb(_ post: Post) -> some View {
        if post.imageURL != nil || post.imageData != nil {
            MediaImage(url: post.imageURL, data: post.imageData, cornerRadius: 10)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GGColor.ink(0.08))
                Text(post.text ?? "Post")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(3)
                    .padding(6)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if multiSelect {
            if let i = draft.postIDs.firstIndex(of: id) { draft.postIDs.remove(at: i) }
            else { draft.postIDs.append(id) }
        } else {
            draft.postIDs = draft.postIDs == [id] ? [] : [id]
        }
    }

    private var deleteButton: some View {
        Button {
            app.deleteHomeBlock(draft.id)
            app.editingHomeBlockID = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                Text("Delete block").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(GGColor.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GGColor.ink(0.06)))
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 4)
    }

    // MARK: field helpers

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.ggMono(9, .semibold))
            .tracking(0.4)
            .foregroundStyle(GGColor.textTertiary)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType = .default,
                       autocaps: TextInputAutocapitalization = .sentences) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GGColor.textPrimary)
                .tint(GGColor.white)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocaps)
                .autocorrectionDisabled(keyboard == .URL)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GGColor.ink(0.06)))
        }
    }

    private func multilineField(_ title: String, text: Binding<String>, placeholder: String,
                                minHeight: CGFloat = 80) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundStyle(GGColor.textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                TextEditor(text: text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
                    .tint(GGColor.white)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: minHeight)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GGColor.ink(0.06)))
        }
    }
}
