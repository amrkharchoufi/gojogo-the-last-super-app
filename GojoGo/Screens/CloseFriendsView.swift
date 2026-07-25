import SwiftUI

/// Your close-friends list — who can see a story you post to that audience.
///
/// One-directional and private by design: the people on it are never told, and
/// being on someone's list says nothing about whether they're on yours. It's
/// enforced on read, so taking someone off also takes away their access to the
/// close-friends stories you already posted.
struct CloseFriendsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<UUID> = []
    @State private var candidates: [CloseFriend] = []
    @State private var query = ""
    @State private var loading = true
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.bg.ignoresSafeArea()

                if loading {
                    ProgressView().tint(GGColor.textSecondary)
                } else if candidates.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Close friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(GGColor.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saving ? "Saving…" : "Done") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GGColor.accent)
                        .disabled(saving)
                }
            }
            .preferredColorScheme(.dark)
        }
        .task { await load() }
    }

    private var filtered: [CloseFriend] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.lowercased().contains(q) || ($0.handle ?? "").lowercased().contains(q)
        }
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text("Only these people see a story you share to close friends. They're never notified they're on the list.")
                    .explanatory(13)
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textTertiary)
                    TextField("Search", text: $query)
                        .font(.system(size: 14))
                        .foregroundStyle(GGColor.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GGColor.surface))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                ForEach(filtered) { person in
                    row(person)
                    Divider().overlay(GGColor.hairline).padding(.leading, 62)
                }
            }
            .padding(.bottom, 30)
        }
    }

    private func row(_ person: CloseFriend) -> some View {
        let isOn = selected.contains(person.id)
        return HStack(spacing: 12) {
            UserAvatar(size: 38, letter: String(person.name.prefix(1)).uppercased(),
                       imageURL: person.avatarURL)

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
                if let handle = person.handle {
                    Text("@\(handle)")
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textTertiary)
                }
            }

            Spacer()

            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isOn ? GGColor.accent : GGColor.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.ggSnappy) {
                if isOn { selected.remove(person.id) } else { selected.insert(person.id) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(GGColor.textTertiary)
            Text("No one to add yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Follow some people first — then you can pick who sees your close-friends stories.")
                .explanatory(13)
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func load() async {
        await app.refreshCloseFriends()
        selected = Set(app.closeFriends.map(\.id))

        // Candidates = whoever is already on the list, plus the people whose
        // rings we know about. A real "following" picker arrives with the
        // follow-list endpoint; until then this covers the realistic case.
        var seen = Set(app.closeFriends.map(\.id))
        var all = app.closeFriends
        for story in app.stories where !story.isYou && !seen.contains(story.id) {
            seen.insert(story.id)
            all.append(CloseFriend(id: story.id, name: story.name,
                                   handle: story.name, avatarURL: story.avatarURL))
        }
        candidates = all
        loading = false
    }

    private func save() {
        saving = true
        Task {
            await app.saveCloseFriends(Array(selected))
            saving = false
            dismiss()
        }
    }
}
