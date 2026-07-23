import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var app: AppState

    /// Identity of the visible section — drives the crossfade between tabs / My World.
    private var surfaceID: AnyHashable {
        app.navMode == .myWorld ? AnyHashable("myWorld") : AnyHashable(app.activeTab)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if app.navMode == .myWorld {
                    // First run in My World: WhatsApp-style setup (phone + World
                    // profile) before the messages list — design stays GojoGo.
                    if app.needsWorldSetup {
                        WorldSetupView()
                    } else {
                        MyWorldView()
                    }
                } else {
                    switch app.activeTab {
                    case .home:      HomeView()
                    case .watch:     WatchView()
                    case .madeleine: MadeleineHomeView()
                    case .travel:    GojoTravelView()
                    case .delivery:  GojoDeliveryView()
                    case .economy:   EconomyView()
                    case .search:    SearchView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Crossfade between sections. Keyed identity + a scoped `.ggTab` animation
            // keeps the transition on the section swap only — it can't leak into a
            // section's own ScrollView offset (that only ever changes on activeTab/navMode,
            // and each incoming section is a fresh view). navBarExpanded is deliberately
            // absent from the key so expanding the dock never re-animates the content.
            .id(surfaceID)
            .transition(.opacity)
            .animation(.ggTab, value: surfaceID)

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

            if !app.isWorldImmersive {
                // Full-width shield so bottom taps never hit the feed ScrollView.
                Color.clear
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)

                GGTabBar(ghosted: app.isImmersive)
                    .padding(.bottom, app.isComposing ? 2 : 0)
                    .safeAreaPadding(.bottom, 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }

            // Story overlay — media goes edge-to-edge inside; chrome uses safe area.
            if app.storyOverlayActive, app.viewingStory != nil {
                StoryViewer()
                    .environmentObject(app)
                    .transition(.opacity)
                    .zIndex(50)
            }
        }
        .animation(.ggOverlay, value: app.storyOverlayActive)
        // Don't ignore keyboard — composer must sit above it when open.
        .animation(.ggOverlay, value: app.isComposing)
        .animation(.ggGentle, value: app.isWorldImmersive)
        .sheet(isPresented: Binding(
            get: { app.showProfile },
            set: { if !$0 { app.closeProfile() } }
        )) {
            ProfileView()
                .environmentObject(app)
                .presentationDragIndicator(.visible)
                .presentationBackground(GGColor.sheetBG)
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
        .sheet(isPresented: Binding(
            get: { app.showActivity },
            set: { if !$0 { app.closeActivity() } }
        )) {
            ActivityView().environmentObject(app)
        }
        .sheet(isPresented: Binding(
            get: { app.viewingPostID != nil && !app.showProfile },
            set: { if !$0 { app.closePostViewer() } }
        )) {
            PostViewerSheet().environmentObject(app)
        }
        .fullScreenCover(isPresented: Binding(
            get: { app.partnerOnboardingRole != nil },
            set: { if !$0 { app.cancelPartnerOnboarding() } }
        )) {
            PartnerOnboardingView().environmentObject(app)
        }
        .fullScreenCover(isPresented: Binding(
            get: { app.partnerDashboardRole != nil },
            set: { if !$0 { app.closePartnerDashboard() } }
        )) {
            PartnerDashboardView().environmentObject(app)
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
        navMode == .collections && activeTab == .watch && watchSubFeed == .shorts
    }
}

extension Story: Hashable {
    static func == (lhs: Story, rhs: Story) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
