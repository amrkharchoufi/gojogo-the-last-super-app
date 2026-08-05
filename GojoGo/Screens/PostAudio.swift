import SwiftUI
import UIKit

// MARK: - Voice post player

/// How an uploaded recording reads in the feed and on a profile: a wide
/// outlined card with one play control and a waveform that lights up as it
/// plays. No duration label — the length isn't on the wire, and a number that
/// showed on your own copy of a post and nowhere else reads as a bug.
///
/// Playback runs through `ChatAudioPlayer`, the same one voice messages use, so
/// starting a post stops a message and vice versa — one sound at a time.
struct PostVoiceNote: View {
    let post: Post
    /// Full-bleed feed card vs. the inset list row on a profile.
    var height: CGFloat = 64

    @ObservedObject private var audio = ChatAudioPlayer.shared

    private var isPlaying: Bool { audio.isPlaying(post.id) }
    private var isLoading: Bool { audio.loadingID == post.id }
    private var failed: Bool { audio.failedID == post.id }
    private var progress: Double { audio.progress(for: post.id) }

    private var bars: [CGFloat] { Self.waveform(seed: post.id) }

    var body: some View {
        HStack(spacing: 14) {
            playControl
            waveform
        }
        .padding(.leading, 18)
        .padding(.trailing, 22)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: height / 2.6, style: .continuous)
                .strokeBorder(GGColor.ink(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: height / 2.6, style: .continuous))
        .onTapGesture { toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(failed ? "Audio unavailable" : (isPlaying ? "Pause audio" : "Play audio"))
        .accessibilityAction { toggle() }
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        audio.toggle(messageID: post.id, url: post.playableAudioURL)
    }

    private var playControl: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(GGColor.textPrimary)
            } else {
                Image(systemName: failed ? "exclamationmark.triangle.fill"
                                         : (isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: failed ? 18 : 26, weight: .medium))
                    .foregroundStyle(failed ? GGColor.textTertiary : GGColor.textPrimary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 30, height: 30)
    }

    /// Bars share the row evenly, so the same waveform fits every width without
    /// the last bars falling off a narrow phone.
    private var waveform: some View {
        HStack(spacing: 0) {
            ForEach(Array(bars.enumerated()), id: \.offset) { i, bar in
                let played = Double(i) / Double(bars.count) <= progress
                Capsule()
                    .fill(GGColor.textPrimary.opacity(played ? 0.95 : 0.28))
                    .frame(width: 2.5, height: max(2, bar * (height - 24)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height - 24)
        .animation(.linear(duration: 0.06), value: progress)
    }

    /// Deterministic from the post id, so a clip looks the same to everyone who
    /// sees it — the bars are a signature, not a live analysis of the file.
    private static func waveform(seed: UUID) -> [CGFloat] {
        var state = UInt64(truncatingIfNeeded: seed.hashValue) | 1
        return (0..<44).map { i in
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            let base = 0.25 + CGFloat(state % 75) / 100
            // Ease the first and last few bars down so the shape starts and ends
            // like a recording rather than being cut off mid-sentence.
            let edge = min(CGFloat(i), CGFloat(43 - i)) / 5
            return base * min(1, max(0.06, edge))
        }
    }
}
