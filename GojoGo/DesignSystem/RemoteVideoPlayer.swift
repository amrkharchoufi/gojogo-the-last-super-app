import SwiftUI
import AVKit
import AVFoundation
import UIKit

/// Full-bleed AVPlayer for long-form / watching surfaces.
struct RemoteVideoPlayer: View {
    let urlString: String?
    var autoplay: Bool = true
    /// Optional poster while the stream buffers.
    var posterURL: String? = nil
    var posterData: Data? = nil

    @State private var player: AVPlayer?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var failed = false
    @State private var isReady = false

    var body: some View {
        ZStack {
            Color.black

            if !isReady || failed {
                MediaImage(url: posterURL, data: posterData, cornerRadius: 0)
                    .opacity(failed ? 0.45 : 1)
            }

            if let player, !failed {
                VideoPlayer(player: player)
            }

            if !isReady && !failed && urlString != nil {
                ProgressView().tint(.white)
            }

            if failed {
                VStack(spacing: 10) {
                    Image(systemName: "play.slash.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Couldn't load video")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Button("Retry") { setup(force: true) }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                }
            }
        }
        .onAppear {
            activateAudioSession()
            setup()
        }
        .onDisappear { teardown() }
        .onChange(of: urlString) { _, _ in
            teardown()
            setup()
        }
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setup(force: Bool = false) {
        if force {
            teardown()
        }
        failed = false
        isReady = false
        let raw = VideoLibrary.resolve(urlString) ?? SampleData.repairedVideoURL(urlString)
        guard let s = raw, let url = URL(string: s),
              !(url.isFileURL && !FileManager.default.fileExists(atPath: url.path)) else {
            failed = urlString != nil
            return
        }

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        statusObserver = item.observe(\.status, options: [.new, .initial]) { item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    isReady = true
                    failed = false
                    if autoplay { p.play() }
                case .failed:
                    isReady = false
                    failed = true
                default:
                    break
                }
            }
        }
        player = p
    }

    private func teardown() {
        statusObserver?.invalidate()
        statusObserver = nil
        player?.pause()
        player = nil
        isReady = false
    }
}

// MARK: - Shared looping players (survive SwiftUI remounts)

/// Keeps one `AVPlayer` per URL so mute / pause / TabView rebuilds never restart or stack copies.
@MainActor
enum ShortVideoPlayerCache {
    private final class Entry {
        let player: AVPlayer
        var endObserver: NSObjectProtocol?
        var wantsPlay = false
        /// Which ShortVideoPlayer instance currently owns playback for this URL.
        var activeClientID: UUID?
        weak var attachedLayer: AVPlayerLayer?

        init(player: AVPlayer) {
            self.player = player
        }
    }

    private static var entries: [String: Entry] = [:]

    static func player(for urlString: String) -> AVPlayer? {
        entry(for: urlString)?.player
    }

    static func attach(urlString: String, to layer: AVPlayerLayer) {
        guard let entry = entry(for: urlString) else {
            layer.player = nil
            return
        }
        // One layer at a time — prevents duplicate video surfaces.
        if let old = entry.attachedLayer, old !== layer {
            old.player = nil
        }
        entry.attachedLayer = layer
        layer.player = entry.player
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = UIColor.black.cgColor
    }

    static func detach(clientID: UUID, urlString: String, layer: AVPlayerLayer) {
        guard let entry = entries[urlString] else { return }
        if entry.attachedLayer === layer {
            layer.player = nil
            entry.attachedLayer = nil
        }
        // Stop if this client was driving playback (e.g. scrolled off-screen).
        if entry.activeClientID == clientID || entry.activeClientID == nil {
            entry.activeClientID = nil
            entry.wantsPlay = false
            entry.player.pause()
        }
    }

    /// Play / pause only — never seek, never recreate.
    /// `clientID` ensures an off-screen card can't keep a shared clip playing.
    static func setActive(clientID: UUID, urlString: String, active: Bool) {
        guard let entry = entry(for: urlString) else { return }
        if active {
            entry.activeClientID = clientID
            entry.wantsPlay = true
            if entry.player.rate == 0 {
                entry.player.play()
            }
        } else if entry.activeClientID == nil || entry.activeClientID == clientID {
            entry.activeClientID = nil
            entry.wantsPlay = false
            entry.player.pause()
        }
    }

    static func setMuted(clientID: UUID, urlString: String, muted: Bool) {
        // Apply to this clip; feed mute is global so also sync every cached player.
        entries[urlString]?.player.isMuted = muted
    }

    /// Feed-wide mute — every in-memory clip follows the same preference.
    static func setAllMuted(_ muted: Bool) {
        for entry in entries.values {
            entry.player.isMuted = muted
        }
    }

    private static func entry(for urlString: String) -> Entry? {
        if let existing = entries[urlString] { return existing }

        activateAudioSession()
        let raw = VideoLibrary.resolve(urlString) ?? SampleData.repairedVideoURL(urlString) ?? urlString
        guard let url = resolveURL(raw) else { return nil }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        let entry = Entry(player: player)

        entry.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak entry] _ in
            guard let entry else { return }
            entry.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                guard finished, entry.wantsPlay else { return }
                entry.player.play()
            }
        }

        entries[urlString] = entry
        return entry
    }

    private static func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private static func resolveURL(_ raw: String) -> URL? {
        let resolved = VideoLibrary.resolve(raw) ?? raw
        if let url = URL(string: resolved), url.scheme != nil {
            if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) {
                return nil
            }
            return url
        }
        let file = URL(fileURLWithPath: resolved)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
}

/// Control-free looping player for Shorts / feed video.
struct ShortVideoPlayer: UIViewRepresentable {
    let urlString: String
    var isActive: Bool = true
    var isMuted: Bool = false
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeCoordinator() -> Coordinator {
        Coordinator(urlString: urlString)
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.backgroundColor = .black
        view.playerLayer.backgroundColor = UIColor.black.cgColor
        view.playerLayer.videoGravity = videoGravity
        context.coordinator.urlString = urlString
        ShortVideoPlayerCache.attach(urlString: urlString, to: view.playerLayer)
        view.playerLayer.videoGravity = videoGravity
        ShortVideoPlayerCache.setActive(clientID: context.coordinator.clientID, urlString: urlString, active: isActive)
        ShortVideoPlayerCache.setMuted(clientID: context.coordinator.clientID, urlString: urlString, muted: isMuted)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.backgroundColor = .black
        uiView.playerLayer.videoGravity = videoGravity
        if context.coordinator.urlString != urlString {
            ShortVideoPlayerCache.detach(
                clientID: context.coordinator.clientID,
                urlString: context.coordinator.urlString,
                layer: uiView.playerLayer
            )
            context.coordinator.urlString = urlString
            ShortVideoPlayerCache.attach(urlString: urlString, to: uiView.playerLayer)
            uiView.playerLayer.videoGravity = videoGravity
        } else if uiView.playerLayer.player == nil {
            ShortVideoPlayerCache.attach(urlString: urlString, to: uiView.playerLayer)
            uiView.playerLayer.videoGravity = videoGravity
        }
        ShortVideoPlayerCache.setActive(clientID: context.coordinator.clientID, urlString: urlString, active: isActive)
        ShortVideoPlayerCache.setMuted(clientID: context.coordinator.clientID, urlString: urlString, muted: isMuted)
    }

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: Coordinator) {
        ShortVideoPlayerCache.detach(
            clientID: coordinator.clientID,
            urlString: coordinator.urlString,
            layer: uiView.playerLayer
        )
    }

    final class Coordinator {
        let clientID = UUID()
        var urlString: String
        init(urlString: String) { self.urlString = urlString }
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
