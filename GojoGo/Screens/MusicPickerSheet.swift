import SwiftUI
import AVFoundation

/// Pick a track, then pick the 15 seconds of it that go on the story.
///
/// Two steps, like Instagram: browse/search with a preview, then scrub a window
/// over the waveform. The window is what gets sent — the server re-resolves the
/// track's metadata, so nothing displayed here is trusted on the way back.
struct MusicPickerSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// Pre-selected when re-opening the picker on a frame that already has a sound.
    var current: StoryMusic?
    let onPick: (StoryMusic?) -> Void

    @State private var tracks: [MusicTrack] = []
    @State private var query = ""
    @State private var loading = true
    @State private var failed = false
    @State private var chosen: MusicTrack?
    @State private var startSeconds: Double = 0
    @StateObject private var preview = MusicPreviewPlayer()

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.sheetBG.ignoresSafeArea()

                if let chosen {
                    clipStep(for: chosen)
                } else {
                    browseStep
                }
            }
            .navigationTitle(chosen == nil ? "Music" : "Choose the part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.large])
        .task { await load() }
        .onDisappear { preview.stop() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(chosen == nil ? "Cancel" : "Back") {
                if chosen == nil {
                    dismiss()
                } else {
                    preview.stop()
                    withAnimation(.ggSnappy) { chosen = nil }
                }
            }
            .foregroundStyle(GGColor.textSecondary)
        }
        ToolbarItem(placement: .topBarTrailing) {
            if chosen != nil {
                Button("Done") { commit() }
                    .fontWeight(.semibold)
                    .foregroundStyle(GGColor.accent)
            } else if current != nil {
                Button("Remove", role: .destructive) {
                    onPick(nil)
                    dismiss()
                }
            }
        }
    }

    // MARK: Step 1 — browse

    private var browseStep: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textTertiary)
                TextField("Search songs or artists", text: $query)
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textPrimary)
                    .submitLabel(.search)
                    .onSubmit { Task { await load() } }
                if !query.isEmpty {
                    Button {
                        query = ""
                        Task { await load() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(GGColor.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GGColor.surface))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if loading {
                Spacer()
                ProgressView().tint(GGColor.textSecondary)
                Spacer()
            } else if tracks.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            trackRow(track)
                            Divider().overlay(GGColor.hairline).padding(.leading, 68)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    private func trackRow(_ track: MusicTrack) -> some View {
        HStack(spacing: 12) {
            Button {
                preview.toggle(track)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(GGColor.surface2)
                    if let art = track.artworkURL {
                        MediaImage(url: art, cornerRadius: 8)
                    }
                    Image(systemName: preview.isPlaying(track.id) ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(track.durationLabel)
                .font(.ggMono(11))
                .foregroundStyle(GGColor.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { choose(track) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: failed ? "wifi.slash" : "music.note.list")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(GGColor.textTertiary)
            Text(failed ? "Couldn't load music"
                 : query.isEmpty ? "No music yet" : "Nothing matched")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text(failed ? "Check your connection and try again."
                 : query.isEmpty ? "The sound library is still being filled in."
                                 : "Try a different song or artist.")
                .explanatory(13)
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
        }
    }

    // MARK: Step 2 — clip

    private func clipStep(for track: MusicTrack) -> some View {
        VStack(spacing: 22) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GGColor.surface2)
                    if let art = track.artworkURL {
                        MediaImage(url: art, cornerRadius: 10)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 22))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ClipScrubber(
                track: track,
                startSeconds: $startSeconds,
                clipSeconds: clipSeconds(for: track))
                .padding(.horizontal, 20)

            Text("Starts at \(timeLabel(startSeconds)) · \(Int(clipSeconds(for: track).rounded()))s")
                .font(.ggMono(12))
                .foregroundStyle(GGColor.textSecondary)

            Text("Drag to pick the part of the song that plays over your story.")
                .explanatory(13)
                .foregroundStyle(GGColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .onChange(of: startSeconds) { _, new in
            preview.scrub(to: new, of: track)
        }
    }

    /// A short track can't yield a 15s clip — the window shrinks to fit it.
    private func clipSeconds(for track: MusicTrack) -> Double {
        min(Double(StoryMusic.maxClipMs) / 1000, Double(track.durationMs) / 1000)
    }

    // MARK: Actions

    private func load() async {
        loading = true
        failed = false
        do {
            tracks = try await MusicStore.shared.browse(query: query)
        } catch {
            tracks = []
            failed = true
        }
        loading = false
    }

    private func choose(_ track: MusicTrack) {
        // Re-opening on the frame's existing track keeps the window you set.
        startSeconds = current?.trackID == track.id ? current?.startSeconds ?? 0 : 0
        withAnimation(.ggSnappy) { chosen = track }
        preview.play(track, from: startSeconds)
    }

    private func commit() {
        guard let track = chosen else { return }
        preview.stop()
        onPick(StoryMusic(
            trackID: track.id,
            title: track.title,
            artist: track.artist,
            artworkURL: track.artworkURL,
            audioURL: track.audioURL,
            startMs: Int(startSeconds * 1000),
            durationMs: Int(clipSeconds(for: track) * 1000)))
        dismiss()
    }

    private func timeLabel(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

// MARK: - Scrubber

/// A waveform with a draggable window over it.
private struct ClipScrubber: View {
    let track: MusicTrack
    @Binding var startSeconds: Double
    let clipSeconds: Double

    @State private var dragStart: Double?

    private var total: Double { max(Double(track.durationMs) / 1000, 0.1) }
    private var maxStart: Double { max(total - clipSeconds, 0) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let windowWidth = width * (clipSeconds / total)
            let offset = maxStart > 0 ? (startSeconds / maxStart) * (width - windowWidth) : 0

            ZStack(alignment: .leading) {
                waveform(dimmed: true)

                waveform(dimmed: false)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: windowWidth)
                            .offset(x: offset)
                    }

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(GGColor.accent, lineWidth: 2)
                    .frame(width: windowWidth)
                    .offset(x: offset)
                    .shadow(color: .black.opacity(0.4), radius: 6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard maxStart > 0, width > windowWidth else { return }
                        if dragStart == nil { dragStart = startSeconds }
                        let perPoint = maxStart / (width - windowWidth)
                        let next = (dragStart ?? 0) + value.translation.width * perPoint
                        startSeconds = min(max(next, 0), maxStart)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(height: 64)
    }

    private func waveform(dimmed: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(StoryWaveform.bars(seed: track.id).enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(dimmed ? GGColor.ink(0.18) : GGColor.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64 * value)
            }
        }
        .frame(height: 64)
    }
}

// MARK: - Preview playback

/// Plays a track while you browse and while you scrub. Separate from the
/// viewer's player: this one is throwaway and never loops a window.
@MainActor
final class MusicPreviewPlayer: ObservableObject {

    @Published private(set) var playingID: UUID?

    private let player = AVPlayer()

    func isPlaying(_ id: UUID) -> Bool { playingID == id }

    func toggle(_ track: MusicTrack) {
        if playingID == track.id {
            stop()
        } else {
            play(track, from: 0)
        }
    }

    func play(_ track: MusicTrack, from seconds: Double) {
        guard let url = URL(string: track.audioURL), url.scheme != nil else { return }
        if playingID != track.id {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            playingID = track.id
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    /// Scrubbing re-seeks the live preview so you hear where the clip starts.
    func scrub(to seconds: Double, of track: MusicTrack) {
        guard playingID == track.id else {
            play(track, from: seconds)
            return
        }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        playingID = nil
    }
}
