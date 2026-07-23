import SwiftUI
import AVFoundation
import UIKit

@MainActor
final class AudioRecorderController: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var level: CGFloat = 0
    /// Rolling window of recent levels, oldest first — drives the live meter in
    /// the chat composer's hold-to-record bar.
    @Published var levels: [CGFloat] = []
    @Published var finishedURL: URL?
    @Published var permissionDenied = false
    @Published var errorMessage: String?

    /// How many samples the rolling meter keeps (~2.7s at the 0.08s tick).
    private let levelWindow = 34

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var meterTimer: Timer?

    var durationLabel: String {
        let s = Int(elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func prepare() {
        Task { @MainActor in
            let ok = await AVAudioApplication.requestRecordPermission()
            if !ok {
                permissionDenied = true
                return
            }
            configureSession()
        }
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Permission-then-record in one call, for hold-to-talk where there's no
    /// separate "prepare" moment. A denial leaves `permissionDenied` set so the
    /// caller can explain rather than record silence.
    func startAfterPermission() {
        Task { @MainActor in
            guard await AVAudioApplication.requestRecordPermission() else {
                permissionDenied = true
                return
            }
            permissionDenied = false
            configureSession()
            start()
        }
    }

    func start() {
        finishedURL = nil
        elapsed = 0
        level = 0
        levels = []
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gojogo-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            recorder?.prepareToRecord()
            recorder?.record()
            isRecording = true
            startTimers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isRecording else { return }
        recorder?.stop()
        finishedURL = recorder?.url
        isRecording = false
        stopTimers()
        level = 0
    }

    func cancel() {
        stopTimers()
        recorder?.stop()
        if let url = recorder?.url {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        finishedURL = nil
        isRecording = false
        elapsed = 0
        level = 0
        levels = []
    }

    private func startTimers() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let r = self.recorder, r.isRecording else { return }
                self.elapsed = r.currentTime
            }
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let r = self.recorder, r.isRecording else { return }
                r.updateMeters()
                let power = r.averagePower(forChannel: 0) // -160...0
                let normalized = max(0, min(1, CGFloat((power + 50) / 50)))
                self.level = normalized
                self.levels.append(normalized)
                if self.levels.count > self.levelWindow { self.levels.removeFirst() }
            }
        }
    }

    private func stopTimers() {
        timer?.invalidate(); timer = nil
        meterTimer?.invalidate(); meterTimer = nil
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // URL already captured in stop()
    }
}

struct AudioRecorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorderController()
    var onSave: (URL, String, Data) -> Void

    var body: some View {
        VStack(spacing: 28) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text(recorder.isRecording ? "Recording…" : (recorder.finishedURL == nil ? "Record audio" : "Ready to attach"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Text(recorder.durationLabel)
                .font(.system(size: 44, weight: .light).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            // Level meter
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { i in
                    let threshold = CGFloat(i) / 24
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(recorder.level > threshold
                              ? Color.white
                              : Color.white.opacity(0.12))
                        .frame(width: 6, height: 12 + CGFloat(i % 6) * 4)
                }
            }
            .frame(height: 40)
            .animation(.easeOut(duration: 0.08), value: recorder.level)

            if recorder.permissionDenied {
                Text("Microphone access is off. Enable it in Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let err = recorder.errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 28) {
                Button {
                    recorder.cancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button {
                    if recorder.isRecording {
                        recorder.stop()
                    } else if recorder.finishedURL == nil {
                        recorder.start()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 3)
                            .frame(width: 78, height: 78)
                        RoundedRectangle(cornerRadius: recorder.isRecording ? 8 : 34, style: .continuous)
                            .fill(Color.red)
                            .frame(width: recorder.isRecording ? 28 : 58,
                                   height: recorder.isRecording ? 28 : 58)
                    }
                }
                .buttonStyle(SoftPressStyle())
                .disabled(recorder.permissionDenied)

                Button {
                    guard let url = recorder.finishedURL else { return }
                    let poster = waveformPoster()
                    onSave(url, recorder.durationLabel, poster)
                    dismiss()
                } label: {
                    Text("Use")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(recorder.finishedURL != nil
                                         ? Color.white
                                         : Color.white.opacity(0.25))
                }
                .disabled(recorder.finishedURL == nil)
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .ignoresSafeArea()
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
        .onAppear { recorder.prepare() }
        .onDisappear { if recorder.isRecording { recorder.cancel() } }
    }

    private func waveformPoster() -> Data {
        let view = ZStack {
            Color(red: 0.12, green: 0.14, blue: 0.18)
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Color.white)
        }
        .frame(width: 300, height: 300)
        let r = ImageRenderer(content: view)
        r.scale = 2
        return r.uiImage?.jpegData(compressionQuality: 0.85) ?? Data()
    }
}
