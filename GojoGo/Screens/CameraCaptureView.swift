import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

/// The real camera, for the chat drawer's Camera row (which used to open the
/// photo library). Photos come back as JPEG data; videos come back as a poster
/// frame plus a duration label, matching what the composer tray stages for a
/// picked video.
struct CameraCaptureView: UIViewControllerRepresentable {

    enum Capture {
        case photo(Data)
        case video(poster: Data, durationLabel: String, url: URL)
    }

    var onCapture: (Capture) -> Void
    var onCancel: () -> Void

    /// False in the Simulator and on devices with no usable camera — callers
    /// fall back to the photo library rather than presenting an empty controller.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 60
        picker.cameraDevice = .rear
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Capture) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (Capture) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let movie = info[.mediaURL] as? URL {
                Task { [onCapture, onCancel] in
                    if let capture = await Self.videoCapture(from: movie) {
                        onCapture(capture)
                    } else {
                        onCancel()
                    }
                }
                return
            }
            guard let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage,
                  let data = Self.downscaled(image).jpegData(compressionQuality: 0.85) else {
                onCancel()
                return
            }
            onCapture(.photo(data))
        }

        private static func videoCapture(from url: URL) async -> Capture? {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 900, height: 900)
            guard let cg = try? generator.copyCGImage(
                at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil),
                  let poster = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8) else {
                return nil
            }
            let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            let label = String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
            return .video(poster: poster, durationLabel: label, url: url)
        }

        private static func downscaled(_ image: UIImage, maxDimension: CGFloat = 1600) -> UIImage {
            let longest = max(image.size.width, image.size.height)
            guard longest > maxDimension else { return image }
            let scale = maxDimension / longest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            return UIGraphicsImageRenderer(size: size).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }
}
