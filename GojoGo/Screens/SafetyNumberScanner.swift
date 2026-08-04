import AVFoundation
import CoreImage.CIFilterBuiltins
import LibSignalClient
import SwiftUI
import UIKit

// MARK: - QR safety-number verification (E2EE Phase E)
//
// The same fingerprint has two forms. The 60 digits are the one that always
// works — a phone call, a bad camera, someone who won't scan — and they shipped
// first for exactly that reason. This is the other one: `ScannableFingerprint`,
// compared by libsignal rather than by two people reading aloud.
//
// It matters more than convenience. Sixty digits compared by eye is a task
// people abandon halfway and then declare done, and a half-compared safety
// number is worse than none because it produces false confidence. A scan is
// all-or-nothing and takes a second.
//
// The comparison itself is libsignal's `compare(againstEncoding:)`, never a
// string equality on what the camera read: the encoding carries a version, and
// a mismatched version has to fail loudly instead of quietly comparing bytes
// that mean different things.

struct SafetyNumberScanner: View {
    let peer: UUID
    let displayName: String
    var onVerified: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var result: Outcome?
    @State private var cameraDenied = false

    enum Outcome: Equatable {
        case match
        case mismatch
        /// The code scanned cleanly but isn't one of ours.
        case notASafetyNumber
    }

    private var mine: ScannableFingerprint? {
        WorldSafetyNumber.fingerprint(with: peer)?.scannable
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let mine, let qr = Self.qrImage(from: mine.encoding) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white))
                    .padding(.top, 8)

                Text("Have \(displayName) scan this, or scan theirs below.")
                    .font(.system(size: 13))
                    .foregroundStyle(IMColor.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
            }

            ZStack {
                if cameraDenied {
                    Text("Camera access is off, so scanning isn't available. "
                         + "You can still compare the digits by reading them aloud.")
                        .font(.system(size: 13))
                        .foregroundStyle(IMColor.secondary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                } else {
                    QRCameraView(onCode: handle)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                if let result { verdict(result) }
            }
            .frame(height: 260)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .background(IMColor.bg.ignoresSafeArea())
        .task {
            // Asked here rather than at launch: the permission prompt makes
            // sense standing in front of somebody's phone, and nowhere else.
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            cameraDenied = AVCaptureDevice.authorizationStatus(for: .video) != .authorized
        }
    }

    private var header: some View {
        HStack {
            Button("Close") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(IMColor.blue)
            Spacer()
            Text("Verify \(displayName)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(IMColor.label)
            Spacer()
            Button("Close") { dismiss() }.opacity(0).disabled(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func verdict(_ outcome: Outcome) -> some View {
        VStack(spacing: 10) {
            Image(systemName: outcome == .match ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(outcome == .match ? .green : Color(dark: "FF453A", light: "FF3B30"))
            Text(message(for: outcome))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(IMColor.label)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if outcome != .match {
                Button("Try again") { result = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IMColor.blue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func message(for outcome: Outcome) -> String {
        switch outcome {
        case .match:
            return "Verified. This conversation is between the two of you."
        case .mismatch:
            // Said without hedging. A mismatch is either the wrong contact's
            // code or an intercepted conversation, and both deserve a stop.
            return "These don't match. Either that's a different conversation's "
                + "code, or someone is intercepting this one. Don't send anything "
                + "sensitive until it matches."
        case .notASafetyNumber:
            return "That isn't a GojoGo safety number."
        }
    }

    private func handle(_ payload: Data) {
        guard result == nil, let mine else { return }
        do {
            if try mine.compare(againstEncoding: payload) {
                WorldVerificationStore.shared.markVerified(peer)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                result = .match
                onVerified()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                result = .mismatch
            }
        } catch {
            // A code that isn't a fingerprint at all, or one from an
            // incompatible version. Not a mismatch — saying "these don't match"
            // about a random QR code would be a false alarm.
            result = .notASafetyNumber
        }
    }

    static func qrImage(from data: Data) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        // High correction: this gets scanned off a screen at an angle, in
        // whatever light the two people happen to be standing in.
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Camera

/// Minimal QR reader. Hands up raw bytes rather than a string: a fingerprint
/// encoding is binary, and round-tripping it through UTF-8 would corrupt it.
private struct QRCameraView: UIViewRepresentable {
    let onCode: (Data) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.start(delegate: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        uiView.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (Data) -> Void
        init(onCode: @escaping (Data) -> Void) { self.onCode = onCode }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let object = objects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let descriptor = object.descriptor as? CIQRCodeDescriptor
            else { return }
            // `errorCorrectedPayload` is the raw bytes; `stringValue` would have
            // already lost anything that isn't valid text.
            let payload = descriptor.errorCorrectedPayload
            // The first byte pair is QR mode/length framing; libsignal wants the
            // bytes we encoded, which CoreImage returns with a 2-byte header for
            // byte-mode payloads.
            let bytes = payload.count > 2 ? payload.dropFirst(2) : payload[...]
            DispatchQueue.main.async { self.onCode(Data(bytes)) }
        }
    }

    final class PreviewView: UIView {
        private let session = AVCaptureSession()

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        private var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        func start(delegate: AVCaptureMetadataOutputObjectsDelegate) {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: .main)
            output.metadataObjectTypes = [.qr]
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            // Starting the session blocks; off the main thread or the sheet
            // animates in stuttering.
            Task.detached { [session] in session.startRunning() }
        }

        func stop() {
            Task.detached { [session] in session.stopRunning() }
        }
    }
}
