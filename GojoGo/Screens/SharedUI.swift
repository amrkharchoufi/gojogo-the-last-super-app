import SwiftUI
import UIKit

let tabBarInset: CGFloat = 100

/// Shared empty-content placeholder used across feeds and catalogs.
struct GGEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(GGColor.textTertiary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.onAccent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

/// Instagram-style white heart burst for double-tap / like.
struct HeartBurstOverlay: View {
    var trigger: Int

    @State private var scale: CGFloat = 0.2
    @State private var opacity: Double = 0
    @State private var lastTrigger = 0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 88, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, value in
                guard value != lastTrigger, value > 0 else { return }
                lastTrigger = value
                play()
            }
    }

    private func play() {
        scale = 0.15
        opacity = 0
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            scale = 1.15
            opacity = 1
        }
        withAnimation(.easeOut(duration: 0.22).delay(0.32)) {
            scale = 1.35
            opacity = 0
        }
    }
}

struct PostActions: View {
    @EnvironmentObject var app: AppState
    let post: Post
    var onLiked: (() -> Void)? = nil

    @State private var heartBounce = false

    private var live: Post {
        app.posts.first(where: { $0.id == post.id }) ?? post
    }

    var body: some View {
        HStack(spacing: 16) {
            Button {
                let wasLiked = live.liked
                withAnimation(.ggPop) {
                    app.toggleLike(live.id)
                }
                if !wasLiked {
                    heartBounce = true
                    onLiked?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        heartBounce = false
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: live.liked ? "heart.fill" : "heart")
                        .font(.system(size: 24, weight: .regular))
                        .scaleEffect(heartBounce ? 1.35 : 1)
                        .animation(.ggPop, value: heartBounce)
                    if live.likeCount > 0 {
                        Text(formatCount(live.likeCount))
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundStyle(GGColor.textPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            actionButton(icon: "bubble.right", count: live.commentCount) {
                app.openComments(for: live.id)
            }

            actionButton(icon: "paperplane", count: nil) {}

            Spacer(minLength: 8)

            Button {
                withAnimation(.ggSnappy) {
                    app.toggleBookmark(live.id)
                }
            } label: {
                Image(systemName: live.bookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 44)
    }

    private func actionButton(icon: String, count: Int?, tint: Color = GGColor.textPrimary,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .regular))
                if let count, count > 0 {
                    Text(formatCount(count))
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WatchSegments: View {
    @Binding var selection: WatchSubFeed
    var body: some View {
        HStack(spacing: 0) {
            ForEach(WatchSubFeed.allCases) { seg in
                let active = seg == selection
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.2)) { selection = seg }
                } label: {
                    Text(seg.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? GGColor.onAccent : GGColor.ink(0.55))
                        .frame(minWidth: 58, minHeight: 34)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(active ? GGColor.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        // Non-interactive glass — interactive liquid glass delays / eats taps on device.
        .glassCapsule(interactive: false)
        .contentShape(Capsule())
    }
}

struct TopScrim: View {
    var base: Color = .clear
    var body: some View {
        base
            .frame(height: 96)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}

// MARK: - Hide top chrome while scrolling (UIKit contentOffset)

/// Finds the nearest vertical UIScrollView and observes `contentOffset.y`.
private struct ScrollOffsetReader: UIViewRepresentable {
    var onOffset: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOffset: onOffset)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onOffset = onOffset
        context.coordinator.scheduleAttach(from: uiView)
    }

    final class Coordinator {
        var onOffset: (CGFloat) -> Void
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var attachAttempts = 0

        init(onOffset: @escaping (CGFloat) -> Void) {
            self.onOffset = onOffset
        }

        func scheduleAttach(from view: UIView) {
            if scrollView != nil { return }
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                if let scroll = Self.findVerticalScrollView(from: view) {
                    self.beginObserving(scroll)
                    return
                }
                self.attachAttempts += 1
                if self.attachAttempts < 20 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.scheduleAttach(from: view)
                    }
                }
            }
        }

        private func beginObserving(_ scroll: UIScrollView) {
            guard scrollView !== scroll else { return }
            observation?.invalidate()
            scrollView = scroll
            observation = scroll.observe(\.contentOffset, options: [.new, .initial]) { [weak self] sv, _ in
                let y = sv.contentOffset.y
                DispatchQueue.main.async {
                    self?.onOffset(y)
                }
            }
        }

        /// Walk ancestors and scan nearby subviews for the tallest vertical scroller.
        static func findVerticalScrollView(from view: UIView) -> UIScrollView? {
            var best: UIScrollView?
            var current: UIView? = view
            while let node = current {
                best = betterScroll(best, Self.scan(node))
                current = node.superview
            }
            if let window = view.window {
                best = betterScroll(best, Self.scan(window))
            }
            return best
        }

        private static func scan(_ root: UIView) -> UIScrollView? {
            var best: UIScrollView?
            var stack: [UIView] = [root]
            while let node = stack.popLast() {
                if let scroll = node as? UIScrollView {
                    best = betterScroll(best, scroll)
                }
                stack.append(contentsOf: node.subviews)
            }
            return best
        }

        private static func betterScroll(_ a: UIScrollView?, _ b: UIScrollView?) -> UIScrollView? {
            guard let b else { return a }
            guard let a else { return b }
            let aVertical = a.contentSize.height > a.bounds.height + 8
            let bVertical = b.contentSize.height > b.bounds.height + 8
            if aVertical != bVertical { return bVertical ? b : a }
            // Prefer larger vertical content (main feed over nested horizontal wrappers)
            if b.contentSize.height != a.contentSize.height {
                return b.contentSize.height > a.contentSize.height ? b : a
            }
            return b.bounds.height >= a.bounds.height ? b : a
        }

        deinit {
            observation?.invalidate()
        }
    }
}

/// Drives `hidden` from UIScrollView contentOffset: hide while scrolling down,
/// show on scroll-up or shortly after scrolling stops.
struct ScrollChromeTracker: ViewModifier {
    @Binding var hidden: Bool
    var topRevealThreshold: CGFloat = 8
    var deltaThreshold: CGFloat = 1.5
    var idleRevealNanos: UInt64 = 500_000_000

    func body(content: Content) -> some View {
        // Capture Binding explicitly — escaping UIKit callbacks must write
        // `wrappedValue`, not a copied Bool from `@Binding`.
        let chromeHidden = $hidden
        return content
            .background {
                ScrollOffsetReader { y in
                    ChromeScrollGate.shared.handle(
                        y: y,
                        setHidden: { newValue in
                            guard chromeHidden.wrappedValue != newValue else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                chromeHidden.wrappedValue = newValue
                            }
                        },
                        topRevealThreshold: topRevealThreshold,
                        deltaThreshold: deltaThreshold,
                        idleRevealNanos: idleRevealNanos
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
            .onDisappear {
                ChromeScrollGate.shared.cancelIdle()
            }
    }
}

/// Keeps last offset off the SwiftUI render path so scroll ticks don't thrash the view tree.
@MainActor
private final class ChromeScrollGate {
    static let shared = ChromeScrollGate()

    private var lastY: CGFloat = 0
    private var hasBaseline = false
    private var idleTask: Task<Void, Never>?
    private var suppressUntil: Date = .distantPast

    /// Ignore offset jitter while the tab bar morphs / layout settles.
    func suppress(for seconds: TimeInterval = 0.4) {
        suppressUntil = Date().addingTimeInterval(seconds)
        hasBaseline = false
        cancelIdle()
    }

    func handle(
        y: CGFloat,
        setHidden: @escaping (Bool) -> Void,
        topRevealThreshold: CGFloat,
        deltaThreshold: CGFloat,
        idleRevealNanos: UInt64
    ) {
        if Date() < suppressUntil {
            lastY = y
            hasBaseline = true
            return
        }

        if !hasBaseline {
            lastY = y
            hasBaseline = true
            return
        }

        let delta = y - lastY
        lastY = y

        if y <= topRevealThreshold {
            setHidden(false)
            cancelIdle()
            return
        }

        // Ignore tiny layout adjustments (common when bottom chrome resizes).
        if abs(delta) < 1.0 { return }

        if delta > deltaThreshold {
            setHidden(true)
            scheduleIdleReveal(setHidden: setHidden, nanos: idleRevealNanos)
        } else if delta < -deltaThreshold {
            setHidden(false)
            cancelIdle()
        } else {
            scheduleIdleReveal(setHidden: setHidden, nanos: idleRevealNanos)
        }
    }

    func cancelIdle() {
        idleTask?.cancel()
        idleTask = nil
    }

    private func scheduleIdleReveal(setHidden: @escaping (Bool) -> Void, nanos: UInt64) {
        idleTask?.cancel()
        idleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            setHidden(false)
        }
    }

    func resetBaseline() {
        hasBaseline = false
        lastY = 0
        cancelIdle()
    }
}

extension View {
    /// Attach to a `ScrollView` so floating top chrome can hide with scroll direction.
    func trackScrollChrome(hidden: Binding<Bool>, space: String = "") -> some View {
        modifier(ScrollChromeTracker(hidden: hidden))
            .onAppear { ChromeScrollGate.shared.resetBaseline() }
    }

    /// Slide / fade floating top chrome out of the way.
    func autoHideChrome(_ hidden: Bool) -> some View {
        self
            .offset(y: hidden ? -120 : 0)
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}

/// Call when bottom nav morphs so feed scroll chrome doesn't react to layout jitter.
enum ScrollChromeControl {
    @MainActor static func suppressTabBarJitter() {
        ChromeScrollGate.shared.suppress(for: 0.5)
        FeedViewportGate.shared.suppress(for: 0.5)
    }
}
