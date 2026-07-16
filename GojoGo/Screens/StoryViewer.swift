import SwiftUI
import UIKit

/// Instagram-style story viewer — multi-frame per person, tap + swipe + hold-to-pause.
struct StoryViewer: View {
    @EnvironmentObject var app: AppState

    @State private var segmentProgress: CGFloat = 0
    @State private var isPaused = false
    @State private var dragOffset: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var tick: Timer?
    @State private var generation = 0
    @State private var isDismissing = false

    private let frameDuration: Double = 4.0
    private let tickInterval: Double = 1.0 / 60.0

    private var story: Story? {
        guard let id = app.viewingStory?.id else { return nil }
        return app.stories.first(where: { $0.id == id }) ?? app.viewingStory
    }

    private var frameIndex: Int {
        guard let story else { return 0 }
        return min(max(app.viewingFrameIndex, 0), max(story.frames.count - 1, 0))
    }

    private var frame: StoryFrame? {
        guard let story, story.frames.indices.contains(frameIndex) else { return nil }
        return story.frames[frameIndex]
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Overlay / covers can report 0 — fall back to window inset.
            let topInset = max(geo.safeAreaInsets.top, Self.windowTopInset, 47)
            ZStack {
                // Fixed backdrop — must NOT slide with the dismiss drag,
                // or Home peeks through and feels like a second page.
                Color.black.ignoresSafeArea()

                storyContent(width: w, topInset: topInset)
                    .offset(x: dragOffset, y: max(0, dragY))
                    .scaleEffect(1 - min(0.05, max(0, dragY) / 1600))
            }
            .highPriorityGesture(storyDrag(width: w, height: geo.size.height))
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
        .onAppear { restartSegment() }
        .onChange(of: app.viewingStory?.id) { _, _ in restartSegment() }
        .onChange(of: app.viewingFrameIndex) { _, _ in restartSegment() }
        .onDisappear { stopTick() }
    }

    private static var windowTopInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first?.windows.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.safeAreaInsets.top ?? 0
    }

    private func storyContent(width: CGFloat, topInset: CGFloat) -> some View {
        ZStack {
            if let frame {
                MediaImage(url: frame.imageURL, data: frame.imageData, cornerRadius: 0)
                    .ignoresSafeArea()
                    .id(frame.id)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topInset + 120)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Tap / hold zones
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { retreat() }
                    .frame(width: width * 0.3)

                Color.clear
                    .contentShape(Rectangle())
                    .onLongPressGesture(
                        minimumDuration: 0.12,
                        maximumDistance: 80,
                        pressing: { setPaused($0) },
                        perform: {}
                    )
                    .frame(maxWidth: .infinity)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { advance() }
                    .frame(width: width * 0.3)
            }
            .ignoresSafeArea()
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onLongPressGesture(
                        minimumDuration: 0.18,
                        maximumDistance: 120,
                        pressing: { setPaused($0) },
                        perform: {}
                    )
            }

            VStack(spacing: 12) {
                progressBars(width: max(width - 28, 0))
                    .padding(.horizontal, 14)

                header
                    .padding(.horizontal, 14)

                if isPaused {
                    Text("Paused")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassCapsule(interactive: false)
                        .transition(.opacity.combined(with: .scale(0.95)))
                }

                Spacer()
            }
            .padding(.top, topInset + 6)
            .animation(.easeOut(duration: 0.15), value: isPaused)
        }
    }

    // MARK: Progress bars — only the active segment animates

    private func progressBars(width: CGFloat) -> some View {
        let count = max(story?.frames.count ?? 1, 1)
        let spacing: CGFloat = 4
        let barW = (width - spacing * CGFloat(count - 1)) / CGFloat(count)

        return HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.28))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: barGeo.size.width * fillAmount(for: i))
                    }
                }
                .frame(width: barW, height: 3)
            }
        }
        .transaction { $0.animation = nil }
    }

    private func fillAmount(for index: Int) -> CGFloat {
        if index < frameIndex { return 1 }
        if index > frameIndex { return 0 }
        return min(max(segmentProgress, 0), 1)
    }

    private var header: some View {
        HStack(spacing: 10) {
            UserAvatar(
                size: 34,
                letter: story?.letter ?? "·",
                ring: true,
                imageURL: story?.isYou == true ? app.user.avatarURL : story?.imageURL,
                imageData: story?.imageData
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))

            Text(story?.name ?? "")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 1)

            Spacer()

            Button {
                dismissViewer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.35)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            }
        }
    }

    // MARK: Gestures

    private func storyDrag(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !isDismissing else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if !isPaused { setPaused(true) }

                if abs(dy) > abs(dx) * 1.05 {
                    // Vertical — swipe down to dismiss (content only)
                    dragY = max(0, dy)
                    dragOffset = 0
                } else {
                    dragOffset = dx * 0.9
                    dragY = 0
                }
            }
            .onEnded { value in
                guard !isDismissing else { return }
                let dx = value.predictedEndTranslation.width
                let dy = value.predictedEndTranslation.height
                let hThreshold = width * 0.22
                let vThreshold: CGFloat = 110

                if abs(value.translation.height) > abs(value.translation.width),
                   max(value.translation.height, dy) > vThreshold {
                    // Instant close — no second-page slide/fight with presentation.
                    dismissViewer()
                    return
                }

                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    if dx < -hThreshold {
                        dragOffset = -width
                    } else if dx > hThreshold {
                        dragOffset = width
                    } else {
                        dragOffset = 0
                        dragY = 0
                    }
                }

                if dx < -hThreshold {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        dragOffset = 0
                        dragY = 0
                        app.jumpToAdjacentAuthor(forward: true)
                        setPaused(false)
                    }
                } else if dx > hThreshold {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        dragOffset = 0
                        dragY = 0
                        app.jumpToAdjacentAuthor(forward: false)
                        setPaused(false)
                    }
                } else {
                    setPaused(false)
                }
            }
    }

    private func dismissViewer(animatedFrom height: CGFloat? = nil) {
        guard !isDismissing else { return }
        isDismissing = true
        stopTick()
        _ = height
        dragY = 0
        dragOffset = 0
        app.closeStoryViewer()
        isDismissing = false
    }

    private func advance() {
        guard !isDismissing else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        stopTick()
        _ = app.advanceStory()
    }

    private func retreat() {
        guard !isDismissing else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        stopTick()
        _ = app.retreatStory()
    }

    private func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        if paused {
            stopTick(keepProgress: true)
        } else {
            startTick()
        }
    }

    // MARK: Timer-driven progress

    private func restartSegment() {
        guard let story, let frame else { return }
        app.markFrameSeen(storyID: story.id, frameID: frame.id)
        generation += 1
        segmentProgress = 0
        isPaused = false
        startTick()
    }

    private func startTick() {
        stopTick(keepProgress: true)
        let gen = generation
        let step = CGFloat(tickInterval / frameDuration)
        let timer = Timer(timeInterval: tickInterval, repeats: true) { timer in
            DispatchQueue.main.async {
                guard gen == self.generation, !self.isPaused, !self.isDismissing else { return }
                self.segmentProgress = min(1, self.segmentProgress + step)
                if self.segmentProgress >= 1 {
                    timer.invalidate()
                    if self.tick === timer { self.tick = nil }
                    _ = self.app.advanceStory()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func stopTick(keepProgress: Bool = false) {
        tick?.invalidate()
        tick = nil
        _ = keepProgress
    }
}
