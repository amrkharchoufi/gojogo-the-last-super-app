import SwiftUI

/// Finding `@handle` tokens in a body of text.
///
/// The grammar here **must** mirror the server's `MentionService.MENTION`
/// pattern and `Handles.normalize`: the client underlines what the server
/// resolved, and a client that highlights a token the server ignored (or the
/// reverse) is a tag that looks tappable and isn't.
enum MentionParser {

    /// The characters a handle is made of, server-side: `[a-z0-9_.]`.
    static func isHandleCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == ".")
    }

    /// A tag found in text: where it sits, and the handle it names (lowercased).
    struct Span {
        let range: Range<String.Index>
        let handle: String
    }

    /// Every tag in `text`, in order.
    ///
    /// The leading-boundary rule is what keeps an email address from reading as
    /// a tag — "me@example.com" must not link @example — and the trailing dot is
    /// dropped because handles may contain dots, so "thanks @amina." names
    /// @amina and not @amina.
    static func spans(in text: String) -> [Span] {
        guard text.contains("@") else { return [] }
        var found: [Span] = []
        var i = text.startIndex
        while i < text.endIndex, let at = text[i...].firstIndex(of: "@") {
            let afterAt = text.index(after: at)
            // Preceded by handle characters or another "@" — this is the tail of
            // an email address or a doubled sigil, not the start of a tag.
            let boundaryOK = at == text.startIndex || {
                let previous = text[text.index(before: at)]
                return !isHandleCharacter(previous) && previous != "@"
            }()
            guard boundaryOK else {
                i = afterAt
                continue
            }
            var end = afterAt
            while end < text.endIndex, isHandleCharacter(text[end]),
                  text.distance(from: afterAt, to: end) < 30 {
                end = text.index(after: end)
            }
            // Trailing dots are sentence punctuation, not part of the handle.
            while end > afterAt, text[text.index(before: end)] == "." {
                end = text.index(before: end)
            }
            if text.distance(from: afterAt, to: end) >= 2 {
                found.append(Span(range: at..<end, handle: String(text[afterAt..<end]).lowercased()))
            }
            i = max(end, afterAt)
        }
        return found
    }

    /// The handles tagged in `text`, deduplicated, in order of appearance.
    static func handles(in text: String) -> [String] {
        var seen: Set<String> = []
        return spans(in: text).compactMap { seen.insert($0.handle).inserted ? $0.handle : nil }
    }

    /// A best-effort local resolution, for the optimistic copy of a comment the
    /// app shows before the server answers. Only handles this device has already
    /// seen resolve; the rest arrive with the server's version a moment later.
    @MainActor
    static func resolveLocally(in text: String) -> [Mention] {
        handles(in: text).compactMap { handle in
            SocialStore.shared.profileId(forHandle: handle)
                .map { Mention(profileID: $0, handle: handle) }
        }
    }

    /// The partial `@token` being typed, or nil when the text doesn't end in one.
    ///
    /// SwiftUI's `TextField` exposes no caret position, so this reads the **last**
    /// `@` in the text and treats the run after it as live. That is exactly right
    /// while a tag is being typed at the end — which is how tags get typed — and
    /// deliberately gives up when the caret has been moved back into the middle
    /// of an earlier sentence, rather than guessing wrong there.
    static func activeToken(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex {
            let previous = text[text.index(before: at)]
            if isHandleCharacter(previous) || previous == "@" { return nil }
        }
        let token = text[text.index(after: at)...]
        guard token.count <= 30, token.allSatisfy(isHandleCharacter) else { return nil }
        return String(token).lowercased()
    }

    /// Replaces the partial token at the end of `text` with a settled tag.
    static func complete(_ text: String, with handle: String) -> String {
        guard let at = text.lastIndex(of: "@") else { return text + "@\(handle) " }
        return String(text[..<at]) + "@\(handle) "
    }
}

// MARK: - Rendering

/// Body text with its `@handle` tags picked out and tappable.
///
/// **Tags are marked by weight, not colour.** The palette is monochrome by
/// design (`GGColor.accent` *is* the ink), so a "highlight colour" would either
/// be invisible or would be the one hue in the whole app — semibold against the
/// body's regular weight is the emphasis this design system actually has.
///
/// Tapping resolves through `mentions` when the server supplied them, and falls
/// back to the handle alone otherwise — which is what makes tags in sample
/// content and in video comments (whose module has no mention table) still work.
struct MentionedText: View {
    let text: String
    var mentions: [Mention] = []
    var font: Font = .system(size: 15)
    var color: Color = GGColor.textPrimary
    let onOpenProfile: (String, UUID?) -> Void

    /// Private scheme so a tag never escapes to Safari. The handle rides in the
    /// path rather than the host because a host may not contain `_`.
    private static let scheme = "gojogo-mention"

    var body: some View {
        Text(attributed)
            .tint(color)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == Self.scheme else { return .systemAction }
                let handle = String(url.path.dropFirst()).removingPercentEncoding
                    ?? String(url.path.dropFirst())
                onOpenProfile(handle, profileID(for: handle))
                return .handled
            })
    }

    private func profileID(for handle: String) -> UUID? {
        mentions.first { $0.handle.caseInsensitiveCompare(handle) == .orderedSame }?.profileID
            ?? SocialStore.shared.profileId(forHandle: handle)
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        var cursor = text.startIndex
        for span in MentionParser.spans(in: text) {
            out.append(plain(String(text[cursor..<span.range.lowerBound])))
            out.append(tag(span.handle, label: String(text[span.range])))
            cursor = span.range.upperBound
        }
        out.append(plain(String(text[cursor...])))
        return out
    }

    private func plain(_ string: String) -> AttributedString {
        guard !string.isEmpty else { return AttributedString() }
        var run = AttributedString(string)
        run.font = font
        run.foregroundColor = color
        return run
    }

    private func tag(_ handle: String, label: String) -> AttributedString {
        var run = AttributedString(label)
        run.font = font.weight(.semibold)
        run.foregroundColor = color
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        run.link = URL(string: "\(Self.scheme):///\(encoded)")
        return run
    }
}
