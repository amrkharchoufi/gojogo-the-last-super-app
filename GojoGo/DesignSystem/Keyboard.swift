import SwiftUI
import UIKit

/// App-wide keyboard helpers. Tap-outside is installed once on the key window
/// (doesn't cancel button taps); interactive scroll/swipe dismisses the rest.
enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Makes the keyboard dismissible for this subtree via interactive scroll
    /// (swipe down) and tap-outside. No keyboard accessory toolbar.
    func dismissesKeyboard() -> some View {
        modifier(DismissesKeyboardModifier())
    }

    /// Carves this view's rectangle out of the window-wide tap-to-dismiss.
    ///
    /// "Tap anywhere that isn't a text field and the keyboard goes away" is the
    /// right rule for a form, and the wrong one for a chat composer: the Send
    /// button is not a text field, so tapping it dismissed the keyboard on the
    /// way to sending — the message went out and the keyboard went down with
    /// it, every time. The recognizer keeps `cancelsTouchesInView = false`, so
    /// the button still fired; both things happened, which is why it read as a
    /// dismiss rather than as a dead button.
    ///
    /// Frames rather than the view hierarchy, deliberately: the marker goes in
    /// as a `.background`, which makes it a sibling of the controls and not an
    /// ancestor of them, so walking up from `touch.view` would never find it.
    func keepsKeyboardOnTap() -> some View {
        background(KeyboardSafeZoneBridge())
    }
}

/// The `.keepsKeyboardOnTap()` marker: an empty, untouchable view that exists
/// only so its frame can be asked for.
private struct KeyboardSafeZoneBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { KeyboardSafeZoneView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class KeyboardSafeZoneView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Registered while on screen and dropped the moment it isn't, so a closed
    /// thread doesn't leave a hole in the tap-to-dismiss behind it.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            KeyboardDismissInstaller.shared.forgetSafeZone(self)
        } else {
            KeyboardDismissInstaller.shared.rememberSafeZone(self)
        }
    }
}

private struct DismissesKeyboardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
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
    /// Rectangles that opted out of tap-to-dismiss (see `keepsKeyboardOnTap()`).
    /// Weak, so a view that goes away takes its exemption with it.
    private let safeZones = NSHashTable<UIView>.weakObjects()

    func rememberSafeZone(_ view: UIView) { safeZones.add(view) }
    func forgetSafeZone(_ view: UIView) { safeZones.remove(view) }

    private func isInSafeZone(_ touch: UITouch) -> Bool {
        guard let host = touch.window else { return false }
        let point = touch.location(in: host)
        for zone in safeZones.allObjects where zone.window === host {
            if zone.convert(zone.bounds, to: host).contains(point) { return true }
        }
        return false
    }

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
        if isInSafeZone(touch) { return false }
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
