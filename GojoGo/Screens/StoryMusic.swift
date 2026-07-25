import SwiftUI
import AVFoundation

// MARK: - Clip playback

/// Plays one frame's clip window — seeks to the chosen start, stops at the end
/// of the window, and loops if the frame is still on screen.
///
/// Separate from `StoryVideoController` because the two coexist: a video frame
/// with a sound plays the video muted and this on top, which is exactly what
/// Instagram does when you add music to a clip you shot.
@MainActor
final class StoryMusicController: ObservableObject {

    private let player = AVPlayer()
    private var boundaryObserver: Any?
    private var loadedKey: String?
    private var clip: StoryMusic?

    func play(_ music: StoryMusic, muted: Bool) {
        let key = "\(music.audioURL)#\(music.startMs)-\(music.durationMs)"
        if loadedKey != key {
            teardown()
            loadedKey = key
            clip = music
            guard let url = URL(string: music.audioURL), url.scheme != nil else { return }
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            Self.activateAudioSession()
            addLoopBoundary(for: music)
            seekToStart(music)
        }
        player.isMuted = muted
        player.play()
    }

    func setPaused(_ paused: Bool) {
        if paused { player.pause() } else { player.play() }
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    func teardown() {
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedKey = nil
        clip = nil
    }

    private func seekToStart(_ music: StoryMusic) {
        player.seek(to: CMTime(seconds: music.startSeconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// A boundary observer at the clip's end is cheaper and more precise than
    /// polling — the loop point has to land on the beat, not near it.
    private func addLoopBoundary(for music: StoryMusic) {
        let end = CMTime(seconds: music.startSeconds + music.clipSeconds, preferredTimescale: 600)
        boundaryObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: end)], queue: .main
        ) { [weak self] in
            guard let self, let clip = self.clip else { return }
            self.seekToStart(clip)
        }
    }

    private static func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

// MARK: - The sticker

/// The pill Instagram puts on a frame carrying a sound. Sits above the frame's
/// own overlays and is not draggable — it's attribution, not decoration.
struct StoryMusicSticker: View {
    let music: StoryMusic
    var isPlaying: Bool = true
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            artwork

            VStack(alignment: .leading, spacing: 1) {
                Text(music.title)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(music.artist)
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }

            if !compact {
                EqualizerBars(animating: isPlaying)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 7)
        .frame(maxWidth: compact ? 150 : 230, alignment: .leading)
        .glassCapsule(tint: Color.black.opacity(0.4))
    }

    @ViewBuilder
    private var artwork: some View {
        let side: CGFloat = compact ? 18 : 24
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.16))
            if let url = music.artworkURL {
                MediaImage(url: url, cornerRadius: 5)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Four bars that bounce while a sound plays — the cheapest honest signal that
/// there is audio, for anyone watching with the volume down.
struct EqualizerBars: View {
    var animating: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2, height: height(for: i))
            }
        }
        .frame(height: 14, alignment: .center)
        .onAppear { restart() }
        .onChange(of: animating) { _, _ in restart() }
    }

    private func height(for index: Int) -> CGFloat {
        guard animating else { return 4 }
        let offsets: [CGFloat] = [0, 0.25, 0.5, 0.75]
        let wave = sin((phase + offsets[index]) * .pi * 2)
        return 4 + (wave + 1) / 2 * 8
    }

    private func restart() {
        phase = 0
        guard animating else { return }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

// MARK: - Waveform

/// A deterministic waveform for a track — real sample analysis would mean
/// downloading and decoding the whole file just to draw a scrubber. Seeded off
/// the track id so the same song always looks the same.
enum StoryWaveform {

    static func bars(seed: UUID, count: Int = 60) -> [CGFloat] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { _ in CGFloat.random(in: 0.25...1, using: &generator) }
    }

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UUID) {
            var hasher = Hasher()
            hasher.combine(seed)
            state = UInt64(bitPattern: Int64(hasher.finalize())) | 1
        }

        mutating func next() -> UInt64 {
            // xorshift64* — plenty for drawing bars.
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2_685_821_657_736_338_717
        }
    }
}
