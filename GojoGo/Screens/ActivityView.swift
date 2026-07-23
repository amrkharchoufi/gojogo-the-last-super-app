import SwiftUI
import PhotosUI

// MARK: - Activity (notifications)

struct ActivityView: View {
    @EnvironmentObject var app: AppState

    private var unread: [ActivityItem] { app.notifications.filter { !$0.read } }
    private var earlier: [ActivityItem] { app.notifications.filter(\.read) }

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.bg.ignoresSafeArea()
                if app.notifications.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "heart")
                            .font(.system(size: 34))
                            .foregroundStyle(GGColor.textTertiary)
                        Text("Activity on your posts shows up here.")
                            .font(.system(size: 14))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if !unread.isEmpty {
                                sectionLabel("New")
                                ForEach(unread) { row($0) }
                            }
                            if !earlier.isEmpty {
                                sectionLabel(unread.isEmpty ? "Earlier" : "Seen")
                                ForEach(earlier) { row($0) }
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !unread.isEmpty {
                        Button("Mark all read") {
                            withAnimation(.easeOut(duration: 0.25)) { app.markActivityRead() }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { app.closeActivity() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GGColor.textPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(GGColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private func row(_ item: ActivityItem) -> some View {
        Button {
            app.handleActivityTap(item)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    UserAvatar(size: 44,
                               letter: String(item.actor.prefix(1)).uppercased(),
                               imageURL: item.avatarURL)
                    Image(systemName: item.kind.icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(item.kind.tint))
                        .overlay(Circle().strokeBorder(GGColor.bg, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }

                (Text(item.actor).fontWeight(.semibold)
                 + Text(" \(item.text) ")
                 + Text(item.timeAgo).foregroundColor(GGColor.textTertiary))
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let preview = item.previewURL {
                    MediaImage(url: preview, cornerRadius: 8)
                        .frame(width: 44, height: 44)
                        .clipped()
                } else if !item.read {
                    Circle().fill(GGColor.blue).frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(item.read ? Color.clear : GGColor.ink(0.035))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Direct messages

struct DirectMessageView: View {
    @EnvironmentObject var app: AppState
    @FocusState private var focused: Bool

    private var peer: ProfileUser? { app.dmPeer }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                UserAvatar(size: 40,
                           gradient: peer?.avatarGradient ?? [],
                           letter: String((peer?.name ?? "?").prefix(1)).uppercased(),
                           imageURL: peer?.avatarURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer?.name ?? "Chat")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text("@\(peer?.handle ?? "") · active now")
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                }
                Spacer()
                Button { app.closeDirectMessage() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GGColor.textSecondary)
                        .frame(width: 32, height: 32)
                        .glassCapsule(interactive: false)
                }
            }
            .padding(16)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(app.dmChat) { msg in
                            HStack {
                                if msg.fromUser { Spacer(minLength: 40) }
                                Text(msg.text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(msg.fromUser ? GGColor.onAccent : GGColor.textPrimary)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(msg.fromUser ? GGColor.white : GGColor.ink(0.12))
                                    )
                                if !msg.fromUser { Spacer(minLength: 40) }
                            }
                            .id(msg.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: app.dmChat.count) { _, _ in
                    if let last = app.dmChat.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Message…", text: $app.dmDraft, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .glassCapsule(interactive: false)
                Button {
                    app.sendDirectMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
                .disabled(app.dmDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(app.dmDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .padding(16)
        }
        .background(GGColor.bg.ignoresSafeArea())
    }
}

// MARK: - Edit profile

struct EditProfileSheet: View {
    @EnvironmentObject var app: AppState
    @State private var name = ""
    @State private var bio = ""
    @State private var category = "Creator"
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var showChangeUsername = false

    private let categories = ["Creator", "Artist", "Athlete", "Founder", "Photographer", "Musician", "Personal"]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                UserAvatar(size: 88,
                                           gradient: app.user.avatarGradient,
                                           letter: String(app.user.name.prefix(1)),
                                           imageURL: app.user.avatarURL,
                                           imageData: avatarData)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(GGColor.onAccent)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(GGColor.white))
                                    .overlay(Circle().strokeBorder(GGColor.bg, lineWidth: 2))
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.top, 8)

                    field("Name", text: $name)
                    field("Bio", text: $bio, lines: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GGColor.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.self) { cat in
                                    Button { category = cat } label: {
                                        MonoChip(text: cat, active: category == cat)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Button {
                        showChangeUsername = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Username")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(GGColor.textSecondary)
                                Text("@\(app.user.handle)")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(GGColor.textPrimary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(GGColor.textTertiary)
                        }
                        .padding(14)
                        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(GGColor.bg.ignoresSafeArea())
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { app.showEditProfile = false }
                        .foregroundStyle(GGColor.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        app.updateProfile(name: name, bio: bio, category: category)
                        app.showEditProfile = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(GGColor.textPrimary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showChangeUsername) {
            ChangeUsernameSheet().environmentObject(app)
        }
        .onAppear {
            name = app.user.name
            bio = app.user.bio
            category = app.user.category
        }
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    avatarData = data
                    app.syncProfileAvatar(data)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, lines: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            Group {
                if lines {
                    TextField(label, text: text, axis: .vertical)
                        .lineLimit(2...5)
                } else {
                    TextField(label, text: text)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(GGColor.textPrimary)
            .padding(14)
            .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.1)
        }
    }
}

// MARK: - Single-post viewer (profile grid)

struct PostViewerSheet: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                if let post = app.viewingPost {
                    InstagramPostCard(post: post)
                        .padding(.top, 6)
                } else {
                    Text("Post unavailable.")
                        .font(.system(size: 14))
                        .foregroundStyle(GGColor.textTertiary)
                        .padding(.vertical, 60)
                }
            }
            .background(GGColor.bg.ignoresSafeArea())
            .navigationTitle(app.viewingPost?.author ?? "Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { app.closePostViewer() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GGColor.textPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Comments opened from inside this sheet must present from here.
        .sheet(isPresented: Binding(
            get: { app.commentingPostID != nil },
            set: { if !$0 { app.closeComments() } }
        )) {
            CommentsSheet().environmentObject(app)
        }
    }
}
