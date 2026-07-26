import SwiftUI
import UIKit

/// App-wide keyboard helpers. Tap-outside is installed once on the key window
/// (doesn't cancel button taps); scroll + a Done toolbar cover the rest.
enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Makes the keyboard dismissible for this subtree: interactive scroll
    /// dismiss, and a Done button on the system keyboard toolbar (covers
    /// number pads that have no Return key).
    func dismissesKeyboard() -> some View {
        modifier(DismissesKeyboardModifier())
    }
}

private struct DismissesKeyboardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { Keyboard.dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .background(KeyboardDismissInstallerBridge())
    }
}

/// Hooks the window-level tap recognizer into the SwiftUI lifecycle.
private struct KeyboardDismissInstallerBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { KeyboardDismissInstaller.shared.installIfNeeded() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        KeyboardDismissInstaller.shared.installIfNeeded()
    }
}

/// Tap anywhere outside a text field/view to resign first responder.
/// `cancelsTouchesInView = false` so buttons (Send, Post, etc.) still fire.
final class KeyboardDismissInstaller: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissInstaller()

    private weak var window: UIWindow?
    private var recognizer: UITapGestureRecognizer?

    func installIfNeeded() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let key = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        else { return }

        if window === key, recognizer != nil { return }

        if let old = recognizer, let oldWindow = window {
            oldWindow.removeGestureRecognizer(old)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.requiresExclusiveTouchType = false
        tap.delegate = self
        key.addGestureRecognizer(tap)
        recognizer = tap
        window = key
    }

    @objc private func handleTap() {
        Keyboard.dismiss()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
