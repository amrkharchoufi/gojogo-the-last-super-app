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

            // Story notices ride above the viewer — a failed post or a sent
            // reply has to be readable while the story is still on screen.
            if let notice = app.storyNotice {
                Text(notice)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassCapsule(tint: Color.black.opacity(0.55))
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 66)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { app.dismissStoryNotice() }
                    .zIndex(70)
            }

            // Profile is a page, not a drawer: it pushes in from the trailing
            // edge over the whole surface (dock included) rather than sliding
            // up as a modal card. Hosted here for the same reason the story
            // viewer is — a sheet couldn't cover the tab bar, and a card with a
            // grab handle read as a temporary peek at something that is really
            // a destination.
            if app.showProfile {
                ProfileView()
                    .environmentObject(app)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .trailing))
                    .zIndex(40)
            }

            // Chat attachment opened full screen. Hosted here (not in the chat
            // view) so it covers the dock and the immersive chrome.
            if !app.worldMediaViewerItems.isEmpty {
                ChatMediaViewer(items: app.worldMediaViewerItems,
                                startIndex: app.worldMediaViewerIndex) {
                    app.closeWorldMediaViewer()
                }
                .environmentObject(app)
                .transition(.opacity)
                .zIndex(60)
            }
        }
        .animation(.ggOverlay, value: app.worldMediaViewerItems.isEmpty)
        .animation(.ggOverlay, value: app.storyOverlayActive)
        // Don't ignore keyboard — composer must sit above it when open.
        .animation(.ggOverlay, value: app.isComposing)
        .animation(.ggGentle, value: app.isWorldImmersive)
        .animation(.ggNav, value: app.showProfile)
        .sheet(isPresented: $app.showStoriesBrowser) {
            StoriesBrowserView()
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // These also open from inside the stories browser and the profile,
        // which are themselves sheets — a sheet can't be presented from here
        // while one of those is up, so each of them declares its own copy and
        // this one stands down. Same shape as the post viewer above.
        .fullScreenCover(isPresented: Binding(
            get: { app.showStoryComposer && !app.showStoriesBrowser },
            set: { app.showStoryComposer = $0 }
        )) {
            StoryComposer().environmentObject(app)
        }
        .sheet(isPresented: Binding(
            get: { app.showStoryArchive && !app.showStoriesBrowser && !app.showProfile },
            set: { app.showStoryArchive = $0 }
        )) {
            StoryArchiveView().environmentObject(app)
        }
        .sheet(isPresented: Binding(
            get: { app.showCloseFriends && !app.showStoriesBrowser },
            set: { app.showCloseFriends = $0 }
        )) {
            CloseFriendsView().environmentObject(app)
        }
        // The wallet, from anywhere: settings opens it, and so does delivery
        // checkout when an order is short by more than the balance covers. The
        // profile declares its own copy (it's a sheet, so this one can't
        // present over it) and this one stands down while it's up.
        .sheet(isPresented: Binding(
            get: { app.showWallet && !app.showProfile },
            set: { app.showWallet = $0 }
        )) {
            WalletView().environmentObject(app)
        }
        // Reporting and blocking, from anywhere: a post in the feed, a comment,
        // a profile. The profile and the comments sheet declare their own copies
        // (a sheet can't present over a sheet) and this one stands down while
        // either is up — the same shape as the wallet above.
        .safetyPresentations(active: !app.showProfile && app.commentingPostID == nil
                             && app.browsingProduct == nil)
        // The long-form player is a fullScreenCover and owns its own comments
        // drawer — presenting from here while it's up dismisses the player.
        .sheet(isPresented: Binding(
            get: { app.commentingPostID != nil && !app.showWatching },
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
        .sheet(isPresented: Binding(
            get: { app.editingLongFormAttachmentID != nil },
            set: { if !$0 { app.closeVideoDetails() } }
        )) {
            if let id = app.editingLongFormAttachmentID {
                VideoDetailsSheet(target: .attachment(id))
                    .environmentObject(app)
            }
        }
        // The profile and the player are themselves covers and declare their
        // own copy of this editor — same shape as the post viewer above.
        .sheet(isPresented: Binding(
            get: { app.editingVideoID != nil && !app.showProfile && !app.showWatching },
            set: { if !$0 { app.closeVideoDetails() } }
        )) {
            if let id = app.editingVideoID {
                VideoDetailsSheet(target: .published(id))
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
            get: { app.showSellerHub },
            set: { if !$0 { app.closeSellerHub() } }
        )) {
            SellerListingsView()
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(GGColor.sheetBG)
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
            switch phase {
            case .inactive, .background:
                app.persistSession()
            case .active:
                // A backgrounded socket is dropped by API Gateway well before the
                // user notices — re-dial and re-sync the moment we're back.
                app.worldEnterForeground()
                if app.backendConnected, app.phase == .app {
                    Task { await app.refreshWatch() }
                }
            @unknown default:
                break
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
