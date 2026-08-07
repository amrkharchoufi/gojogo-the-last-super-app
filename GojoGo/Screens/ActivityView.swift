import SwiftUI
import PhotosUI

// MARK: - Activity (notifications)

/// One row of the activity feed: usually a single notification, sometimes a
/// run of them collapsed into "…and 4 others".
///
/// Grouping happens here rather than on the server because it is a property of
/// how the list is *read* — five people liking one post is one event to the
/// person scrolling, and five rows of it push everything else off the screen.
/// The members stay intact so a tap still routes off a real notification and
/// "read" still means all of them.
struct ActivityGroup: Identifiable {
    let items: [ActivityItem]

    var id: UUID { lead.id }
    var lead: ActivityItem { items[0] }
    var count: Int { items.count }
    var read: Bool { items.allSatisfy(\.read) }

    /// "amina", "amina and jonas", "amina, jonas and 4 others".
    var actors: String {
        let names = items.map(\.actor)
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) others"
        }
    }

    /// Only likes on the same post collapse. A comment is something somebody
    /// said, and a row that hides four of them to save two lines is worse than
    /// the four rows.
    static func group(_ items: [ActivityItem]) -> [ActivityGroup] {
        var out: [ActivityGroup] = []
        var run: [ActivityItem] = []

        func flush() {
            guard !run.isEmpty else { return }
            out.append(ActivityGroup(items: run))
            run = []
        }
        for item in items {
            if item.kind == .like, let postID = item.postID,
               let first = run.first, first.postID == postID,
               // Never collapse across the read line: a group is one row, and
               // one row cannot be half-new.
               first.read == item.read {
                run.append(item)
            } else {
                flush()
                run = [item]
            }
        }
        flush()
        return out
    }
}

/// The date headings, Instagram-style: what "when" means to somebody scrolling
/// is today / yesterday / this week, not a timestamp.
enum ActivityBucket: Int, CaseIterable {
    case today, yesterday, week, month, earlier

    var label: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .earlier: return "Earlier"
        }
    }

    static func of(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> ActivityBucket {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if days < 7 { return .week }
        if days < 30 { return .month }
        return .earlier
    }
}

/// One heading and the rows under it.
struct ActivitySection: Identifiable {
    let bucket: ActivityBucket
    let groups: [ActivityGroup]

    var id: Int { bucket.rawValue }
}

struct ActivityView: View {
    @EnvironmentObject var app: AppState

    private var unread: [ActivityGroup] {
        ActivityGroup.group(app.notifications.filter { !$0.read })
    }

    /// Read rows, split into date headings. Empty buckets are dropped.
    private var earlier: [ActivitySection] {
        let read = app.notifications.filter(\.read)
        return ActivityBucket.allCases.compactMap { bucket -> ActivitySection? in
            let inBucket = read.filter { ActivityBucket.of($0.createdAt) == bucket }
            guard !inBucket.isEmpty else { return nil }
            return ActivitySection(bucket: bucket, groups: ActivityGroup.group(inBucket))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.bg.ignoresSafeArea()
                // The empty state lives *inside* the scroll view rather than
                // beside it: "nothing here yet" is exactly when someone reaches
                // for a pull-to-refresh, so it has to be pullable too.
                ScrollView(showsIndicators: false) {
                    if app.notifications.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "heart")
                                .font(.system(size: 34))
                                .foregroundStyle(GGColor.textTertiary)
                            Text("Activity on your posts shows up here.")
                                .font(.system(size: 14))
                                .foregroundStyle(GGColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 140)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if !unread.isEmpty {
                                sectionLabel("New")
                                ForEach(unread) { row($0) }
                            }
                            ForEach(earlier) { section in
                                sectionLabel(section.bucket.label)
                                ForEach(section.groups) { row($0) }
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
                .refreshable { await app.refreshNotifications() }
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

    /// The row is a tap target rather than a `Button` because it contains one —
    /// nested buttons both fire, and "Follow back" would also open the profile.
    private func row(_ group: ActivityGroup) -> some View {
        let item = group.lead
        return HStack(spacing: 12) {
            avatar(group)

            VStack(alignment: .leading, spacing: 3) {
                (Text(group.actors).fontWeight(.semibold)
                 + Text(" \(item.text) ")
                 + Text(item.timeAgo).foregroundColor(GGColor.textTertiary))
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)

                // What was actually said, or — on a like — the caption of the
                // post in question. The thumbnail answers "which post" when
                // there is a picture; this answers it when there isn't.
                if let snippet = item.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing(group)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(group.read ? Color.clear : GGColor.ink(0.035))
        .contentShape(Rectangle())
        .onTapGesture { app.handleActivityTap(item) }
    }

    /// The actor's picture with the kind badge. A collapsed group stacks the
    /// second face behind the first, which is what says "more than one person"
    /// before the text does.
    private func avatar(_ group: ActivityGroup) -> some View {
        let item = group.lead
        return ZStack(alignment: .bottomTrailing) {
            if group.count > 1, let second = group.items.dropFirst().first {
                UserAvatar(size: 34,
                           letter: String(second.actor.prefix(1)).uppercased(),
                           imageURL: second.avatarURL)
                    .overlay(Circle().strokeBorder(GGColor.bg, lineWidth: 2))
                    .offset(x: -12, y: -8)
            }
            UserAvatar(size: 44,
                       letter: String(item.actor.prefix(1)).uppercased(),
                       imageURL: item.avatarURL)
                .overlay(Circle().strokeBorder(GGColor.bg, lineWidth: group.count > 1 ? 2 : 0))
            Image(systemName: item.kind.icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(item.kind.tint))
                .overlay(Circle().strokeBorder(GGColor.bg, lineWidth: 2))
                .offset(x: 3, y: 3)
        }
        .frame(width: 50, height: 44, alignment: .bottomTrailing)
    }

    /// The post it happened on, a follow-back button, or the unread dot — in
    /// that order, because the thumbnail is the one that answers a question.
    @ViewBuilder
    private func trailing(_ group: ActivityGroup) -> some View {
        let item = group.lead
        if let preview = item.previewURL {
            MediaImage(url: preview, cornerRadius: 8)
                .frame(width: 44, height: 44)
                .clipped()
        } else if item.kind == .follow, !item.actorFollowed {
            Button {
                app.followBack(item)
            } label: {
                Text("Follow back")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(GGColor.blue))
            }
            .buttonStyle(PressableStyle())
        } else if item.kind == .follow, item.actorFollowed {
            Text("Following")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassCapsule(interactive: false)
        } else if !group.read {
            Circle().fill(GGColor.blue).frame(width: 8, height: 8)
        }
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
