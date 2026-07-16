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

/// Control-free looping player for Shorts / feed video. Plays only while `isActive`.
struct ShortVideoPlayer: View {
    let urlString: String
    var isActive: Bool = true
    var isMuted: Bool = false

    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?
    /// Shared with the end-of-item observer so looping respects pause / inactive.
    @State private var playGate = PlayGate()

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player, videoGravity: .resizeAspectFill)
            } else {
                // Transparent so feed / shorts poster stays visible when file is missing.
                Color.clear
            }
        }
        .onAppear {
            playGate.isActive = isActive
            activateAudioSession()
            ensurePlayer()
        }
        .onDisappear { teardown() }
        .onChange(of: urlString) { _, _ in
            teardown()
            ensurePlayer()
        }
        .onChange(of: isActive) { _, active in
            playGate.isActive = active
            guard let player else { return }
            if active {
                player.play()
            } else {
                player.pause()
            }
        }
        .onChange(of: isMuted) { _, muted in
            player?.isMuted = muted
        }
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func ensurePlayer() {
        playGate.isActive = isActive
        guard player == nil else {
            player?.isMuted = isMuted
            if isActive { player?.play() } else { player?.pause() }
            return
        }
        let raw = VideoLibrary.resolve(urlString) ?? SampleData.repairedVideoURL(urlString) ?? urlString
        guard let url = Self.resolveURL(raw) else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = isMuted
        let gate = playGate
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero)
            if gate.isActive { p?.play() }
        }
        player = p
        if isActive { p.play() }
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

    private func teardown() {
        playGate.isActive = false
        player?.pause()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player = nil
    }
}

private final class PlayGate {
    var isActive = true
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
