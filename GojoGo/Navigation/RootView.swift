import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch app.activeTab {
                case .home:      HomeView()
                case .watch:     WatchView()
                case .madeleine: MadeleineHomeView()
                case .travel:    GojoTravelView()
                case .economy:   EconomyView()
                case .search:    SearchView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Soft scrim when composing — Apple blur feel
            if app.isComposing {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.55)
                    .background(Color.black.opacity(0.25))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { app.closeComposer() }
                    .transition(.opacity)
                    .zIndex(1)
            }

            GGTabBar(ghosted: app.isImmersive)
                .padding(.bottom, app.isComposing ? 2 : 0)
                .safeAreaPadding(.bottom, 0)
                .zIndex(2)

            // Story overlay — media goes edge-to-edge inside; chrome uses safe area.
            if app.storyOverlayActive, app.viewingStory != nil {
                StoryViewer()
                    .environmentObject(app)
                    .transition(.opacity)
                    .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.18), value: app.storyOverlayActive)
        // Don't ignore keyboard — composer must sit above it when open.
        .animation(.easeOut(duration: 0.25), value: app.isComposing)
        .sheet(isPresented: Binding(
            get: { app.showProfile },
            set: { if !$0 { app.closeProfile() } }
        )) {
            ProfileView()
                .environmentObject(app)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.black)
        }
        .sheet(isPresented: $app.showStoriesBrowser) {
            StoriesBrowserView()
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { app.commentingPostID != nil },
            set: { if !$0 { app.closeComments() } }
        )) {
            CommentsSheet().environmentObject(app)
        }
        .fullScreenCover(isPresented: $app.showWatching) {
            WatchingMadeleineView().environmentObject(app)
        }
        .sheet(isPresented: Binding(
            get: { app.editingAttachmentID != nil },
            set: { if !$0 { app.closeMediaEditor() } }
        )) {
            if let id = app.editingAttachmentID {
                MediaEditSheet(attachmentID: id)
                    .environmentObject(app)
            }
        }
        .sheet(isPresented: $app.showSellSheet) {
            SellListingSheet()
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { app.messagingProduct != nil },
            set: { if !$0 { app.closeSellerChat() } }
        )) {
            SellerChatView()
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: Binding(
            get: { app.browsingProduct != nil },
            set: { if !$0 { app.closeProduct() } }
        )) {
            if let id = app.browsingProduct?.id {
                ProductDetailView(productID: id)
                    .environmentObject(app)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { app.selectedTVShow != nil },
            set: { if !$0 { app.closeTVShow() } }
        )) {
            if let id = app.selectedTVShow?.id {
                TVShowDetailView(showID: id)
                    .environmentObject(app)
            }
        }
        .onChange(of: app.showCompose) { _, open in
            if open {
                app.showCompose = false
                app.openComposer()
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch app.phase {
            case .welcome:
                WelcomeView().transition(.opacity)
            case .email:
                EmailSignUpView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .onboarding:
                OnboardingFlow().transition(.opacity)
            case .app:
                MainAppView().transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                app.persistSession()
            }
        }
    }
}

extension AppState {
    var isImmersive: Bool {
        activeTab == .watch && watchSubFeed == .shorts
    }
}

extension Story: Hashable {
    static func == (lhs: Story, rhs: Story) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
