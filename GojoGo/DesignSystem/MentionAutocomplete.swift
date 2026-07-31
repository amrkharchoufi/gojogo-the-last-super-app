import SwiftUI

/// Drives the `@`-tag picker above a composer.
///
/// Owned by whichever view holds the text, so the caption composer and the
/// comment composer each get their own, and the bar can be dropped above any
/// `TextField` with two lines: `.onChange(of: text) { autocomplete.update(...) }`
/// and a `MentionSuggestionBar`.
@MainActor
final class MentionAutocomplete: ObservableObject {

    /// The rows to offer. Empty means the bar hides itself.
    @Published private(set) var candidates: [MentionCandidate] = []

    /// The partial handle being typed, or nil when the text isn't ending in a
    /// tag. Kept separate from `candidates` so "typed @ but matched nobody"
    /// doesn't read the same as "not tagging anyone".
    @Published private(set) var token: String?

    /// Suggestions drawn from what's already on screen, used before the network
    /// answers and instead of it when the app is running on sample content.
    var localSource: () -> [MentionCandidate] = { [] }

    private var search: Task<Void, Never>?
    /// Long enough that a fast typist makes one request per word, short enough
    /// that the list feels attached to the keyboard.
    private static let debounce = Duration.milliseconds(220)

    func update(for text: String, connected: Bool) {
        guard let token = MentionParser.activeToken(in: text) else {
            reset()
            return
        }
        self.token = token
        // A bare "@" offers whoever is already in front of the user rather than
        // querying the server for every account in existence.
        let local = matchingLocals(token)
        candidates = local
        search?.cancel()
        guard connected, token.count >= 1 else { return }
        search = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled,
                  let remote = try? await SocialStore.shared.searchProfiles(token),
                  !Task.isCancelled else { return }
            guard let self, self.token == token else { return }
            self.candidates = Self.merge(remote: remote, local: local)
        }
    }

    /// Settles the tag being typed and returns the new text. The caller assigns
    /// it back, which is also what re-triggers `update` and closes the bar.
    func complete(_ text: String, with candidate: MentionCandidate) -> String {
        SocialStore.shared.registerProfile(id: candidate.id, handle: candidate.handle)
        reset()
        return MentionParser.complete(text, with: candidate.handle)
    }

    func reset() {
        search?.cancel()
        search = nil
        token = nil
        candidates = []
    }

    private func matchingLocals(_ token: String) -> [MentionCandidate] {
        guard !token.isEmpty else { return Array(localSource().prefix(8)) }
        return localSource()
            .filter { $0.handle.lowercased().hasPrefix(token)
                || $0.name.lowercased().contains(token) }
            .prefix(8)
            .map { $0 }
    }

    /// The server is authoritative; on-screen names fill the tail so the list
    /// doesn't shrink when the query goes out.
    private static func merge(remote: [MentionCandidate],
                              local: [MentionCandidate]) -> [MentionCandidate] {
        var seen = Set(remote.map(\.id))
        return remote + local.filter { seen.insert($0.id).inserted }.prefix(4)
    }
}

/// The row of people offered while typing a tag.
struct MentionSuggestionBar: View {
    @ObservedObject var autocomplete: MentionAutocomplete
    let onPick: (MentionCandidate) -> Void

    var body: some View {
        if !autocomplete.candidates.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(autocomplete.candidates) { candidate in
                        Button { onPick(candidate) } label: { chip(candidate) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func chip(_ candidate: MentionCandidate) -> some View {
        HStack(spacing: 7) {
            UserAvatar(size: 24, letter: String(candidate.handle.prefix(1)).uppercased(),
                       imageURL: candidate.avatarURL)
            Text("@\(candidate.handle)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .lineLimit(1)
            if candidate.verified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textSecondary)
            }
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 5)
        .glassCapsule()
    }
}
