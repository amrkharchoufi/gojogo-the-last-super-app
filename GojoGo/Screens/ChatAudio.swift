import SwiftUI
import AVFoundation
import Combine
import UIKit

// MARK: - Voice note playback

/// Plays one voice note at a time across the whole chat (iMessage behaviour:
/// starting a second bubble stops the first). Remote clips are downloaded to the
/// caches directory once and replayed from disk afterwards.
@MainActor
final class ChatAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = ChatAudioPlayer()

    /// Message id of the bubble currently playing (nil when idle/paused).
    @Published private(set) var playingID: UUID?
    /// Message whose clip is loaded — playing or paused part-way through.
    @Published private(set) var loadedID: UUID?
    /// Message id currently fetching its audio file.
    @Published private(set) var loadingID: UUID?
    /// 0…1 through the clip that's playing.
    @Published private(set) var progress: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    /// Set when a clip can't be fetched, so the bubble can show it instead of
    /// silently doing nothing.
    @Published private(set) var failedID: UUID?

    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var downloads: [UUID: Task<Void, Never>] = [:]

    func isPlaying(_ id: UUID) -> Bool { playingID == id }

    /// How far through the given clip we are — 0 for any other bubble, and held
    /// at the pause point rather than snapping back to the start.
    func progress(for id: UUID) -> Double { loadedID == id ? progress : 0 }

    /// Play / pause / resume the given message.
    func toggle(messageID: UUID, url: URL?) {
        failedID = nil
        if playingID == messageID {
            pause()
            return
        }
        // Same clip, paused part-way — pick it back up.
        if loadedID == messageID, let player {
            player.play()
            playingID = messageID
            startTicker()
            return
        }
        guard let url else { failedID = messageID; return }

        stop()
        if url.isFileURL {
            start(messageID: messageID, file: url)
        } else {
            loadRemote(messageID: messageID, url: url)
        }
    }

    func stop() {
        ticker?.invalidate(); ticker = nil
        player?.stop()
        player = nil
        playingID = nil
        loadedID = nil
        progress = 0
        elapsed = 0
    }

    private func pause() {
        player?.pause()
        ticker?.invalidate(); ticker = nil
        playingID = nil
    }

    private func loadRemote(messageID: UUID, url: URL) {
        let cached = Self.cacheURL(for: url)
        if FileManager.default.fileExists(atPath: cached.path) {
            start(messageID: messageID, file: cached)
            return
        }
        downloads[messageID]?.cancel()
        loadingID = messageID
        downloads[messageID] = Task { [weak self] in
            defer { Task { @MainActor in self?.downloads[messageID] = nil } }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                try data.write(to: cached, options: .atomic)
                guard !Task.isCancelled else { return }
                self?.loadingID = nil
                self?.start(messageID: messageID, file: cached)
            } catch {
                guard !Task.isCancelled else { return }
                self?.loadingID = nil
                self?.failedID = messageID
            }
        }
    }

    private func start(messageID: UUID, file: URL) {
        do {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)

            let p = try AVAudioPlayer(contentsOf: file)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            playingID = messageID
            loadedID = messageID
            progress = 0
            elapsed = 0
            startTicker()
        } catch {
            failedID = messageID
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.elapsed = p.currentTime
                self.progress = min(1, p.currentTime / p.duration)
            }
        }
    }

    /// `Library/Caches/world-audio/<sha-ish>.m4a` — stable per remote URL.
    private static func cacheURL(for remote: URL) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("world-audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = String(remote.absoluteString.hashValue.magnitude, radix: 36)
        return dir.appendingPathComponent("\(name).m4a")
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

// MARK: - Voice note bubble

/// iMessage-style voice note: play/pause, a waveform that fills as it plays, and
/// the running time. The waveform shape is derived from the message id so both
/// sides of the conversation see the same bars.
struct VoiceNoteBubble: View {
    let message: WorldMessage
    let tailed: Bool

    @ObservedObject private var audio = ChatAudioPlayer.shared

    private var isPlaying: Bool { audio.isPlaying(message.id) }
    private var isLoading: Bool { audio.loadingID == message.id }
    private var failed: Bool { audio.failedID == message.id }
    private var tint: Color { message.fromUser ? Color.white : IMColor.label }

    private var bars: [CGFloat] { Self.waveform(seed: message.id) }

    private var progress: Double { audio.progress(for: message.id) }

    private var timeLabel: String {
        if audio.loadedID == message.id {
            let s = Int(audio.elapsed)
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        return message.durationLabel ?? "0:00"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audio.toggle(messageID: message.id, url: message.playableAudioURL)
            } label: {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 32, height: 32)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(tint)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(tint)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause voice message" : "Play voice message")

            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { i, height in
                    let played = Double(i) / Double(bars.count) <= progress
                    Capsule()
                        .fill(tint.opacity(played ? 1 : 0.35))
                        .frame(width: 2.5, height: height)
                }
            }
            .frame(height: 26)
            .animation(.linear(duration: 0.06), value: progress)

            Text(failed ? "Unavailable" : timeLabel)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint.opacity(failed ? 0.6 : 0.9))
                .contentTransition(.numericText())
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            BubbleShape(fromUser: message.fromUser, tailed: tailed)
                .fill(message.fromUser ? IMColor.blue : IMColor.bubbleGray)
        )
        .contentShape(Rectangle())
    }

    /// Deterministic bar heights so a clip looks the same on every device.
    private static func waveform(seed: UUID) -> [CGFloat] {
        var state = UInt64(truncatingIfNeeded: seed.hashValue) | 1
        return (0..<28).map { _ in
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return 6 + CGFloat(state % 20)
        }
    }
}

// MARK: - Hold-to-record

/// Recording lifecycle for the composer's hold-to-talk mic, on top of the shared
/// `AudioRecorderController`. Owns the "slide left to cancel" state so the
/// composer view stays declarative.
@MainActor
final class HoldToRecordModel: ObservableObject {
    @Published var isRecording = false
    @Published var cancelling = false
    /// Horizontal finger travel while holding, ≤ 0 (leftwards).
    @Published var dragX: CGFloat = 0

    let recorder = AudioRecorderController()

    /// Past this much leftward travel, releasing throws the recording away.
    let cancelThreshold: CGFloat = -90
    /// Anything shorter than this was a mis-tap, not a message.
    private let minimumDuration: TimeInterval = 0.6

    private var recorderChanges: AnyCancellable?

    init() {
        // A nested ObservableObject doesn't republish on its own, so the live
        // level meter and running time would never redraw. Forward its changes.
        recorderChanges = recorder.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func begin() {
        guard !isRecording else { return }
        cancelling = false
        dragX = 0
        isRecording = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        recorder.startAfterPermission()
    }

    func update(translation: CGFloat) {
        guard isRecording else { return }
        dragX = min(0, translation)
        let shouldCancel = dragX < cancelThreshold
        if shouldCancel != cancelling {
            cancelling = shouldCancel
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    enum Outcome {
        case recorded(url: URL, label: String)
        /// Released past the cancel threshold — thrown away, no message.
        case cancelled
        /// A tap rather than a hold.
        case tooShort
        /// Microphone access is off.
        case denied
    }

    /// Ends the hold and reports what to do with it.
    func end() -> Outcome {
        guard isRecording else { return .cancelled }
        isRecording = false
        let duration = recorder.elapsed
        let wasCancelling = cancelling
        cancelling = false
        dragX = 0

        if recorder.permissionDenied {
            recorder.cancel()
            return .denied
        }
        if wasCancelling {
            recorder.cancel()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return .cancelled
        }
        if duration < minimumDuration {
            recorder.cancel()
            return .tooShort
        }
        recorder.stop()
        guard let url = recorder.finishedURL else { return .tooShort }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return .recorded(url: url, label: recorder.durationLabel)
    }

    func abort() {
        guard isRecording else { return }
        isRecording = false
        cancelling = false
        dragX = 0
        recorder.cancel()
    }
}

/// The inline recording bar that replaces the text field while the mic is held —
/// live level meter, running time, and the slide-to-cancel hint.
struct RecordingComposerBar: View {
    @ObservedObject var model: HoldToRecordModel

    private var recorder: AudioRecorderController { model.recorder }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(red: 1, green: 0.27, blue: 0.23))
                .frame(width: 9, height: 9)
                .opacity(model.cancelling ? 0.4 : 1)
                .scaleEffect(recorder.isRecording ? 1 : 0.6)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                           value: recorder.isRecording)

            Text(recorder.durationLabel)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(IMColor.label)
                .contentTransition(.numericText())

            liveMeter

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                Text(model.cancelling ? "Release to cancel" : "Slide to cancel")
                    .font(.system(size: 13, weight: model.cancelling ? .semibold : .regular))
            }
            .foregroundStyle(model.cancelling
                             ? Color(red: 1, green: 0.35, blue: 0.3)
                             : IMColor.secondary)
            .offset(x: max(model.dragX * 0.5, -40))
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(height: 42)
        .animation(.ggSnappy, value: model.cancelling)
    }

    /// Rolling level meter — newest sample on the right, like the Voice Memos bar.
    private var liveMeter: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(model.cancelling
                          ? IMColor.secondary.opacity(0.5)
                          : IMColor.blue.opacity(0.85))
                    .frame(width: 2.5, height: max(3, level * 22))
            }
        }
        .frame(height: 24)
        .animation(.linear(duration: 0.08), value: recorder.levels.count)
    }
}
