import SwiftUI

/// My World — private social hub, designed to mirror Apple Messages.
struct MyWorldView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if app.showWorldContact, app.selectedWorldContact != nil || app.selectedWorldConversation != nil {
                WorldContactView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
            } else if let id = app.selectedWorldConversationID,
                      app.worldConversations.contains(where: { $0.id == id }) {
                WorldChatView(conversationID: id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                WorldMessagesList()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: app.selectedWorldConversationID)
        .animation(.easeInOut(duration: 0.28), value: app.showWorldContact)
        .sheet(isPresented: $app.showWorldNewMessage) {
            NewWorldMessageSheet()
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(white: 0.09))
        }
    }
}

// MARK: - Messages list (iMessage home)

private struct WorldMessagesList: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            topBar
            listContent
        }
        .overlay(alignment: .topTrailing) {
            if app.showWorldFilters {
                filtersMenu
                    .padding(.trailing, 12)
                    .padding(.top, 48)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { app.worldIsEditing.toggle() }
            } label: {
                Text(app.worldIsEditing ? "Done" : "Edit")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(IMColor.chrome))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.showWorldNewMessage = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(IMColor.chrome))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New message")

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    app.showWorldFilters.toggle()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(IMColor.chrome))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var filtersMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterRow("All Messages", "message", checked: !app.worldFilterUnreadOnly) {
                app.worldFilterUnreadOnly = false
                app.showWorldFilters = false
            }
            Divider().background(Color.white.opacity(0.1))
            filterRow("Unread Only", "circle.fill", checked: app.worldFilterUnreadOnly) {
                app.worldFilterUnreadOnly = true
                app.showWorldFilters = false
            }
            Divider().background(Color.white.opacity(0.1))
            filterRow("Add by Phone", "phone.badge.plus") {
                app.showWorldFilters = false
                app.showWorldNewMessage = true
            }
            Divider().background(Color.white.opacity(0.1))
            filterRow("Add by Username", "at") {
                app.showWorldFilters = false
                app.showWorldNewMessage = true
            }
        }
        .padding(.vertical, 6)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(IMColor.chrome.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
    }

    private func filterRow(_ title: String, _ icon: String, checked: Bool? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(IMColor.blue)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                Spacer()
                if checked == true {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IMColor.blue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var titleRow: some View {
        HStack {
            Text("My World")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(IMColor.secondary)
            TextField("Search", text: $app.worldSearch)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .tint(IMColor.blue)
                .autocorrectionDisabled()
            if !app.worldSearch.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { app.worldSearch = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(IMColor.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(IMColor.inputFill)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var listContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                titleRow
                searchBar

                if !app.worldPinnedConversations.isEmpty {
                    pinnedGrid
                        .padding(.bottom, 10)
                }

                circlesStrip
                    .padding(.bottom, 8)

                // Full Messages list — includes threads started from Circles.
                ForEach(app.worldFilteredConversations) { convo in
                    conversationCell(convo)

                    Rectangle()
                        .fill(IMColor.separator.opacity(0.65))
                        .frame(height: 0.33)
                        .padding(.leading, 86)
                }

                if app.worldFilteredConversations.isEmpty {
                    emptyState
                }

                Color.clear.frame(height: tabBarInset + 12)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(TapGesture().onEnded {
            if app.showWorldFilters {
                withAnimation { app.showWorldFilters = false }
            }
        })
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: app.worldFilterUnreadOnly ? "checkmark.message" : "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(IMColor.secondary)
            Text(app.worldFilterUnreadOnly ? "No unread messages" : "No results")
                .font(.system(size: 15))
                .foregroundStyle(IMColor.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    // MARK: Pinned (iMessage big avatars)

    private var pinnedGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                  spacing: 14) {
            ForEach(app.worldPinnedConversations) { convo in
                Button {
                    if app.worldIsEditing {
                        app.togglePinWorldConversation(convo.id)
                    } else {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.openWorldConversation(convo.id)
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            pinnedAvatar(convo)
                            if app.worldIsEditing {
                                Image(systemName: "minus.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color(red: 1, green: 0.27, blue: 0.23))
                                    .font(.system(size: 22))
                                    .offset(x: 4, y: -4)
                            } else if convo.unread > 0 {
                                Text("\(convo.unread)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(IMColor.blue))
                                    .offset(x: 6, y: -2)
                            }
                        }
                        Text(convo.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { rowMenu(convo) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func pinnedAvatar(_ convo: WorldConversation) -> some View {
        if convo.isGroup {
            Circle()
                .fill(IMColor.chrome)
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.white.opacity(0.75))
                )
        } else {
            UserAvatar(
                size: 72,
                gradient: convo.avatarGradient,
                letter: String(convo.title.prefix(1)),
                imageURL: convo.avatarURL
            )
        }
    }

    // MARK: Circles

    private var circlesStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Circles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IMColor.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(app.worldCircles) { circle in
                        let members = app.worldContacts.filter { circle.memberIDs.contains($0.id) }
                        let shown = Array(members.prefix(3))
                        VStack(spacing: 8) {
                            // Overlap lightly so faces stay readable / tappable.
                            ZStack(alignment: .leading) {
                                ForEach(Array(shown.enumerated()), id: \.element.id) { i, contact in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        app.startWorldConversation(with: contact)
                                    } label: {
                                        UserAvatar(
                                            size: 44,
                                            gradient: contact.avatarGradient,
                                            letter: String(contact.name.prefix(1)),
                                            imageURL: contact.avatarURL
                                        )
                                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 2.5))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: CGFloat(i) * 28)
                                    .zIndex(Double(i))
                                }
                                if shown.isEmpty {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        app.openWorldCircle(circle)
                                    } label: {
                                        Circle()
                                            .fill(IMColor.chrome)
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Image(systemName: "person.2.fill")
                                                    .font(.system(size: 15))
                                                    .foregroundStyle(.white.opacity(0.7))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(
                                width: shown.isEmpty ? 44 : 44 + CGFloat(shown.count - 1) * 28,
                                height: 44,
                                alignment: .leading
                            )

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                app.openWorldCircle(circle)
                            } label: {
                                Text(circle.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(minWidth: 96)
                        .contextMenu {
                            Button {
                                app.openWorldCircle(circle)
                            } label: {
                                Label("Open \(circle.name)", systemImage: "person.2")
                            }
                            ForEach(members) { contact in
                                Button {
                                    app.startWorldConversation(with: contact)
                                } label: {
                                    Label(contact.name, systemImage: "message")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Rows

    private func conversationCell(_ convo: WorldConversation) -> some View {
        HStack(spacing: 0) {
            if app.worldIsEditing {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    app.deleteWorldConversation(convo.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(red: 1, green: 0.27, blue: 0.23))
                        .font(.system(size: 22))
                        .padding(.leading, 14)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Button {
                guard !app.worldIsEditing else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.openWorldConversation(convo.id)
            } label: {
                conversationRow(convo)
            }
            .buttonStyle(.plain)
            .contextMenu { rowMenu(convo) }
        }
        .animation(.easeOut(duration: 0.2), value: app.worldIsEditing)
    }

    @ViewBuilder
    private func rowMenu(_ convo: WorldConversation) -> some View {
        Button {
            app.togglePinWorldConversation(convo.id)
        } label: {
            Label(convo.pinned ? "Unpin" : "Pin", systemImage: convo.pinned ? "pin.slash" : "pin")
        }
        Button {
            app.toggleUnreadWorldConversation(convo.id)
        } label: {
            Label(convo.unread > 0 ? "Mark as Read" : "Mark as Unread",
                  systemImage: convo.unread > 0 ? "message.badge.filled.fill" : "message.badge")
        }
        Button(role: .destructive) {
            app.deleteWorldConversation(convo.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func conversationRow(_ convo: WorldConversation) -> some View {
        HStack(alignment: .center, spacing: 0) {
            // Unread blue dot
            Circle()
                .fill(convo.unread > 0 ? IMColor.blue : .clear)
                .frame(width: 10, height: 10)
                .padding(.leading, 10)
                .padding(.trailing, 8)

            Group {
                if convo.isGroup {
                    Circle()
                        .fill(IMColor.chrome)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.white.opacity(0.75))
                        )
                } else {
                    UserAvatar(
                        size: 52,
                        gradient: convo.avatarGradient,
                        letter: String(convo.title.prefix(1)),
                        imageURL: convo.avatarURL
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(convo.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(convo.timeAgo)
                        .font(.system(size: 15))
                        .foregroundStyle(IMColor.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IMColor.secondary.opacity(0.55))
                }

                HStack(alignment: .top, spacing: 6) {
                    if let badge = convo.filterBadge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(IMColor.chrome)
                            )
                    }
                    Text(convo.preview)
                        .font(.system(size: 15))
                        .foregroundStyle(IMColor.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .opacity(app.worldIsEditing ? 0.85 : 1)
    }
}

// MARK: - New message sheet

private struct NewWorldMessageSheet: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [WorldContact] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return app.worldContacts }
        return app.worldContacts.filter {
            $0.name.lowercased().contains(q)
                || $0.username.lowercased().contains(q)
                || $0.phone.replacingOccurrences(of: " ", with: "").contains(q.replacingOccurrences(of: " ", with: ""))
        }
    }

    private var canAddNew: Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !q.isEmpty && results.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            toField

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if canAddNew {
                        addNewRow
                    }
                    ForEach(results) { contact in
                        contactRow(contact)
                        Divider()
                            .background(Color.white.opacity(0.07))
                            .padding(.leading, 66)
                    }
                }
                .padding(.top, 6)
            }
        }
        .background(Color(white: 0.09).ignoresSafeArea())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
    }

    private var header: some View {
        ZStack {
            Text("New Message")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            HStack {
                Spacer()
                Button("Cancel") { app.showWorldNewMessage = false }
                    .font(.system(size: 17))
                    .foregroundStyle(IMColor.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var toField: some View {
        HStack(spacing: 8) {
            Text("To:")
                .font(.system(size: 16))
                .foregroundStyle(IMColor.secondary)
            TextField("Name, @username, or phone", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .tint(IMColor.blue)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    if canAddNew { app.addWorldContact(query) }
                    else if let first = results.first { app.startWorldConversation(with: first) }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .bottom) {
            Rectangle().fill(IMColor.separator.opacity(0.6)).frame(height: 0.33)
        }
    }

    private var addNewRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            app.addWorldContact(query)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 26))
                    .foregroundStyle(IMColor.blue)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a chat with \"\(query.trimmingCharacters(in: .whitespaces))\"")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Adds them to My World")
                        .font(.system(size: 13))
                        .foregroundStyle(IMColor.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func contactRow(_ contact: WorldContact) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            app.startWorldConversation(with: contact)
        } label: {
            HStack(spacing: 12) {
                UserAvatar(
                    size: 44,
                    gradient: contact.avatarGradient,
                    letter: String(contact.name.prefix(1)),
                    imageURL: contact.avatarURL
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(contact.phone.isEmpty ? "@\(contact.username)" : contact.phone)
                        .font(.system(size: 13))
                        .foregroundStyle(IMColor.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
