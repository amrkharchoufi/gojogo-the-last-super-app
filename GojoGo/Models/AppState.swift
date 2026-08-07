import SwiftUI
import UIKit
import CoreLocation

@MainActor
final class AppState: ObservableObject {
    // Auth / onboarding
    @Published var phase: AuthPhase = .welcome
    @Published var onboardingStep: Int = 1
    @Published var email: String = ""

    // Backend auth/session (Milestone 4 — see AppState+Backend.swift)
    @Published var authPassword: String = ""
    @Published var authCode: String = ""
    @Published var emailAuthStep: EmailAuthStep = .credentials
    @Published var authBusy: Bool = false
    @Published var authError: String? = nil
    /// True once /v1/auth/session + profile succeeded against the live backend.
    var backendConnected: Bool = false
    /// True once `connectBackend()` has finished, whichever way it went. Screens
    /// that shimmer need to tell "no backend yet" apart from "no backend at all":
    /// before this flips, `backendConnected == false` only means the answer
    /// hasn't come back, and a screen that reads it as "offline" starts its
    /// loading state late — one stage behind everything that was already
    /// shimmering.
    @Published var backendResolved: Bool = false
    /// Initial live-feed load in flight (drives the Home loading state).
    @Published var feedLoading: Bool = false
    /// Keyset cursor for the next feed page; nil = no more pages.
    var feedNextBefore: String? = nil
    var feedLoadingMore: Bool = false
    /// Keyset cursor for the next economy listings page; nil = no more pages.
    var economyNextBefore: String? = nil
    var economyLoadingMore: Bool = false
    /// Listings dropped into the catalog to be *looked at* rather than browsed —
    /// a thread's listing card, "View in marketplace" on a paused item. They are
    /// deliberately not cached to disk (`CachedSession` filters them out): the
    /// catalog on disk is meant to be the last thing the marketplace served, and
    /// a card you opened once out of a chat is not that. Session-scoped.
    var economySeededListingIDs: Set<UUID> = []
    /// Set on fresh signups so the onboarding flow runs before entering the app.
    var pendingOnboarding: Bool = false

    // Appearance
    @Published var appTheme: AppTheme = .dark

    // Main navigation
    @Published var navMode: AppNavMode = .collections
    @Published var activeTab: AppTab = .home
    /// Collections dock: false = compact pill with just the active section, true = full tab row.
    @Published var navBarExpanded: Bool = false
    @Published var watchSubFeed: WatchSubFeed = .feed
    @Published var myWorldTab: MyWorldTab = .messages
    @Published var selectedWorldConversationID: UUID? = nil
    @Published var worldDraft: String = ""
    @Published var worldSearch: String = ""
    // GojoMessages starts empty and fills from the server. It seeded a demo
    // roster, demo circles and demo threads until 2026-08-02; they went with the
    // canned auto-reply, because a made-up contact you can message is the same
    // fiction as a made-up person answering. An empty Messages list on a fresh
    // account is the honest state, and it is the state the server describes.
    @Published var worldContacts: [WorldContact] = []
    @Published var worldCircles: [WorldCircle] = []
    @Published var worldConversations: [WorldConversation] = []
    @Published var showWorldAppsMenu: Bool = false
    @Published var showWorldContact: Bool = false
    @Published var worldIsEditing: Bool = false
    @Published var showWorldFilters: Bool = false
    /// Single modal-sheet slot for My World (new message / poll / send-later).
    @Published var worldSheet: WorldSheetKind? = nil
    @Published var worldFilterUnreadOnly: Bool = false
    /// Media staged in the chat composer, sent together with the next message.
    @Published var worldPendingAttachments: [WorldPendingAttachment] = []
    /// Conversation currently showing the "…" typing indicator.
    @Published var worldTypingConversationID: UUID? = nil
    /// Where the next page of *older* messages starts, per thread. Nil means the
    /// thread has been read back to its first message — messages are kept
    /// forever server-side, so without a cursor a long history simply sat there
    /// unasked for behind the newest thirty.
    @Published var worldOlderCursor: [UUID: String] = [:]
    /// Pages already pulled back, oldest-first. Held apart from the thread's
    /// messages because a refresh replaces the newest page wholesale and would
    /// take the scrolled-back history with it.
    var worldOlderPages: [UUID: [WorldMessage]] = [:]
    /// Server activity time each thread's list preview has actually been brought
    /// up to date with. The server can't read an envelope, so it previews every
    /// encrypted thread as the constant "Message" and only this device can say
    /// what the last message was — this is what stops the row from repeating a
    /// stale preview, and what keeps the backfill that fixes it from re-running
    /// on every poll. In memory on purpose: a launch is exactly when the list
    /// should re-derive its previews.
    var worldPreviewSyncedAt: [UUID: Date] = [:]
    /// Message the tapback/action overlay is focused on (long-press target).
    @Published var worldReactionTarget: UUID? = nil
    /// Message the composer is currently quoting as an inline reply.
    @Published var worldReplyingTo: UUID? = nil
    /// In-view overlays shown over the immersive chat (sheets don't present there).
    @Published var showWorldPollOverlay: Bool = false
    @Published var showWorldSendLaterOverlay: Bool = false
    /// Chosen date for a Send-Later message.
    @Published var worldSendLaterDate: Date = {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }()
    /// When set, the next send is scheduled for this label instead of sent now.
    @Published var worldSendLaterLabel: String? = nil
    /// Transient status line above the composer ("Getting your location…").
    @Published var worldNotice: String? = nil
    private var worldNoticeTask: Task<Void, Never>? = nil
    /// True while the live socket is up — the chat header shows "Connecting…" otherwise.
    @Published var worldRealtimeConnected: Bool = false
    /// The person (or group) behind the open thread, for the contact page.
    @Published var worldContactProfile: WorldContactProfile? = nil
    /// Attachment(s) open in the full-screen media viewer.
    @Published var worldMediaViewerItems: [ChatMediaItem] = []
    @Published var worldMediaViewerIndex: Int = 0
    /// Threads muted on this device (no local alert; server push is a global toggle).
    @Published var worldMutedConversations: Set<UUID> = WorldPreference.mutedConversations
    /// Threads whose pinned reference card the reader has put away, on this device.
    @Published var worldDismissedContextCards: Set<UUID> = WorldPreference.dismissedContextCards

    // MARK: My World settings (device preferences — see `WorldPreference`)

    /// Push notifications for GojoGo on this device.
    @Published var worldPushEnabled: Bool = WorldPreference.pushEnabled {
        didSet {
            guard oldValue != worldPushEnabled else { return }
            WorldPreference.pushEnabled = worldPushEnabled
            PushRegistrar.shared.setMuted(!worldPushEnabled)
        }
    }
    /// Whether the composer tells the other side you're typing.
    @Published var worldTypingIndicatorsEnabled: Bool = WorldPreference.typingIndicators {
        didSet { WorldPreference.typingIndicators = worldTypingIndicatorsEnabled }
    }
    /// Whether "Location" is offered in the chat apps drawer.
    @Published var worldLocationSharingEnabled: Bool = WorldPreference.locationSharing {
        didSet { WorldPreference.locationSharing = worldLocationSharingEnabled }
    }
    /// Wallpaper applied to conversations you start.
    @Published var worldDefaultBackground: WorldChatBackground = WorldPreference.defaultBackground {
        didSet { WorldPreference.defaultBackground = worldDefaultBackground }
    }
    /// Draft state for the settings screen's profile card.
    @Published var worldSettingsName: String = ""
    @Published var worldSettingsAvatarData: Data? = nil
    @Published var worldSettingsBusy: Bool = false
    @Published var worldSettingsError: String? = nil
    @Published var worldSettingsSaved: Bool = false

    // MARK: GojoMessages contact aliases (private per-viewer renames)
    /// Contacts this account has privately renamed, `contactId -> alias`.
    ///
    /// Applied at render time rather than on the wire, because the server
    /// broadcasts one payload to every participant of a thread — a name baked in
    /// server-side would be right over REST and wrong over the socket. The alias
    /// is ours alone: the person renamed never sees it, and neither does anyone
    /// else. Only pushes are resolved server-side, since a device can't rewrite
    /// an APNs alert after the fact.
    @Published var worldAliases: [UUID: String] = [:]

    // MARK: GojoMessages private network (Phase 2f — the graph, its audiences, its content)
    /// Posts from people whose number you have, newest first.
    @Published var worldFeedPosts: [WorldPost] = []
    /// Unexpired stories, grouped by author, for the row above the feed.
    @Published var worldStories: [WorldStoryRing] = []
    /// The server-side contacts graph. Distinct from `worldContacts`, which is
    /// the picker's row model — no longer seeded with anybody.
    @Published var worldGraphContacts: [WorldGraphContact] = []
    /// Whether the graph above has actually been fetched. An empty list is a
    /// real answer as well as a not-yet, and telling somebody they haven't added
    /// the person they're talking to is only fair once the difference is known.
    @Published var worldGraphLoaded: Bool = false
    /// Your own rich GojoMessages profile (separate from the public one).
    @Published var worldRichProfile = WorldRichProfile()
    /// Why the last "New Message" attempt reached nobody. Shown in that sheet:
    /// a number that isn't on GojoMessages has to say so, because the only other
    /// honest outcome is nothing happening at all.
    @Published var worldNewMessageError: String?
    @Published var worldFeedLoading: Bool = false
    @Published var worldFeedLoaded: Bool = false
    /// Which tab the composer opens on. Set by whoever opens it — the "Your
    /// story" bubble means a story, the `+` means a post — because a composer
    /// that always opens on Post makes the story bubble open the wrong thing.
    @Published var worldComposerKind: String = "post"
    /// The story ring currently open full-screen, if any.
    @Published var openWorldStory: WorldStoryRing?

    // MARK: My World setup (WhatsApp-style: own phone-verified identity)
    /// Backend `GET /v1/world/me` — true once phone verified + World name set.
    @Published var worldSetupComplete: Bool = false
    /// Whether `worldSetupComplete` reflects a real backend answer yet.
    @Published var worldSetupLoaded: Bool = false
    /// True while conversation list fetch is in flight (avoids empty-flash).
    /// Starts true because the list begins empty until the first fetch lands.
    @Published var worldConversationsLoading: Bool = true
    /// Becomes true after the first connected fetch attempt finishes (success or fail).
    @Published var worldConversationsLoaded: Bool = false
    /// Rows drawn from the launch cache that the server hasn't confirmed yet.
    /// Cleared by the first page that comes back — which is also what removes
    /// any of them that thread no longer exists.
    var worldCachedOnlyConversationIDs: Set<UUID> = []
    @Published var worldSetupStep: WorldSetupStep = .intro
    @Published var worldSetupPhone: String = ""
    @Published var worldSetupCode: String = ""
    @Published var worldSetupName: String = ""
    @Published var worldSetupAvatarData: Data? = nil
    @Published var worldSetupAvatarURL: String? = nil
    @Published var worldSetupBusy: Bool = false
    @Published var worldSetupError: String? = nil
    /// Verified phone shown read-only once set (My World identity key).
    @Published var worldPhone: String? = nil
    /// Throttle for outbound typing pings on live threads.
    var worldLastTypingSentAt: Date? = nil
    @Published var showProfile: Bool = false
    @Published var profileUser: ProfileUser? = nil
    @Published var showStoriesBrowser: Bool = false
    @Published var showWatching: Bool = false
    @Published var watchingWithMadeleine: Bool = false
    @Published var showCompose: Bool = false   // legacy sheet flag — prefer isComposing
    @Published var isComposing: Bool = false
    @Published var showAttachMenu: Bool = false
    @Published var composeText: String = ""
    @Published var composeAttachments: [ComposeAttachment] = []
    @Published var editingAttachmentID: UUID? = nil
    @Published var viewingStory: Story? = nil
    @Published var viewingFrameIndex: Int = 0
    /// When true, story is shown as an in-app overlay (not a system cover).
    @Published var storyOverlayActive: Bool = false
    /// Frozen author order for the current viewer session (Instagram-style).
    /// Empty while a highlight is playing — a highlight is a ring of one.
    var storyViewerRail: [UUID] = []

    // Stories — composing, engagement, and what outlives the 24 hours.
    @Published var showStoryComposer: Bool = false
    /// Set when the composer should open straight into the close-friends audience.
    @Published var storyComposerAudience: StoryAudience = .everyone
    /// Playing a highlight rather than a live ring — no expiry, its own title.
    @Published var viewingHighlightTitle: String? = nil
    @Published var storyArchive: [StoryFrame] = []
    @Published var storyHighlights: [StoryHighlight] = []
    @Published var closeFriends: [CloseFriend] = []
    @Published var showStoryArchive: Bool = false
    @Published var showCloseFriends: Bool = false
    /// Replies and viewers for the frame currently open in the viewer.
    @Published var storyReplies: [StoryReply] = []
    @Published var storyViewers: [StoryViewerInfo] = []
    @Published var storyInsightsLoading: Bool = false
    /// Transient message over the story surfaces — same pattern as world/economy/delivery.
    @Published var storyNotice: String? = nil
    var storyNoticeTask: Task<Void, Never>? = nil
    /// A highlight being played. It isn't one of the live rings, so the viewer's
    /// ring lookups fall back to it — see `liveStory(id:)`.
    var playingHighlightRing: Story? = nil
    @Published var messagingProduct: Product? = nil
    @Published var browsingProduct: Product? = nil
    @Published var sellerChat: [ChatMessage] = []
    @Published var sellerDraft: String = ""
    /// A thread waiting on My World setup — opened once it completes. Named for
    /// the listing chat it was built for; since Phase 4 M2 an order thread parks
    /// here too, because the gate is the same one and it is about the *reader*
    /// rather than about what they were reading.
    var pendingSellerConversation: (id: UUID, draft: String)? = nil
    @Published var showSellSheet: Bool = false

    // Economy — the seller's own shelf (Phase 2b · M5)
    /// "Your listings" presented over Economy.
    @Published var showSellerHub: Bool = false
    /// Everything the signed-in user is selling, every status, newest first.
    @Published var sellerListings: [SellerListing] = []
    /// Server-computed totals — they cover every listing, not just the page.
    @Published var sellerStats: SellerStatsDTO? = nil
    @Published var sellerListingsLoading: Bool = false
    /// Non-nil while the edit form is open on one of the user's own listings.
    @Published var editingListing: SellerListing? = nil
    /// Transient message shown over Economy — a refused edit, a failed relist.
    @Published var economyNotice: String? = nil
    var economyNoticeTask: Task<Void, Never>?

    // MARK: Shops — the merchant catalog (Phase 5 · M1 + M2)
    //
    // Beside the C2C shelf above, not instead of it: `products` up there is one
    // person selling one thing, and everything below is a provisioned seller
    // with variants, stock and an order that settles when the buyer says it
    // arrived. Two catalogs on one tab, which is what the segment picker is for.

    /// Which half of Economy is on screen. Persisted with the rest of the tab
    /// state so coming back lands where you left.
    @Published var economySegment: EconomySegment = .marketplace
    @Published var shopProducts: [ShopProductDTO] = []
    @Published var shopCategory: String = "All"
    @Published var shopLoading: Bool = false
    var shopNextBefore: String? = nil
    var shopLoadingMore: Bool = false
    /// The product page, presented over the tab.
    @Published var browsingShopProduct: ShopProductDTO? = nil
    @Published var shopProductReviews: [ShopReviewDTO] = []
    /// One checkout is one seller (SPECS §6, read literally), so the basket
    /// carries the seller it belongs to and refuses to mix.
    @Published var shopBasket: [ShopBasketLine] = []
    @Published var showShopCheckout: Bool = false
    @Published var shopOrders: [ShopOrderDTO] = []
    @Published var showShopOrders: Bool = false
    /// What a digital purchase granted — downloads and licence keys.
    @Published var entitlements: [ShopEntitlementDTO] = []

    // MARK: Services (Phase 5 · M3)

    @Published var services: [ServiceDTO] = []
    @Published var serviceCategory: String = "All"
    @Published var servicesLoading: Bool = false
    var servicesNextBefore: String? = nil
    var servicesLoadingMore: Bool = false
    @Published var browsingService: ServiceDTO? = nil
    @Published var serviceSlots: SlotsDTO? = nil
    @Published var serviceSlotsLoading: Bool = false
    @Published var serviceReviews: [ServiceReviewDTO] = []
    @Published var bookings: [BookingDTO] = []
    @Published var showBookings: Bool = false

    // MARK: The two Phase 5 consoles
    //
    // Derived from `/v1/me/roles` like every other role in this app — an
    // approved application provisions a row, and the row is the fact.

    @Published var isSeller: Bool = false
    @Published var isServiceProvider: Bool = false
    @Published var showSellerConsole: Bool = false
    @Published var showProviderConsole: Bool = false

    /// The shop and provider rows this account *is*, read from `/v1/me/roles`
    /// rather than from a console that has been opened. Both catalogs carry the
    /// owning id on every card (`sellerId`, `providerId`), so knowing these two
    /// is the whole of "this one is mine" — and it has to be known before the
    /// first tap, not after the server refuses it. Nothing here is a permission:
    /// the server is still the only thing that decides a checkout.
    @Published var myShopId: UUID? = nil
    @Published var myProviderId: UUID? = nil

    @Published var myShop: ShopSellerDTO? = nil
    @Published var myShopProducts: [ShopProductDTO] = []
    @Published var shopOrderQueue: [ShopOrderDTO] = []
    @Published var shopPromotions: [ShopPromotionDTO] = []
    @Published var shopWallet: PayeeWalletDTO? = nil
    @Published var sellerConsoleLoading: Bool = false

    @Published var myProvider: ProviderDTO? = nil
    @Published var myServices: [ServiceDTO] = []
    @Published var providerBookings: [BookingDTO] = []
    @Published var providerAvailability: [AvailabilityRuleDTO] = []
    @Published var providerExceptions: [String] = []
    @Published var providerDocuments: [ProviderDocumentDTO] = []
    @Published var providerWallet: PayeeWalletDTO? = nil
    @Published var providerConsoleLoading: Bool = false

    // MARK: Ownership transfers (Phase 5 · M2)

    @Published var transfers: [TransferDTO] = []
    @Published var showTransfers: Bool = false
    @Published var openTransferID: UUID? = nil
    @Published var transferDocuments: [TransferDocumentDTO] = []
    @Published var selectedTVShow: TVShow? = nil
    @Published var tvShows: [TVShow] = SampleData.tvShows
    @Published var tvHero: TVShow = SampleData.tvHero
    @Published var commentingPostID: UUID? = nil
    @Published var watchingVideoID: UUID? = nil
    @Published var watchingChat: [ChatMessage] = SampleData.watchingChat
    @Published var watchingDraft: String = ""
    /// When set, ShortsView jumps to this short (e.g. opened from a feed video).
    @Published var focusedShortID: UUID? = nil
    /// Keyed by post (or video) id, newest thread first. Each entry is a
    /// top-level comment carrying its own replies — threads are one level deep.
    @Published var commentsByPost: [UUID: [Comment]] = [:]
    @Published var draftComment: String = ""
    /// The comment the draft answers, if any. Holds whichever comment was
    /// tapped, including a reply — the server re-points it at the thread root.
    @Published var replyingToCommentID: UUID? = nil
    @Published var replyingToHandle: String? = nil
    /// Threads the user has expanded past their preview.
    @Published var expandedCommentIDs: Set<UUID> = []

    // Activity / notifications
    @Published var notifications: [ActivityItem] = SampleData.notifications
    @Published var showActivity: Bool = false

    // Direct messages (per-handle threads)
    @Published var dmPeer: ProfileUser? = nil
    @Published var dmDraft: String = ""
    @Published var dmThreads: [String: [ChatMessage]] = [:]

    // Channel subscriptions + video reactions
    @Published var subscribedChannels: Set<String> = []
    @Published var dislikedVideoIDs: Set<UUID> = []
    @Published var downloadedVideoIDs: Set<UUID> = []
    /// Non-nil while the long-form details editor is up (a published video id).
    @Published var editingVideoID: UUID? = nil
    /// Deletions awaiting confirmation. These live here rather than in the row
    /// that asked, because a dialog raised from inside a `List` row or a
    /// dismissing context menu never presents — the screen root owns it.
    @Published var pendingVideoDelete: UUID? = nil
    @Published var pendingShortDelete: UUID? = nil
    @Published var pendingPostDelete: UUID? = nil
    /// Non-nil while the pre-publish details editor is up (a compose attachment id).
    @Published var editingLongFormAttachmentID: UUID? = nil
    /// Ids counted this run, so re-rendering a card can't inflate a view count.
    private var countedViewIDs: Set<UUID> = []
    // Keyset cursors + in-flight flags for the two Watch feeds.
    @Published var watchNextBefore: String? = nil
    @Published var shortsNextBefore: String? = nil
    @Published var watchLoadingMore: Bool = false
    @Published var shortsLoadingMore: Bool = false
    /// Local video/short ids currently being uploaded — blocks double-create.
    var videoPublishInFlight: Set<UUID> = []
    /// Profiles the user turned notifications on for.
    @Published var notifyHandles: Set<String> = []
    /// Follower counts learned from real profile fetches, keyed by lowercased
    /// handle. Used for the "subscribers" line — absent means we show nothing.
    @Published var followerCountByHandle: [String: Int] = [:]

    // Profile editing + post viewer (profile grid)
    @Published var showEditProfile: Bool = false
    @Published var viewingPostID: UUID? = nil

    // Profile Home (customizable canvas tab)
    @Published var profileHomeBlocks: [ProfileHomeBlock] = []
    @Published var profileHomeEditing: Bool = false
    /// Non-nil while a block editor sheet is presented.
    @Published var editingHomeBlockID: UUID? = nil
    /// Drives the "add a block" type-picker sheet.
    @Published var showHomeBlockPicker: Bool = false

    // User + content (live, mutable)
    @Published var user = GGUser()

    /// Initial drawn on this user's own avatar while their photo loads (and when
    /// they have none). `nil` before the profile is known, so a signed-out or
    /// still-connecting session shows an empty disc rather than somebody else's
    /// letter — the seed ring used to carry a hardcoded "J".
    var ownAvatarLetter: String? {
        guard let first = user.name.first ?? user.handle.first else { return nil }
        return String(first).uppercased()
    }
    @Published var interests: [Interest] = SampleData.interests
    @Published var stories: [Story] = SampleData.stories
    @Published var posts: [Post] = SampleData.posts
    @Published var videos: [VideoItem] = SampleData.videos
    @Published var shorts: [Short] = SampleData.shorts
    /// Home-feed video mute — shared across every post until toggled again.
    @Published var feedVideosMuted: Bool = true
    /// Shorts / Reels mute — independent from home feed videos.
    @Published var shortsMuted: Bool = false
    /// Exclusive feed autoplay — only this post's current slide may play.
    @Published var activeFeedVideoPostID: UUID? = nil
    @Published var products: [Product] = SampleData.products
    @Published var featuredProduct: Product = SampleData.featuredProduct
    @Published var people: [PersonSuggestion] = SampleData.people
    @Published var profilePhotos: [String] = SampleData.profileGridURLs
    @Published var savedPostIDs: Set<UUID> = []
    @Published var chatMessages: [ChatMessage] = []

    // GojoTravel
    @Published var travelPhase: TravelPhase = .home
    @Published var travelPickup: TravelPlace = SampleData.travelDefaultCenter
    @Published var travelDropoff: TravelPlace? = nil
    @Published var travelQuery: String = ""
    @Published var travelRideOptions: [RideOption] = []
    @Published var selectedRide: RideOption? = nil
    @Published var travelDriver: TravelDriver? = nil
    @Published var travelRating: Int = 0
    @Published var travelRecent: [TravelPlace] = SampleData.travelRecentPlaces
    /// Live geocoder suggestions for `travelQuery` (see `travelQueryChanged`).
    @Published var travelSearchResults: [TravelPlace] = []
    @Published var travelSearching: Bool = false
    /// Where the pickup point came from, which the rider is entitled to know:
    /// a guessed city centre and a GPS fix look identical on a map.
    @Published var travelPickupState: TravelPickupState = .unknown
    var travelSearchTask: Task<Void, Never>?
    var travelPickupTask: Task<Void, Never>?
    // The real ride, when there is one (Phase 3 M3). Non-nil is what makes every
    // action on the travel screen a server call rather than a simulation.
    @Published var ride: RideDTO? = nil
    @Published var rideQuote: RideQuoteDTO? = nil
    var ridePollTask: Task<Void, Never>?
    private var travelMatchTask: Task<Void, Never>?

    // GojoDelivery
    @Published var deliveryRestaurants: [DeliveryRestaurant] = SampleData.deliveryRestaurants
    @Published var selectedDeliveryRestaurantID: UUID? = nil
    @Published var deliverySearch: String = ""
    @Published var deliveryCategory: String = "All"
    @Published var deliveryCart: [DeliveryCartLine] = []
    @Published var deliveryCartRestaurantID: UUID? = nil
    @Published var showDeliveryCheckout: Bool = false
    @Published var deliveryStatus: DeliveryOrderStatus? = nil
    @Published var deliveryCourier: DeliveryCourier? = nil
    @Published var deliveryEtaMinutes: Int = 0
    /// 0 = courier at restaurant, 1 = courier at your door.
    @Published var deliveryCourierProgress: Double = 0
    /// NONE / SEARCHING / ASSIGNED / FAILED (Phase 4 M1) — whether anybody is
    /// actually coming for this order, which the six order statuses cannot say.
    @Published var deliveryCourierSearch: String? = nil
    // How this order gets handed over, and the half of it the customer holds
    // (Phase 4 M2). The PIN is the server's — it is minted when the restaurant
    // accepts and this app only ever reads it out.
    /// PIN / PHOTO / CONFIRM.
    @Published var deliveryHandoffMode: String = "CONFIRM"
    /// Six digits to give the courier, or empty when there is nothing to give.
    @Published var deliveryPin: String = ""
    /// A short-lived signed URL for the drop-off photo, once there is one.
    @Published var deliveryProofPhotoURL: String? = nil
    /// The thread with whoever is bringing it, opened server-side at assignment.
    @Published var deliveryConversationID: UUID? = nil
    @Published var deliveryHandoffBusy: Bool = false
    /// The kitchens on the live order (Phase 4 M3), each with its own state.
    /// Empty for an order from a backend that predates sub-orders, which the
    /// tracking card reads as the one restaurant it always drew.
    @Published var deliveryKitchens: [SubOrderDTO] = []
    @Published var deliverySubOrderBusy: Bool = false
    /// Whether the cart is being collected rather than delivered (Phase 4 M4).
    /// A property of the checkout and not of a restaurant: an order is one kind
    /// or the other, and a cart that was half collected would be two orders
    /// wearing one receipt. Reset with the cart, because the next cart is a
    /// fresh decision.
    @Published var deliveryWantsPickup: Bool = false
    /// The live order's own kind, which is the server's answer and not this
    /// app's intention — they differ for the whole life of an order placed
    /// before somebody last toggled the switch above.
    @Published var deliveryOrderIsPickup: Bool = false
    @Published var deliveryRating: Int = 0
    @Published var deliveryPastOrders: [DeliveryPastOrder] = []
    /// Restaurant the active order was placed from (kept after cart clears).
    @Published var deliveryOrderRestaurantID: UUID? = nil
    @Published var deliveryOrderTotalLabel: String = ""
    @Published var deliveryOrderSummary: String = ""
    private var deliveryTask: Task<Void, Never>?
    /// Non-nil while a server-backed order is in flight. The SampleData catalog
    /// still runs the on-device simulation below; a live order's fulfilment is
    /// owned by the backend and only mirrored here (see AppState+Delivery).
    var deliveryLiveOrderID: UUID? = nil
    var deliveryPollTask: Task<Void, Never>?
    /// Restaurants whose menu is being fetched, so a re-open doesn't re-request.
    var deliveryMenuLoading: Set<UUID> = []
    /// Saved delivery addresses (server-backed) + the one this order goes to.
    @Published var deliveryAddresses: [DeliveryAddress] = []
    @Published var selectedDeliveryAddressID: UUID? = nil
    @Published var showDeliveryAddressSheet: Bool = false
    /// Transient message shown over GojoDelivery — a failed order, a refused
    /// cancel. Cleared automatically; `deliveryNoticeTask` owns the timer.
    @Published var deliveryNotice: String? = nil
    var deliveryNoticeTask: Task<Void, Never>?
    /// What checkout will cost, priced by the server (Phase 2e M3). Nil until
    /// the cart has been quoted — the app never adds up an order itself, so
    /// this is also what says whether checkout can proceed at all.
    @Published var deliveryQuote: QuoteDTO? = nil
    @Published var deliveryQuoting: Bool = false
    /// When this checkout is booked for (Phase 4 M5), or nil for "now" — which
    /// is what the great majority of orders are, so the control starts here and
    /// the whole picker stays out of the way until somebody asks for it. Reset
    /// with the cart: the next cart is a fresh decision, exactly like the
    /// pickup switch above.
    @Published var deliveryScheduledFor: Date? = nil
    /// Orders booked for later that no kitchen has been told about yet. Kept
    /// apart from the live order deliberately: a booking three days out is not
    /// something to draw a countdown for, and the tracking card is about food
    /// that is on its way.
    @Published var deliveryBookings: [OrderDTO] = []
    /// The booking whose sheet is open, if any.
    @Published var deliveryBookingBeingEdited: OrderDTO? = nil
    @Published var deliveryBookingBusy: Bool = false
    // Ordering for somebody else (Phase 4 M6). Properties of *this* checkout,
    // like the pickup switch and the booked time, and cleared with the cart.
    @Published var deliveryRecipientName: String = ""
    @Published var deliveryRecipientPhone: String = ""
    /// The report on the order being looked at, once there is one. Nil means
    /// either nothing reported or nothing loaded — the sheet asks.
    @Published var deliveryDispute: DisputeDTO? = nil
    @Published var showDeliveryDispute: Bool = false
    @Published var deliveryDisputeBusy: Bool = false
    /// A public tracking link, once minted. Held so the share sheet has
    /// something to present and so a second tap doesn't re-mint.
    @Published var deliveryShareLink: ShareOrderDTO? = nil
    /// What they thought of the courier, kept apart from `deliveryRating` for
    /// the reason the two endpoints are apart: one is about the food.
    @Published var deliveryCourierRating: Int = 0
    /// The live order as the server last described it. Kept whole (rather than
    /// only unpacked into the fields above) so a sheet that needs the order's
    /// lines — reporting a problem — has them without a second fetch.
    @Published var deliveryLiveOrder: OrderDTO? = nil
    /// The promotion code typed at checkout, and the tip chosen with it. A code,
    /// never an amount: what it is worth is the server's answer.
    @Published var deliveryPromotionCode: String = ""
    @Published var deliveryTipCents: Int = 0
    /// A restaurant's live promotions, keyed by merchant, loaded only when its
    /// storefront shows a `promo_banner` (Phase 2e M4) — the block names a
    /// promotion by id, and the offer itself always comes from the server.
    @Published var deliveryPromotions: [UUID: [DeliveryPromotionDTO]] = [:]

    // GoJo Wallet (Phase 2e M3). One balance for the whole superapp — delivery
    // spends from it today, Phase 3's stake and ride tokens land in it next.
    /// The account's settings sheet — everything that used to be an entry in
    /// the profile's overflow menu (see SettingsView).
    @Published var showSettings: Bool = false
    @Published var wallet: WalletDTO? = nil
    @Published var walletTransactions: [WalletTransactionDTO] = []
    @Published var showWallet: Bool = false
    /// True while a hosted checkout is being opened — the top-up buttons go
    /// quiet rather than starting a second session.
    @Published var walletBusy: Bool = false
    @Published var walletNotice: String? = nil
    var walletNoticeTask: Task<Void, Never>?

    // Ride tokens (Phase 3 M4). A driver spends one to accept a trip, and a
    // driver with none is filtered out of every search — silently, by design.
    // These two are what turns that silence into a sentence. See
    // AppState+Tokens.swift.
    /// The shelf: balance, packs, and recent token movements.
    @Published var tokenWallet: TokenWalletDTO? = nil
    /// What a trip costs, and whether this driver can take one right now.
    @Published var rideTokens: MyRideTokensDTO? = nil
    @Published var tokensBusy: Bool = false
    /// What a refused purchase was short by — the amount the "top up" button on
    /// the token screen fills, so the driver never has to work it out.
    @Published var pendingTokenTopUpMinor: Int? = nil

    // Merchant partner — running a restaurant on GojoDelivery (Phase 2b M6).
    // Distinct from the driver/courier `partner*` state below: that one is the
    // gig-worker prototype waiting on Phase 3 dispatch, this one is live.
    // Restaurants are created in Gojo Admin; the app only runs one.
    // See AppState+Partner.swift.
    /// The user's partner account, or nil if they aren't a partner.
    @Published var merchantAccount: MerchantAccount? = nil
    /// Their restaurant — only once an application is approved.
    @Published var merchantStorefront: MerchantStorefront? = nil
    @Published var showMerchantPartner: Bool = false
    @Published var merchantBusy: Bool = false
    /// Transient message shown over the merchant sheet — which covers
    /// GojoDelivery, so `deliveryNotice` would render behind it.
    @Published var merchantNotice: String? = nil
    var merchantNoticeTask: Task<Void, Never>?
    /// What the restaurant has earned and whether it can be paid out
    /// (Phase 2e M3). Read from delivery's own `/mine` surface — the vertical
    /// that owns the merchant is the only one that can prove who owns it.
    @Published var merchantWallet: MerchantWalletDTO? = nil

    // Business profiles — a business IS a profile (Phase 2e M1).
    // See AppState+Business.swift.
    /// The business profiles this account runs, newest first.
    @Published var ownedBusinesses: [BusinessIdentity] = []
    /// Who new content is published as: nil = you, otherwise one of the above.
    /// Mirrors `ActingIdentity.shared`, which is what the stores actually read.
    @Published var actingBusinessID: UUID? = nil
    @Published var showBusinessProfiles: Bool = false
    @Published var businessBusy: Bool = false

    // Trust & safety (Phase 2e M5). See AppState+Safety.swift.
    /// What the report sheet is pointed at; nil when it is closed.
    @Published var reportTarget: ReportTarget? = nil
    /// The reason list, fetched from the server so the app never hardcodes one
    /// that can grow. Starts as the shipped copy, so the sheet is never empty.
    @Published var reportReasons: [ReportReason] = ReportReason.fallback
    @Published var reportBusy: Bool = false
    /// Set once a report is filed — the sheet becomes a thank-you rather than
    /// a form somebody can submit twice.
    @Published var reportSubmitted: Bool = false
    @Published var reportNotice: String? = nil
    /// Accounts *you* blocked, newest first. Who blocked you is deliberately
    /// unknowable — there is no field for it here or on the wire.
    @Published var blockedAccounts: [BlockedAccount] = []
    @Published var showBlockedAccounts: Bool = false
    /// A block waiting on its confirmation dialog.
    @Published var pendingBlock: BlockCandidate? = nil
    @Published var showDeleteAccount: Bool = false
    @Published var deleteAccountBusy: Bool = false
    @Published var deletionStatus: DeletionStatusDTO? = nil
    /// Transient message for any of the above.
    @Published var safetyNotice: String? = nil

    // The safety pack (Phase 3 M5). See AppState+Safety.swift.
    /// Who to tell if something goes wrong, and how many are allowed.
    @Published var emergencyContacts: [EmergencyContactDTO] = []
    @Published var emergencyContactsMax: Int = 5
    @Published var showEmergencyContacts: Bool = false
    @Published var emergencyContactsBusy: Bool = false
    /// The live trip's public tracking link, once somebody has made one.
    @Published var tripShare: ShareTripDTO? = nil
    @Published var shareBusy: Bool = false
    /// Set the moment SOS is confirmed. Non-nil is what turns the trip screen
    /// red and puts the emergency number in front of a thumb.
    @Published var sos: SosDTO? = nil
    @Published var sosBusy: Bool = false
    /// Two deliberate taps: an SOS raised by accident is a person explaining
    /// themselves to their mother at midnight.
    @Published var confirmingSos: Bool = false
    /// Vehicles this account has been asked to confirm, newest first. Usually
    /// empty; a card appears on the travel screen when it isn't.
    @Published var verificationInvites: [VerificationInviteDTO] = []
    @Published var openVerification: VerificationInviteDTO? = nil
    @Published var verificationBusy: Bool = false
    /// Transient message over the business sheet (a taken handle, a failed save).
    @Published var businessNotice: String? = nil
    var businessNoticeTask: Task<Void, Never>?

    // Identity verification (Sumsub, via the backend `kyc` module).
    /// The signed-in person's identity check. Defaults to `.unavailable` so an
    /// app that hasn't asked the server yet — or is talking to a backend with no
    /// IDV vendor configured — shows nothing rather than a broken button.
    @Published var identity: IdentityVerification = .unavailable
    /// True while the SDK is being launched or a verdict is being fetched.
    @Published var identityBusy: Bool = false

    // Partner (Become a driver / delivery partner)
    /// Roles the user has fully onboarded into (can go online).
    @Published var partnerRoles: Set<PartnerRole> = []
    /// Non-nil while the become-a-partner flow is presented.
    @Published var partnerOnboardingRole: PartnerRole? = nil
    @Published var partnerStep: PartnerOnboardingStep = .rules
    /// True from the moment the cover opens until the server has said where
    /// this application already stands. The step it resolves to is only known
    /// after that round-trip, so the pages wait behind it rather than opening on
    /// the rules and then jumping — an applicant already in the queue was shown
    /// a form to fill in for as long as the network took to say otherwise.
    @Published var partnerResolving: Bool = false
    @Published var partnerApplication = PartnerApplication(role: .driver)
    @Published var partnerAgreedToTerms: Bool = false
    @Published var partnerStakeProcessing: Bool = false
    /// Transient message over the partner cover (a verification that wouldn't
    /// start, a check that couldn't be read).
    @Published var partnerNotice: String? = nil
    var partnerNoticeTask: Task<Void, Never>?
    /// Non-nil while the partner dashboard (working UI) is presented.
    @Published var partnerDashboardRole: PartnerRole? = nil
    @Published var partnerOnline: Bool = false
    @Published var partnerJobPhase: PartnerJobPhase = .idle
    @Published var partnerJob: PartnerJob? = nil
    @Published var partnerJobProgress: Double = 0
    // Earnings / trips / rating are tracked independently per role (driver vs courier).
    @Published var partnerEarningsByRole: [String: Double] = [:]
    @Published var partnerJobsByRole: [String: Int] = [:]
    @Published var partnerRatingByRole: [String: Double] = [:]
    private var partnerOfferTask: Task<Void, Never>?
    private var partnerJobTask: Task<Void, Never>?

    // Dispatch — Driver Mode against the real registry (Phase 3 M1/M2).
    // Empty for anybody who has never been approved, which is what makes the
    // local demo above still the right thing to show them.
    @Published var dispatchWorkers: [DispatchWorkerDTO] = []
    @Published var dispatchOffers: [DispatchOfferDTO] = []
    @Published var dispatchAssignment: DispatchAssignmentDTO? = nil
    @Published var dispatchOnline: Bool = false
    /// How often to report a position while available — the server's number,
    /// not a constant in this app.
    var dispatchPositionInterval: Int = 5
    var dispatchPositionTask: Task<Void, Never>?
    var dispatchPollTask: Task<Void, Never>?
    var dispatchDutyTracking: Bool = false

    // GojoTravel from the driver's seat (Phase 3 M3, wired to the dashboard).
    // The ride behind a RIDE assignment — what the driver's trip card, its
    // status buttons and the map guidance are drawn from.
    @Published var driverRide: RideDTO? = nil
    /// A ride this driver countered on, kept on screen while the rider decides.
    @Published var driverNegotiation: RideDTO? = nil
    /// True while a trip action (arrived / start / complete / counter) is in
    /// flight — one at a time, because each one moves a state machine.
    @Published var driverRideBusy: Bool = false
    var driverRidePollTask: Task<Void, Never>?
    var driverNegotiationPollTask: Task<Void, Never>?
    /// Rides whose completion this session has already celebrated and counted.
    /// A completed ride can be read again after the card is dismissed — a stale
    /// dispatch assignment, a poll that was already in flight — and without this
    /// the re-read replays the completion: card, haptic and earnings, forever.
    var settledDriverRideIDs: Set<UUID> = []

    // Courier Mode's other half (Phase 4 M1). Dispatch finds the work; this is
    // the delivery it turned out to be — what is in the bag, which restaurant,
    // and what it pays.
    @Published var courierJob: CourierJobDTO? = nil
    @Published var courierDeliveries: [CourierJobDTO] = []

    // Handoff integrity (Phase 4 M2). A refused code is an answer rather than
    // an error, so what a refusal leaves behind is state on this screen: the
    // server's sentence under the field, how many tries are left, and whether
    // the photo fallback has opened. Cleared on a success and on a new job.
    @Published var courierHandoffNotice: String? = nil
    /// Tries remaining on the delivery PIN. `-1` is "not counted", which is
    /// what the pickup code always is.
    @Published var courierAttemptsLeft: Int = -1
    @Published var courierSupportUnlocked: Bool = false
    @Published var courierHandoffBusy: Bool = false
    /// True while the drop-off photo is being uploaded — a PUT to S3 on a phone
    /// at a doorstep, which is long enough to need a spinner.
    @Published var courierProofUploading: Bool = false

    // What the work paid (Phase 4 M2). Dispatch's surface, so one wallet serves
    // Driver Mode and Courier Mode both.
    @Published var workerWallet: WorkerWalletDTO? = nil
    @Published var workerMoneyBusy: Bool = false

    // The kitchen's queue (Phase 4 M1). Empty for anybody who doesn't run a
    // restaurant, which is almost everybody.
    @Published var merchantOrders: [MerchantOrderDTO] = []
    @Published var merchantOrdersLoading: Bool = false
    /// While a collection code is being checked (Phase 4 M4) — one at a time,
    /// because the person it belongs to is standing at the counter.
    @Published var merchantCollectBusy: Bool = false

    // Driver/courier onboarding against the real `partner` application.
    @Published var driverApplication: DriverApplicationDTO? = nil
    @Published var partnerSubmitting: Bool = false

    private var persistTask: Task<Void, Never>?

    var selectedInterestCount: Int { interests.filter(\.selected).count }

    /// Stories tray order: You → unwatched → watched → muted (like Instagram).
    /// The server sorts the live rings the same way; this keeps SampleData and
    /// any optimistic local edit agreeing with it.
    var storyTray: [Story] {
        let you = stories.filter(\.isYou)
        let others = stories.filter { !$0.isYou }
        let heard = others.filter { !$0.muted }
        let muted = others.filter(\.muted)
        let fresh = heard.filter { $0.hasMedia && !$0.seen }
        let done = heard.filter { $0.hasMedia && $0.seen }
        let empty = heard.filter { !$0.hasMedia }
        return you + fresh + done + muted + empty
    }

    var halfPosts: [Post] { posts.filter(\.isHalfWidth) }
    var fullPosts: [Post] { posts.filter { !$0.isHalfWidth } }
    var myPosts: [Post] {
        posts.filter { $0.author == user.handle || $0.author == "@\(user.handle)" }
    }
    var savedPosts: [Post] { posts.filter { savedPostIDs.contains($0.id) || $0.bookmarked } }
    var myVideos: [VideoItem] { videos.filter { $0.channel == user.handle } }
    var myShorts: [Short] { shorts.filter { $0.channel == user.handle } }
    var savedVideos: [VideoItem] { videos.filter(\.saved) }
    var savedShorts: [Short] { shorts.filter(\.bookmarked) }

    init() {
        Self.purgeLegacyMockContentIfNeeded()
        guard AuthSession.shared.isAuthenticated else {
            // No real account tokens — any cached prototype session is obsolete.
            SessionStore.clear()
            bootstrapFreshSession()
            // Nobody is going to call connectBackend on this launch, so the
            // answer is in already: there is no backend. Screens that shimmer
            // while it's unknown would otherwise shimmer forever.
            backendResolved = true
            #if DEBUG
            // Headless E2E hook: `simctl launch` with SIMCTL_CHILD_GG_AUTOLOGIN_*.
            let env = ProcessInfo.processInfo.environment
            if let mail = env["GG_AUTOLOGIN_EMAIL"], let pass = env["GG_AUTOLOGIN_PASSWORD"] {
                email = mail
                authPassword = pass
                phase = .email
                submitEmailCredentials()
            }
            #endif
            return
        }
        if let cached = SessionStore.load() {
            applyCachedSession(cached)
        } else {
            phase = .app
            onboardingStep = 3
            bootstrapFreshSession()
        }
        email = AuthSession.shared.accountEmail ?? email
        Task { await connectBackend() }
    }

    /// One-time wipe so devices that still have cached mock feeds start clean.
    private static func purgeLegacyMockContentIfNeeded() {
        let key = "gojogo.purgedMockContent.v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        SessionStore.clear()
        UserDefaults.standard.set(true, forKey: key)
    }

    private func bootstrapFreshSession() {
        commentsByPost = [:]
        user.postCount = myPosts.count
    }

    private func applyCachedSession(_ cached: CachedSession) {
        email = cached.email
        user = cached.user.asDomain()
        interests = cached.interests.map { $0.asDomain() }
        stories = cached.stories.map { $0.asDomain() }
        posts = cached.posts.map {
            var p = $0.asDomain()
            p.videoURL = VideoLibrary.normalizeStored(p.videoURL)
            return p
        }
        videos = cached.videos.map {
            var v = $0.asDomain()
            v.videoURL = VideoLibrary.normalizeStored(v.videoURL)
            return v
        }
        shorts = cached.shorts.map {
            var s = $0.asDomain()
            s.videoURL = VideoLibrary.normalizeStored(s.videoURL)
            return s
        }
        products = cached.products.map { $0.asDomain() }
        featuredProduct = cached.featuredProduct.asDomain()
        people = cached.people.map { $0.asDomain() }
        profilePhotos = cached.profilePhotos
        savedPostIDs = Set(cached.savedPostIDs)
        commentsByPost = Dictionary(uniqueKeysWithValues:
            cached.comments.map { ($0.postID, $0.comments.map { $0.asDomain() }) })
        chatMessages = cached.chatMessages.map { $0.asDomain() }
        activeTab = {
            switch cached.activeTabRaw {
            case "watch": return .watch
            case "madeleine": return .madeleine
            case "travel": return .travel
            case "delivery": return .delivery
            case "economy": return .economy
            case "search": return .search
            default: return .home
            }
        }()
        watchSubFeed = WatchSubFeed(rawValue: cached.watchSubFeedRaw) ?? .feed
        if let raw = cached.navModeRaw, let mode = AppNavMode(rawValue: raw) {
            navMode = mode
        }
        if let raw = cached.appThemeRaw, let theme = AppTheme(rawValue: raw) {
            appTheme = theme
        }
        subscribedChannels = Set(cached.subscribedChannels ?? [])
        dislikedVideoIDs = Set(cached.dislikedVideoIDs ?? [])
        downloadedVideoIDs = Set(cached.downloadedVideoIDs ?? [])
        notifyHandles = Set(cached.notifyHandles ?? [])
        partnerRoles = Set((cached.partnerRoles ?? []).compactMap { PartnerRole(rawValue: $0) })
        partnerEarningsByRole = cached.partnerEarningsByRole ?? [:]
        partnerJobsByRole = cached.partnerJobsByRole ?? [:]
        profileHomeBlocks = cached.profileHomeBlocks ?? []
        dmThreads = (cached.dmThreads ?? [:]).mapValues { $0.map { $0.asDomain() } }
        phase = .app
        onboardingStep = 3
        topUpSeedContent()
        refreshSampleMediaFromSeed()
        // Warm the restored feed's media on launch so the first screenful is
        // decoded before the live refresh even returns — instant cold start.
        prefetchFeedImages(from: 0, count: 8)
        // Same for the user's own avatar: it's already on disk from the last
        // session, and promoting it into memory now is what stops Home drawing
        // the initial for a frame before the photo appears.
        prefetchOwnAvatar()
        // Rewrite durable relative video refs after migration.
        schedulePersist()
    }

    /// Older cached sessions predate newer seed content — append anything they're missing
    /// (matched by stable content keys, since seed UUIDs change per launch).
    private func topUpSeedContent() {
        let postKeys = Set(posts.map { "\($0.author)|\($0.text ?? "")" })
        for p in SampleData.posts where !postKeys.contains("\(p.author)|\(p.text ?? "")") {
            posts.append(p)
            commentsByPost[p.id] = SampleData.defaultComments
        }
        let videoKeys = Set(videos.map(\.title))
        for v in SampleData.videos where !videoKeys.contains(v.title) {
            videos.append(v)
        }
        let shortKeys = Set(shorts.map(\.caption))
        for s in SampleData.shorts where !shortKeys.contains(s.caption) {
            shorts.append(s)
        }
        let productKeys = Set(products.map(\.name) + [featuredProduct.name])
        for p in SampleData.products where !productKeys.contains(p.name) {
            products.append(p)
        }
        let peopleKeys = Set(people.map(\.name))
        for p in SampleData.people where !peopleKeys.contains(p.name) {
            people.append(p)
        }
        let storyKeys = Set(stories.map(\.name))
        for s in SampleData.stories where !storyKeys.contains(s.name) {
            stories.append(s)
        }
    }

    /// Repairs stale media refs in a restored session. The live Watch fetch is
    /// `refreshWatch()` in AppState+Watch.swift.
    func repairCachedMedia() {
        topUpSeedContent()
        refreshSampleMediaFromSeed()
        schedulePersist()
    }

    /// Strip leftover remote placeholder media from older caches.
    private func refreshSampleMediaFromSeed() {
        func isPlaceholder(_ url: String?) -> Bool {
            guard let url, !url.isEmpty else { return false }
            return url.contains("picsum.photos")
                || url.contains("images.unsplash.com")
                || url.hasPrefix("Sample")
                || url.hasPrefix("bundlevideo:")
        }

        for i in posts.indices {
            if isPlaceholder(posts[i].imageURL) { posts[i].imageURL = nil }
            if isPlaceholder(posts[i].avatarURL) { posts[i].avatarURL = nil }
            if let v = posts[i].videoURL {
                posts[i].videoURL = SampleData.repairedVideoURL(v)
                if isPlaceholder(posts[i].videoURL) { posts[i].videoURL = nil }
            }
            for j in posts[i].mediaItems.indices {
                if isPlaceholder(posts[i].mediaItems[j].imageURL) {
                    posts[i].mediaItems[j].imageURL = nil
                }
                if let v = posts[i].mediaItems[j].videoURL {
                    posts[i].mediaItems[j].videoURL = SampleData.repairedVideoURL(v)
                    if isPlaceholder(posts[i].mediaItems[j].videoURL) {
                        posts[i].mediaItems[j].videoURL = nil
                    }
                }
            }
        }

        for i in stories.indices {
            for j in stories[i].frames.indices where isPlaceholder(stories[i].frames[j].imageURL) {
                stories[i].frames[j].imageURL = nil
            }
        }

        for i in shorts.indices {
            if isPlaceholder(shorts[i].imageURL) { shorts[i].imageURL = nil }
            if let v = shorts[i].videoURL {
                shorts[i].videoURL = SampleData.repairedVideoURL(v)
                if isPlaceholder(shorts[i].videoURL) { shorts[i].videoURL = nil }
            }
        }

        for i in videos.indices {
            if isPlaceholder(videos[i].thumbURL) { videos[i].thumbURL = nil }
            if let v = videos[i].videoURL {
                videos[i].videoURL = SampleData.repairedVideoURL(v)
                if isPlaceholder(videos[i].videoURL) { videos[i].videoURL = nil }
            }
        }

        if isPlaceholder(featuredProduct.imageURL) { featuredProduct.imageURL = nil }
        for i in products.indices where isPlaceholder(products[i].imageURL) {
            products[i].imageURL = nil
        }

        if isPlaceholder(user.avatarURL) { user.avatarURL = nil }
        if isPlaceholder(tvHero.imageURL) { tvHero.imageURL = nil }
        for i in tvShows.indices where isPlaceholder(tvShows[i].imageURL) {
            tvShows[i].imageURL = nil
        }
        for i in people.indices where isPlaceholder(people[i].avatarURL) {
            people[i].avatarURL = nil
        }
        profilePhotos.removeAll { isPlaceholder($0) }
    }

    /// Writes the current connected session to disk.
    func persistSession() {
        guard phase == .app else { return }
        SessionStore.save(CachedSession(snapshotting: self))
    }

    /// Debounced save after mutations while connected.
    func schedulePersist() {
        guard phase == .app else { return }
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            persistSession()
        }
    }

    var commentingPost: Post? {
        guard let id = commentingPostID else { return nil }
        return posts.first(where: { $0.id == id })
    }

    var viewingPost: Post? {
        guard let id = viewingPostID else { return nil }
        return posts.first(where: { $0.id == id })
    }

    func openPostViewer(_ id: UUID) { viewingPostID = id }
    func closePostViewer() { viewingPostID = nil }

    // MARK: Appearance

    func toggleTheme() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.3)) {
            appTheme = appTheme == .dark ? .light : .dark
        }
        schedulePersist()
    }

    // MARK: Nav mode (My World ↔ Collections)

    func enterMyWorld() {
        closeComposer()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            navMode = .myWorld
            navBarExpanded = false
        }
        // Always shimmer on empty until the first fetch completes — don't wait
        // for backendConnected (that's what caused empty → shimmer → chats).
        if worldConversations.isEmpty && !worldConversationsLoaded {
            worldConversationsLoading = true
        }
        schedulePersist()
    }

    func enterCollections() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            navMode = .collections
        }
        schedulePersist()
    }

    func openWorldConversation(_ id: UUID) {
        // The list stays mounted under the thread now, search field and all, so
        // its keyboard would come along for the ride.
        Keyboard.dismiss()
        showWorldFilters = false
        // Carries the push-in transition, the mirror of `closeWorldConversation()`.
        withAnimation(.ggNav) {
            showWorldAppsMenu = false
            showWorldContact = false
            selectedWorldConversationID = id
        }
        PushRegistrar.shared.activeConversationID = id
        if let i = worldConversations.firstIndex(where: { $0.id == id }) {
            worldConversations[i].unread = 0
            // Local-first history (E2EE Phase A): the thread renders instantly
            // from the on-device archive; the fetch below reconciles on top.
            // Once the ratchet lands, the archive is the *only* copy of
            // anything already decrypted — the server's is a one-time delivery.
            if worldConversations[i].messages.isEmpty {
                let archived = WorldMessageArchive.shared.load(id)
                if !archived.isEmpty { worldConversations[i].messages = archived }
            }
        }
        loadLiveConversationIfNeeded(id)
    }

    func closeWorldConversation() {
        clearWorldNotice()
        // The navigation flip goes first and carries its own animation, the way
        // `closeWorldContact()` does. Leaving it to `.animation(value:)` on the
        // MyWorld stack meant the removal transition had to survive the twelve
        // other published mutations below landing in the same turn — it didn't,
        // and the thread disappeared in a single frame while opening it still
        // slid in properly.
        withAnimation(.ggNav) {
            selectedWorldConversationID = nil
            showWorldContact = false
            showWorldAppsMenu = false
        }
        PushRegistrar.shared.activeConversationID = nil
        worldDraft = ""
        worldPendingAttachments = []
        worldReactionTarget = nil
        worldReplyingTo = nil
        worldSendLaterLabel = nil
        worldSheet = nil
        showWorldPollOverlay = false
        showWorldSendLaterOverlay = false
        // Tearing down the audio session blocks the main thread for long enough
        // to eat the opening frames of that transition. Nobody is listening to a
        // thread they just closed — one turn later is soon enough.
        DispatchQueue.main.async { ChatAudioPlayer.shared.stop() }
    }

    /// Badge count — muted threads still show their own unread dot, but they
    /// don't drive the badge, which is the point of muting them.
    var worldUnreadCount: Int {
        worldConversations
            .filter { !worldMutedConversations.contains($0.id) }
            .reduce(0) { $0 + $1.unread }
    }

    var selectedWorldConversation: WorldConversation? {
        guard let id = selectedWorldConversationID else { return nil }
        return worldConversations.first(where: { $0.id == id })
    }

    var selectedWorldContact: WorldContact? {
        guard let convo = selectedWorldConversation,
              let cid = convo.contactID else { return nil }
        return worldContacts.first(where: { $0.id == cid })
    }

    /// Full-screen My World surfaces that hide the mode tab bar (setup / chat / contact).
    /// The first-run setup flow owns its own bottom CTA, so the dock and its bottom
    /// hit-testing shield must step aside or they cover "Get started".
    var isWorldImmersive: Bool {
        navMode == .myWorld && (needsWorldSetup || selectedWorldConversationID != nil || showWorldContact)
    }

    // MARK: My World — list filtering

    /// Conversations matching the search field + unread filter.
    /// Pinned first, then most recently active (send or receive).
    var worldFilteredConversations: [WorldConversation] {
        var list = worldConversations
        if worldFilterUnreadOnly { list = list.filter { $0.unread > 0 } }
        let q = worldSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q)
                    || $0.preview.lowercased().contains(q)
                    || $0.messages.contains { $0.kind == .text && $0.text.lowercased().contains(q) }
            }
        }
        return list.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            return a.lastActivityAt > b.lastActivityAt
        }
    }

    // MARK: My World — conversation management

    func togglePinWorldConversation(_ id: UUID) {
        guard let i = worldConversations.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            worldConversations[i].pinned.toggle()
        }
        // Persist it, or the next list refresh undoes the pin.
        let pinned = worldConversations[i].pinned
        guard MessagingStore.shared.isLive(id) else { return }
        Task { try? await MessagingStore.shared.setPinned(id, pinned: pinned) }
    }

    func toggleUnreadWorldConversation(_ id: UUID) {
        guard let i = worldConversations.firstIndex(where: { $0.id == id }) else { return }
        worldConversations[i].unread = worldConversations[i].unread > 0 ? 0 : 1
    }

    func deleteWorldConversation(_ id: UUID) {
        if worldTypingConversationID == id { worldTypingConversationID = nil }
        worldOlderCursor[id] = nil
        worldOlderPages[id] = nil
        worldPreviewSyncedAt[id] = nil
        if selectedWorldConversationID == id { closeWorldConversation() }
        showWorldContact = false
        let wasLive = MessagingStore.shared.isLive(id)
        withAnimation(.easeOut(duration: 0.25)) {
            worldConversations.removeAll { $0.id == id }
        }
        worldMutedConversations.remove(id)
        WorldPreference.mutedConversations = worldMutedConversations
        // Notes about individual messages in a thread that is going entirely —
        // the server prunes its own the same way, for the same reason.
        WorldPreference.clearDeletedMessages(in: id)
        clearWorldContextCardPreference(id)
        // A deleted thread's local history goes with it — including the opened
        // payloads, which are that history in its wire form.
        WorldMessageArchive.shared.remove(id)
        WorldEnvelopeVault.shared.remove(id)
        // …and so does its row, or the next launch draws it back from the cache
        // for as long as it takes the first fetch to answer.
        WorldConversationCache.shared.save(worldConversations)
        // A live thread deleted only on-device reappears on the next refresh.
        guard wasLive else { return }
        Task { [weak self] in
            do {
                try await MessagingStore.shared.leave(id)
            } catch {
                self?.showWorldNotice("Couldn't delete that conversation.")
                await self?.refreshWorldConversations()
            }
        }
    }

    // Removed 2026-08-02: `startWorldConversation(with:)` — it opened a thread
    // that existed only on this phone. Every way into a conversation now goes
    // through the server (`startLiveConversation`, `startLiveGroup`,
    // `openWorldCircle`), because a thread the server never heard of is one that
    // takes your messages and does nothing with them.

    /// Opens a thread with somebody reached by phone number.
    ///
    /// Number only, by design: GojoMessages is a phone-number graph, so a
    /// username is a name here and never a way to find somebody.
    ///
    /// Every outcome that isn't a real thread now **says why**. This used to
    /// fall through to a locally invented contact, which put you in a thread
    /// with a stranger who answered — canned replies, from a person who does not
    /// exist, on a number you may well have mistyped. Nothing is fabricated
    /// here any more: the person is on GojoMessages or you are told they aren't.
    func addWorldContact(_ raw: String) {
        let entry = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return }
        worldNewMessageError = nil
        guard backendConnected else {
            worldNewMessageError = "You're offline — GojoMessages needs a connection "
                + "to reach anybody."
            return
        }
        // Comma-separated phone numbers → a real backend group conversation.
        let recipients = entry.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if recipients.count >= 2 {
            Task {
                if await startLiveGroup(recipients: recipients) {
                    worldSheet = nil; showWorldFilters = false; worldSearch = ""
                } else {
                    worldNewMessageError = "At least two of those numbers need to be on "
                        + "GojoMessages to start a group."
                }
            }
            return
        }
        guard entry.allSatisfy({ "+0123456789 -()".contains($0) }) else {
            worldNewMessageError = "GojoMessages finds people by phone number — "
                + "a name or username won't reach anybody here."
            return
        }
        Task {
            if await startLiveConversation(phone: entry) {
                worldSheet = nil
                showWorldFilters = false
                worldSearch = ""
            } else {
                worldNewMessageError = "Nobody on GojoMessages has that number yet."
            }
        }
    }

    /// Opens the group thread for a circle, creating it if needed — always visible in Messages.
    /// A circle's thread is a real group conversation on the server, created on
    /// first open. It used to be assembled locally, which was survivable while a
    /// canned reply made every thread look alive — now a thread the server
    /// doesn't know about is one that silently swallows what you send, so there
    /// is no such thing here any more.
    func openWorldCircle(_ circle: WorldCircle) {
        if let existing = worldConversations.first(where: { $0.circleID == circle.id }) {
            if let i = worldConversations.firstIndex(where: { $0.id == existing.id }) {
                // Ensure it surfaces in the list (unpin so it shows in the main msgs rows).
                if worldConversations[i].pinned {
                    worldConversations[i].pinned = false
                }
                bumpWorldConversationActivity(at: i)
            }
            openWorldConversation(existing.id)
            return
        }
        guard backendConnected, !circle.memberIDs.isEmpty else {
            showWorldNotice(circle.memberIDs.isEmpty
                            ? "Add somebody to \(circle.name) first."
                            : "You're offline — that circle's chat needs a connection.")
            return
        }
        Task {
            do {
                let convo = try await MessagingStore.shared.createConversation(
                    participantIds: circle.memberIDs, title: circle.name,
                    circleId: circle.id, background: worldDefaultBackground)
                if worldConversations.firstIndex(where: { $0.id == convo.id }) == nil {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        worldConversations.insert(convo, at: 0)
                    }
                }
                openWorldConversation(convo.id)
            } catch {
                showWorldNotice("Couldn't open that circle's chat.")
            }
        }
    }

    // MARK: My World — sending

    func sendWorldMessage() {
        let text = worldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = worldPendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }

        if attachments.count >= 2 {
            let items = attachments.map {
                WorldCarouselItem(imageData: $0.imageData, isVideo: $0.isVideo,
                                  durationLabel: $0.durationLabel,
                                  localVideoURL: $0.videoURL)
            }
            let hasVideo = attachments.contains(where: \.isVideo)
            let preview = hasVideo
                ? "You: 🖼 \(attachments.count) items"
                : "You: 🖼 \(attachments.count) photos"
            deliverWorldMessage(
                WorldMessage(kind: .carousel, text: "", fromUser: true,
                             readLabel: "Delivered",
                             imageData: attachments.first?.imageData,
                             carouselItems: items),
                preview: preview)
            worldPendingAttachments = []
        } else if let att = attachments.first {
            deliverWorldMessage(
                WorldMessage(kind: att.isVideo ? .video : .photo, text: "",
                             fromUser: true, readLabel: "Delivered",
                             imageData: att.imageData, durationLabel: att.durationLabel,
                             localVideoURL: att.videoURL),
                preview: att.isVideo ? "You: 📹 Video" : "You: 📷 Photo")
            worldPendingAttachments = []
        }

        if !text.isEmpty {
            let isEmojiOnly = text.count <= 3 && text.unicodeScalars.allSatisfy { $0.properties.isEmoji }
            let scheduled = worldSendLaterLabel
            let msg = WorldMessage(kind: isEmojiOnly ? .emoji : .text, text: text,
                                   fromUser: true,
                                   readLabel: scheduled == nil ? "Delivered" : nil,
                                   replyTo: currentReplySnippet(),
                                   scheduledLabel: scheduled)
            let replyToId = worldReplyingTo   // capture before clearing (for live linking)
            let scheduledDate = scheduled != nil ? worldSendLaterDate : nil
            worldDraft = ""
            clearWorldReply()
            worldSendLaterLabel = nil
            deliverWorldMessage(msg, preview: "You: \(text)", scheduled: scheduled != nil,
                                replyToId: replyToId, scheduledAt: scheduledDate)
        }
    }

    /// Builds the quoted snippet for whatever message is being replied to.
    private func currentReplySnippet() -> WorldReplySnippet? {
        guard let rid = worldReplyingTo,
              let convo = selectedWorldConversation,
              let src = convo.messages.first(where: { $0.id == rid }) else { return nil }
        let author = src.fromUser ? "You" : (src.senderName ?? convo.title)
        return WorldReplySnippet(authorName: author,
                                 preview: src.snippetText,
                                 fromUser: src.fromUser)
    }

    func beginWorldReply(to id: UUID) {
        worldReactionTarget = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
            worldReplyingTo = id
        }
    }

    func clearWorldReply() {
        withAnimation(.easeOut(duration: 0.18)) { worldReplyingTo = nil }
    }

    func stageWorldAttachment(_ attachment: WorldPendingAttachment) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            worldPendingAttachments.append(attachment)
        }
    }

    func removeWorldAttachment(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            worldPendingAttachments.removeAll { $0.id == id }
        }
    }

    func sendWorldSticker(_ emoji: String) {
        deliverWorldMessage(
            WorldMessage(kind: .emoji, text: emoji, fromUser: true, readLabel: "Delivered"),
            preview: "You: \(emoji)")
    }

    /// A real iOS sticker picked from the system keyboard (PNG with alpha).
    func sendWorldSticker(imageData: Data) {
        deliverWorldMessage(
            WorldMessage(kind: .sticker, text: "", fromUser: true,
                         readLabel: "Delivered", imageData: imageData),
            preview: "You: 🩷 Sticker")
    }

    func sendWorldPhoto(_ data: Data) {
        deliverWorldMessage(
            WorldMessage(kind: .photo, text: "", fromUser: true,
                         readLabel: "Delivered", imageData: data),
            preview: "You: 📷 Photo")
    }

    /// Voice note recorded by holding the composer mic. The bubble plays from the
    /// local file straight away; the upload swaps in the CDN copy when it lands.
    func sendWorldAudio(url: URL, durationLabel: String) {
        deliverWorldMessage(
            WorldMessage(kind: .audio, text: "", fromUser: true,
                         readLabel: "Delivered", durationLabel: durationLabel,
                         localAudioURL: url),
            preview: "You: 🎤 Audio message")
    }

    /// Asks the device for a real fix (and a place name) before sending.
    func sendWorldLocation() {
        guard let target = selectedWorldConversationID else { return }
        showWorldAppsMenu = false
        showWorldNotice("Getting your location…", duration: 45)
        Task {
            do {
                let place = try await LiveLocationProvider.shared.currentPlace()
                clearWorldNotice()
                // The fix can take a moment — send it to the thread it was asked
                // for, even if the user has moved on to another one since.
                deliverWorldMessage(
                    WorldMessage(kind: .location, text: place.name,
                                 fromUser: true, readLabel: "Delivered",
                                 latitude: place.coordinate.latitude,
                                 longitude: place.coordinate.longitude),
                    preview: "You: 📍 \(place.name)", in: target)
            } catch LiveLocationProvider.LocationError.denied {
                showWorldNotice("Location is off for GojoGo — turn it on in Settings.")
            } catch {
                showWorldNotice("Couldn't get your location. Try again.")
            }
        }
    }

    /// Shows a transient line above the composer; auto-clears.
    func showWorldNotice(_ text: String, duration: TimeInterval = 3.5) {
        worldNoticeTask?.cancel()
        withAnimation(.ggSnappy) { worldNotice = text }
        worldNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.ggSnappy) { self?.worldNotice = nil }
        }
    }

    func clearWorldNotice() {
        worldNoticeTask?.cancel()
        worldNoticeTask = nil
        withAnimation(.ggSnappy) { worldNotice = nil }
    }

    /// Appends an outgoing message to the open thread and schedules the canned reply.
    /// When `scheduled` is true the bubble first appears in a pending state and is
    /// "sent" a few seconds later (demo stand-in for Send Later).
    func deliverWorldMessage(_ msg: WorldMessage, preview: String, scheduled: Bool = false,
                                     replyToId: UUID? = nil, scheduledAt: Date? = nil,
                                     in conversationID: UUID? = nil) {
        guard let id = conversationID ?? selectedWorldConversationID,
              let i = worldConversations.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
            worldConversations[i].messages.append(msg)
            if !scheduled { worldConversations[i].preview = preview }
        }
        bumpWorldConversationActivity(at: i)
        archiveWorldMessages(id)
        showWorldAppsMenu = false

        // Every thread is the server's now. A message that can't be sent isn't
        // pretended into existence — the bubble stays without a receipt rather
        // than being answered by nobody.
        if MessagingStore.shared.isLive(id) {
            liveSend(msg, in: id, replyToId: replyToId, scheduledAt: scheduled ? scheduledAt : nil)
        }
    }

    func setWorldSendLater(_ label: String?) {
        worldSendLaterLabel = label
    }

    // MARK: My World — tapbacks (reactions)

    func toggleWorldReaction(_ tapback: WorldTapback, on messageID: UUID) {
        guard let id = selectedWorldConversationID,
              let i = worldConversations.firstIndex(where: { $0.id == id }),
              let j = worldConversations[i].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
            var reactions = worldConversations[i].messages[j].reactions
            if let existing = reactions.firstIndex(where: { $0.fromUser && $0.tapback == tapback }) {
                reactions.remove(at: existing)          // same tapback → toggle off
            } else {
                reactions.removeAll { $0.fromUser }     // one tapback per person
                reactions.append(WorldReaction(tapback: tapback, fromUser: true))
            }
            worldConversations[i].messages[j].reactions = reactions
        }
        archiveWorldMessages(id)
        if MessagingStore.shared.isLive(id) {
            let mine = worldConversations[i].messages[j].reactions.first { $0.fromUser }
            liveReact(mine?.tapback, on: messageID, in: id)
        }
        worldReactionTarget = nil
    }

    func copyWorldMessage(_ messageID: UUID) {
        guard let convo = selectedWorldConversation,
              let msg = convo.messages.first(where: { $0.id == messageID }) else { return }
        UIPasteboard.general.string = msg.snippetText
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        worldReactionTarget = nil
    }

    /// Deletes one message from this account's copy of a thread.
    ///
    /// Taking it off the screen and out of the archive is only half of it, and on
    /// its own it does not hold: the message is still on the server, the thread
    /// re-fetches its newest page on every open and on a poll, and the bubble
    /// comes back. So the backend is told — it hides the message for this account
    /// alone — and a local note covers the window before it answers, or the case
    /// where it never does. Same shape as deleting a whole conversation, at
    /// message scale.
    ///
    /// Not an unsend: the other person keeps their copy. "Delete" lives in a menu
    /// beside Copy and Translate, which is a menu about your own screen.
    func deleteWorldMessage(_ messageID: UUID) {
        guard let id = selectedWorldConversationID,
              let i = worldConversations.firstIndex(where: { $0.id == id }) else { return }
        guard let deleted = worldConversations[i].messages.first(where: { $0.id == messageID })
        else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            worldConversations[i].messages.removeAll { $0.id == messageID }
        }
        archiveWorldMessages(id)
        worldReactionTarget = nil
        // A thread the server never heard of has nothing to tell it about.
        guard MessagingStore.shared.isLive(id) else { return }
        WorldPreference.markMessageDeleted(messageID, in: id)
        // A bubble still waiting for its echo is only known by the id this phone
        // invented for it, which the server cannot act on — a photo can be
        // uploading for long enough to make that a real thing to do. The note is
        // still taken; `applyIncomingMessage` carries it onto the real id the
        // moment the echo says what it is.
        guard deleted.sentAt != nil else { return }
        confirmWorldMessageDeletion(messageID, in: id)
    }

    /// Tells the backend about a deleted message and drops the local note once it
    /// has: from then on the message is filtered before it is ever sent, so
    /// keeping the note would only grow a set nothing reads. A failure leaves it
    /// in place, and the next reload — which will see the message still on the
    /// page — asks again.
    func confirmWorldMessageDeletion(_ messageID: UUID, in conversationID: UUID) {
        Task {
            do {
                try await MessagingStore.shared.deleteMessage(conversationID, message: messageID)
                WorldPreference.clearMessageDeleted(messageID, in: conversationID)
            } catch {
                // Left marked on purpose — the reload retry is the recovery.
            }
        }
    }

    // MARK: My World — polls

    func sendWorldPoll(question: String, options: [String]) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let opts = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { WorldPollOption(text: $0) }
        guard !q.isEmpty, opts.count >= 2 else { return }
        let poll = WorldPoll(question: q, options: opts)
        showWorldPollOverlay = false
        deliverWorldMessage(
            WorldMessage(kind: .poll, text: q, fromUser: true,
                         readLabel: "Delivered", poll: poll),
            preview: "You: 📊 \(q)")
    }

    func voteWorldPoll(messageID: UUID, optionID: UUID) {
        guard let id = selectedWorldConversationID,
              let i = worldConversations.firstIndex(where: { $0.id == id }),
              let j = worldConversations[i].messages.firstIndex(where: { $0.id == messageID }),
              var poll = worldConversations[i].messages[j].poll,
              let k = poll.options.firstIndex(where: { $0.id == optionID })
        else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            if poll.options[k].voters.contains("You") {
                poll.options[k].voters.removeAll { $0 == "You" }
            } else {
                if !poll.allowsMultiple {
                    for m in poll.options.indices { poll.options[m].voters.removeAll { $0 == "You" } }
                }
                poll.options[k].voters.append("You")
            }
            worldConversations[i].messages[j].poll = poll
        }
        if MessagingStore.shared.isLive(id) {
            liveVotePoll(messageID: messageID, optionID: optionID, in: id)
        }
    }

    func addWorldPollOption(messageID: UUID, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty,
              let id = selectedWorldConversationID,
              let i = worldConversations.firstIndex(where: { $0.id == id }),
              let j = worldConversations[i].messages.firstIndex(where: { $0.id == messageID }),
              var poll = worldConversations[i].messages[j].poll else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            poll.options.append(WorldPollOption(text: t))
            worldConversations[i].messages[j].poll = poll
        }
    }

    // MARK: My World — chat background

    /// Sets this thread's wallpaper and remembers it.
    ///
    /// It used to only set it, which meant the next conversation refresh — a
    /// foreground, a socket reconnect — replaced the row with the server's copy
    /// and the wallpaper reverted, having looked for all the world like it had
    /// been applied.
    func setWorldBackground(_ background: WorldChatBackground) {
        guard let convo = selectedWorldConversation,
              let i = worldConversations.firstIndex(where: { $0.id == convo.id }) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        WorldPreference.setBackground(background, for: convo.id)
        withAnimation(.easeInOut(duration: 0.3)) {
            worldConversations[i].background = background
        }
    }

    /// Picks a photo from the library as this thread's wallpaper. The image is
    /// downscaled and kept on the device — see `WorldWallpaperStore`.
    func setWorldBackgroundPhoto(_ data: Data) {
        guard let name = WorldWallpaperStore.save(data) else {
            showWorldNotice("Couldn't use that picture.")
            return
        }
        setWorldBackground(.photo(name))
    }

    /// Marks a thread as most recent so it floats to the top of the list.
    /// Also unpins so the thread always shows in the main Messages rows.
    private func bumpWorldConversationActivity(at index: Int) {
        guard worldConversations.indices.contains(index) else { return }
        worldConversations[index].timeAgo = "now"
        worldConversations[index].lastActivityAt = Date()
        worldConversations[index].pinned = false
    }

    // Removed 2026-08-02: `worldReplyPool` / `scheduleWorldReply` /
    // `receiveWorldReply` — the canned other side. A typing indicator, a random
    // reply and a read receipt, all invented locally on any thread the server
    // didn't own. It was the prototype's whole messaging illusion, and with
    // GojoMessages live it had become a liability: nobody could tell an invented
    // reply from a real one, and a mistyped number answered you like a friend.
    // Read receipts and typing now come from the socket or not at all.

    private func worldCircleMembers(of convo: WorldConversation) -> [UUID] {
        guard let cid = convo.circleID,
              let circle = worldCircles.first(where: { $0.id == cid }) else { return [] }
        return circle.memberIDs
    }

    /// Every image in a conversation — staged bytes *and* the ones that came down
    /// from the CDN, single photos, stickers and carousel slides alike.
    func worldChatPhotos(for convo: WorldConversation?) -> [WorldChatPhoto] {
        guard let convo else { return [] }
        var out: [WorldChatPhoto] = []
        for msg in convo.messages {
            switch msg.kind {
            case .photo, .video, .sticker:
                if msg.imageData != nil || msg.imageURL != nil {
                    out.append(WorldChatPhoto(messageID: msg.id, index: 0,
                                              data: msg.imageData, url: msg.imageURL,
                                              isVideo: msg.kind == .video))
                }
            case .carousel:
                for (i, item) in msg.carouselItems.enumerated() {
                    out.append(WorldChatPhoto(messageID: msg.id, index: i,
                                              data: item.imageData.isEmpty ? nil : item.imageData,
                                              url: item.imageURL, isVideo: item.isVideo))
                }
            default:
                break
            }
        }
        return out
    }

    /// Locations shared in a conversation, newest first.
    func worldChatLocations(for convo: WorldConversation?) -> [WorldMessage] {
        (convo?.messages ?? [])
            .filter { $0.kind == .location && $0.latitude != nil }
            .reversed()
    }

    /// Opens a chat attachment full screen.
    func openWorldMediaViewer(_ items: [ChatMediaItem], at index: Int) {
        guard !items.isEmpty else { return }
        ChatAudioPlayer.shared.stop()
        showWorldAppsMenu = false
        worldMediaViewerIndex = min(max(index, 0), items.count - 1)
        worldMediaViewerItems = items
    }

    func closeWorldMediaViewer() {
        withAnimation(.ggSnappy) {
            worldMediaViewerItems = []
            worldMediaViewerIndex = 0
        }
    }

    func openWorldContact() {
        showWorldAppsMenu = false
        withAnimation(.easeInOut(duration: 0.28)) { showWorldContact = true }
        if let id = selectedWorldConversationID { loadWorldContactProfile(for: id) }
    }

    func closeWorldContact() {
        withAnimation(.easeInOut(duration: 0.28)) { showWorldContact = false }
    }

    // MARK: Activity

    var unreadActivityCount: Int { notifications.filter { !$0.read }.count }

    func openActivity() {
        showActivity = true
        // Pull the latest activity when the sheet opens.
        if backendConnected { Task { await refreshNotifications() } }
    }

    func closeActivity() {
        showActivity = false
        markActivityRead()
    }

    func markActivityRead() {
        guard notifications.contains(where: { !$0.read }) else { return }
        for i in notifications.indices { notifications[i].read = true }
        // Persist read state so the badge stays cleared across launches/devices.
        if backendConnected {
            Task { try? await NotificationStore.shared.markAllRead() }
        }
    }

    func pushActivity(_ item: ActivityItem) {
        notifications.insert(item, at: 0)
    }

    /// Route a tapped notification to the right surface.
    func handleActivityTap(_ item: ActivityItem) {
        showActivity = false
        switch item.kind {
        case .follow:
            afterDismiss { $0.openUserProfile(handle: item.actor, avatarURL: item.avatarURL) }
        case .comment, .reply, .mention, .like:
            // Whatever it is about, if it's loaded. A tag in particular is
            // usually on someone else's post, so the old "open my newest post"
            // fallback would be the wrong thing every time.
            if let postID = item.postID, posts.contains(where: { $0.id == postID }) {
                afterDismiss { $0.openComments(for: postID) }
            } else if item.kind == .mention {
                afterDismiss { $0.openUserProfile(handle: item.actor, avatarURL: item.avatarURL) }
            } else if let post = myPosts.first {
                afterDismiss { $0.openComments(for: post.id) }
            }
        case .order:
            activeTab = .economy
        case .system:
            activeTab = .madeleine
        }
    }

    /// Lets the activity sheet finish closing before the next surface opens —
    /// two presentations in the same runloop turn and neither one shows.
    private func afterDismiss(_ action: @escaping (AppState) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            action(self)
        }
    }

    // MARK: Direct messages

    var dmChat: [ChatMessage] {
        guard let peer = dmPeer else { return [] }
        return dmThreads[peer.handle] ?? []
    }

    func openDirectMessage(handle: String, name: String? = nil,
                           avatarURL: String? = nil, avatarGradient: [Color]? = nil) {
        let cleaned = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        dmPeer = ProfileUser(
            name: name ?? cleaned,
            handle: cleaned,
            avatarURL: avatarURL,
            avatarGradient: avatarGradient ?? SampleData.g1,
            bio: "", category: "", postCount: 0,
            followerCount: 0, followingCount: 0,
            isOwn: false, following: false
        )
        dmDraft = ""
        if dmThreads[cleaned] == nil {
            dmThreads[cleaned] = [
                ChatMessage(text: "Hey \(user.name)! 👋", fromUser: false),
            ]
        }
    }

    func closeDirectMessage() {
        dmPeer = nil
        dmDraft = ""
    }

    func sendDirectMessage() {
        guard let peer = dmPeer else { return }
        let text = dmDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var thread = dmThreads[peer.handle] ?? []
        thread.append(ChatMessage(text: text, fromUser: true))
        dmThreads[peer.handle] = thread
        dmDraft = ""
        schedulePersist()

        let lower = text.lowercased()
        let reply: String
        if lower.contains("?") {
            reply = "Good question — let me check and get back to you tonight."
        } else if lower.contains("nice") || lower.contains("love") || lower.contains("great") {
            reply = "Appreciate it! Means a lot 🙏"
        } else if lower.contains("collab") || lower.contains("shoot") || lower.contains("project") {
            reply = "I'm in. Send me the details and let's lock a date."
        } else {
            reply = ["Haha for real.", "Yeah — was just thinking that.",
                     "Say less. 🔥", "On it. Give me a sec."].randomElement()!
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.8...1.6)) { [weak self] in
            guard let self, self.dmThreads[peer.handle] != nil else { return }
            self.dmThreads[peer.handle]?.append(ChatMessage(text: reply, fromUser: false))
            self.schedulePersist()
        }
    }

    // MARK: Channel subscriptions

    func isOwnChannel(_ channel: String) -> Bool {
        let key = channel.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        guard !key.isEmpty else { return false }
        // A business you own counts as you wherever the question is "is this
        // mine to manage" — the same rule the server enforces with
        // `ProfileApi.actsFor`. This one function gates the delete menus on
        // posts, videos and shorts, so a business's content is manageable
        // everywhere or nowhere.
        return key == user.handle.lowercased()
            || ownedBusinesses.contains { $0.handle.lowercased() == key }
    }

    func isSubscribed(_ channel: String) -> Bool {
        subscribedChannels.contains(channel.lowercased())
    }

    /// Subscribing to a channel *is* following its profile — one relationship,
    /// one number. Mirrors onto the feed and the backend the same way the
    /// profile Follow button does.
    func toggleSubscribe(_ channel: String) {
        let handle = channel.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let key = handle.lowercased()
        guard !isOwnChannel(handle) else { return }
        let subscribing = !subscribedChannels.contains(key)
        if subscribing {
            subscribedChannels.insert(key)
            user.followingCount += 1
        } else {
            subscribedChannels.remove(key)
            user.followingCount = max(0, user.followingCount - 1)
        }
        followerCountByHandle[key] = max(0, (followerCountByHandle[key] ?? 0) + (subscribing ? 1 : -1))
        for i in posts.indices where posts[i].author == handle || posts[i].author == "@\(handle)" {
            posts[i].following = subscribing
            posts[i].showFollow = !subscribing
        }
        for i in shorts.indices where shorts[i].channel.lowercased() == key {
            shorts[i].following = subscribing
        }
        if var p = profileUser, p.handle.lowercased() == key {
            p.following = subscribing
            p.followerCount = max(0, p.followerCount + (subscribing ? 1 : -1))
            profileUser = p
        }
        syncProfileFollow(handle: handle, following: subscribing)
        schedulePersist()
    }

    /// Subscribers *are* followers. Your own channel reads the live follower
    /// count; another channel reads whatever their profile last reported. When
    /// nothing real is known the caller gets nil and shows no number at all
    /// rather than an invented one.
    func subscriberLabel(for channel: String) -> String? {
        guard let count = followerCount(forChannel: channel) else { return nil }
        return count == 1 ? "1 subscriber" : "\(formatCount(count)) subscribers"
    }

    func followerCount(forChannel channel: String) -> Int? {
        if isOwnChannel(channel) { return user.followerCount }
        let key = channel.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        if let p = profileUser, p.handle.lowercased() == key, !p.isOwn { return p.followerCount }
        return followerCountByHandle[key]
    }

    // MARK: Video / short views

    /// Counts this viewer. Deduped per run so re-mounting a card can't move the
    /// optimistic number; the server dedupes permanently, one row per viewer,
    /// and the next fetch replaces the optimistic count with that truth.
    func registerVideoView(_ id: UUID) {
        guard !countedViewIDs.contains(id),
              let i = videos.firstIndex(where: { $0.id == id }) else { return }
        countedViewIDs.insert(id)
        videos[i].views += 1
        syncVideoView(id)
        schedulePersist()
    }

    func registerShortView(_ id: UUID) {
        guard !countedViewIDs.contains(id),
              let i = shorts.firstIndex(where: { $0.id == id }) else { return }
        countedViewIDs.insert(id)
        shorts[i].views += 1
        syncVideoView(id)
        schedulePersist()
    }

    // MARK: Deleting your own videos

    /// Ask for confirmation. Deferred a beat so the menu that triggered it is
    /// gone before the dialog tries to present.
    func requestDeleteVideo(_ id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pendingVideoDelete = id
        }
    }

    func requestDeleteShort(_ id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pendingShortDelete = id
        }
    }

    func requestDeletePost(_ id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pendingPostDelete = id
        }
    }

    func canDeleteVideo(_ id: UUID) -> Bool {
        videos.first(where: { $0.id == id }).map { isOwnChannel($0.channel) } ?? false
    }

    func canDeleteShort(_ id: UUID) -> Bool {
        shorts.first(where: { $0.id == id }).map { isOwnChannel($0.channel) } ?? false
    }

    /// Removes a long-form video and everything derived from it: the local
    /// movie file, its comments, and any download / dislike state.
    func deleteVideo(_ id: UUID) {
        guard let video = videos.first(where: { $0.id == id }) else { return }
        if watchingVideoID == id { closeWatching() }
        if commentingPostID == id { closeComments() }
        if isOwnChannel(video.channel), !isVideoURLShared(video.videoURL, excluding: id) {
            VideoLibrary.remove(video.videoURL)
        }
        syncVideoDelete(id)
        videos.removeAll { $0.id == id }
        dislikedVideoIDs.remove(id)
        downloadedVideoIDs.remove(id)
        commentsByPost[id] = nil
        countedViewIDs.remove(id)
        editingVideoID = nil
        schedulePersist()
    }

    func deleteShort(_ id: UUID) {
        guard let short = shorts.first(where: { $0.id == id }) else { return }
        if commentingPostID == id { closeComments() }
        if focusedShortID == id { focusedShortID = nil }
        if isOwnChannel(short.channel), !isVideoURLShared(short.videoURL, excluding: id) {
            VideoLibrary.remove(short.videoURL)
        }
        syncVideoDelete(id)
        shorts.removeAll { $0.id == id }
        commentsByPost[id] = nil
        countedViewIDs.remove(id)
        schedulePersist()
    }

    /// A feed post opened in Shorts shares its movie file with the post — don't
    /// delete the file out from under whatever else still points at it.
    private func isVideoURLShared(_ url: String?, excluding id: UUID) -> Bool {
        guard let url, !url.isEmpty else { return false }
        if posts.contains(where: { $0.videoURL == url
            || $0.mediaItems.contains(where: { $0.videoURL == url }) }) { return true }
        if videos.contains(where: { $0.id != id && $0.videoURL == url }) { return true }
        if shorts.contains(where: { $0.id != id && $0.videoURL == url }) { return true }
        return false
    }

    // MARK: Long-form details

    /// Applies the details sheet to a published video.
    func updateVideoDetails(_ id: UUID, title: String, details: String, thumbData: Data?) {
        guard let i = videos.firstIndex(where: { $0.id == id }) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        videos[i].title = cleanTitle.isEmpty ? videos[i].title : cleanTitle
        videos[i].details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if let thumbData {
            videos[i].thumbData = thumbData
            videos[i].thumbURL = nil
        }
        syncVideoDetails(id, title: videos[i].title, details: videos[i].details, thumbData: thumbData)
        schedulePersist()
    }

    // MARK: Author identity on videos

    /// The avatar to show next to a handle. Never the media's own poster —
    /// falls back to the letter-and-gradient avatar when we know of no picture.
    func avatarURL(forHandle handle: String) -> String? {
        if isOwnChannel(handle) { return user.avatarURL }
        let key = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        if let p = profileUser, p.handle.lowercased() == key, let url = p.avatarURL { return url }
        if let post = posts.first(where: {
            $0.author.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased() == key
        }), let url = post.avatarURL { return url }
        return nil
    }

    /// Avatar for a video or short: your own always tracks the live profile
    /// picture (so changing it updates everything you posted), anyone else's
    /// uses what was stored with the item and falls back to a lookup.
    func authorAvatarURL(forChannel channel: String, stored: String?) -> String? {
        if isOwnChannel(channel) { return user.avatarURL ?? stored }
        return stored ?? avatarURL(forHandle: channel)
    }

    func avatarGradient(forHandle handle: String) -> [Color] {
        if isOwnChannel(handle) { return user.avatarGradient }
        let key = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        if let post = posts.first(where: {
            $0.author.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased() == key
        }) { return post.avatarGradient }
        return SocialStore.gradient(for: key)
    }

    // MARK: Video reactions

    func isVideoDisliked(_ id: UUID) -> Bool { dislikedVideoIDs.contains(id) }

    func toggleVideoDislike(_ id: UUID) {
        if dislikedVideoIDs.contains(id) {
            dislikedVideoIDs.remove(id)
        } else {
            dislikedVideoIDs.insert(id)
            // Disliking clears a like, YouTube-style.
            if let i = videos.firstIndex(where: { $0.id == id }), videos[i].liked {
                videos[i].liked = false
                videos[i].likes = max(0, videos[i].likes - 1)
            }
        }
        schedulePersist()
    }

    func isVideoDownloaded(_ id: UUID) -> Bool { downloadedVideoIDs.contains(id) }

    func toggleVideoDownload(_ id: UUID) {
        if downloadedVideoIDs.contains(id) { downloadedVideoIDs.remove(id) }
        else { downloadedVideoIDs.insert(id) }
        schedulePersist()
    }

    func reportVideo(_ id: UUID) {
        if watchingVideoID == id { closeWatching() }
        videos.removeAll { $0.id == id }
        dislikedVideoIDs.remove(id)
        downloadedVideoIDs.remove(id)
        schedulePersist()
    }

    func videoShareURL(for id: UUID) -> URL {
        URL(string: "https://gojogo.app/w/\(id.uuidString.lowercased())")!
    }

    func shortShareURL(for id: UUID) -> URL {
        URL(string: "https://gojogo.app/s/\(id.uuidString.lowercased())")!
    }

    // MARK: Profile

    func toggleNotify(handle: String) {
        let key = handle.lowercased()
        if notifyHandles.contains(key) { notifyHandles.remove(key) }
        else { notifyHandles.insert(key) }
        schedulePersist()
    }

    func updateProfile(name: String, bio: String, category: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty { user.name = cleanName }
        user.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        user.category = category
        if profileUser?.isOwn == true {
            profileUser = .own(from: user, posts: myPosts.count)
        }
        // Persist to the backend (was local-only before).
        if backendConnected {
            let body = UpdateProfileBody(
                displayName: cleanName.isEmpty ? nil : cleanName,
                handle: nil, bio: user.bio, category: category,
                birthYear: nil, avatarUrl: nil, interests: nil)
            Task {
                if let profile = try? await ProfileStore.shared.updateMe(body) {
                    applyProfile(profile)
                    SocialStore.shared.myHandle = profile.handle
                }
            }
        }
        schedulePersist()
    }

    // MARK: Profile Home (customizable canvas)

    /// Generates a unique starter layout the first time the Home tab is opened.
    func seedProfileHomeIfNeeded() {
        guard profileHomeBlocks.isEmpty else { return }
        profileHomeBlocks = SampleData.randomProfileHome(handle: user.handle, posts: myPosts)
        schedulePersist()
    }

    /// Random Home layouts generated for *other* users' profiles, keyed by handle.
    /// Not persisted — regenerated per session, stable while browsing.
    @Published var otherProfileHomes: [String: [ProfileHomeBlock]] = [:]

    /// Generates (once) a Home layout for another user's profile.
    func ensureOtherProfileHome(handle: String, posts: [Post]) {
        let key = handle.lowercased()
        guard otherProfileHomes[key] == nil else { return }
        otherProfileHomes[key] = SampleData.randomProfileHome(handle: handle, posts: posts)
    }

    func otherProfileHome(_ handle: String) -> [ProfileHomeBlock] {
        otherProfileHomes[handle.lowercased()] ?? []
    }

    /// Discards the current Home and rolls a fresh random layout.
    func shuffleProfileHome() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            profileHomeBlocks = SampleData.randomProfileHome(handle: user.handle, posts: myPosts)
        }
        schedulePersist()
    }

    var editingHomeBlock: ProfileHomeBlock? {
        guard let id = editingHomeBlockID else { return nil }
        return profileHomeBlocks.first(where: { $0.id == id })
    }

    func toggleProfileHomeEditing() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            profileHomeEditing.toggle()
        }
    }

    /// Adds a new block of the given kind and immediately opens its editor.
    func addHomeBlock(_ kind: ProfileHomeBlockKind) {
        var block = ProfileHomeBlock(kind: kind)
        switch kind {
        case .heading:  block.title = "New heading"; block.style = .plain
        case .banner:   block.title = ""
        case .text:     block.text = ""
        case .featured: block.title = "Featured"
        case .media:    block.title = "Photos & video"; block.columns = 3
        case .gallery:  block.title = "Gallery"; block.columns = 3
        case .link:     block.title = "Visit"; block.url = "https://"; block.style = .accent
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            profileHomeBlocks.append(block)
        }
        showHomeBlockPicker = false
        // Let the picker sheet finish dismissing before presenting the editor,
        // so the two sheets don't collide.
        let id = block.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.editingHomeBlockID = id
        }
        schedulePersist()
    }

    func updateHomeBlock(_ block: ProfileHomeBlock) {
        guard let i = profileHomeBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        profileHomeBlocks[i] = block
        schedulePersist()
    }

    func deleteHomeBlock(_ id: UUID) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            profileHomeBlocks.removeAll { $0.id == id }
        }
        if editingHomeBlockID == id { editingHomeBlockID = nil }
        schedulePersist()
    }

    /// Moves a block up (-1) or down (+1) in the stack.
    func moveHomeBlock(_ id: UUID, by offset: Int) {
        guard let i = profileHomeBlocks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard profileHomeBlocks.indices.contains(j) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            profileHomeBlocks.swapAt(i, j)
        }
        schedulePersist()
    }

    /// Posts referenced by a block, in stored order (skips any that were deleted).
    func homeBlockPosts(_ block: ProfileHomeBlock) -> [Post] {
        block.postIDs.compactMap { id in posts.first(where: { $0.id == id }) }
    }

    /// Everything GojoMessages holds about whoever is signed in.
    ///
    /// A private network is exactly the kind of thing that must not be waiting
    /// for the next person to open the app on this phone — the block list and
    /// the emergency contacts below already say so, and threads, their previews
    /// and a contacts graph are more personal than either. It survived until
    /// 2026-08-02 because the demo seeds made leftovers look like fixtures;
    /// with every thread real, a leftover is somebody's actual conversation.
    ///
    /// Sign-out is the only caller today. If a second way to switch accounts
    /// ever appears, it belongs here too.
    private func clearGojoMessages() {
        worldConversations = []
        worldOlderCursor = [:]
        worldOlderPages = [:]
        worldPreviewSyncedAt = [:]
        worldContacts = []
        worldCircles = []
        worldGraphContacts = []
        worldGraphLoaded = false
        worldFeedPosts = []
        worldStories = []
        worldRichProfile = WorldRichProfile()
        worldAliases = [:]
        // Muting is a device preference rather than account state, but the ids
        // in it name the last account's threads — written through, or the next
        // launch reads them back.
        worldMutedConversations = []
        WorldPreference.mutedConversations = []
        selectedWorldConversationID = nil
        worldContactProfile = nil
        openWorldStory = nil
        worldSheet = nil
        showWorldContact = false
        worldDraft = ""
        worldSearch = ""
        worldPendingAttachments = []
        worldReplyingTo = nil
        worldReactionTarget = nil
        worldTypingConversationID = nil
        worldMediaViewerItems = []
        worldNewMessageError = nil
        worldNotice = nil
        worldFeedLoading = false
        worldFeedLoaded = false
        worldSetupComplete = false
        worldSetupLoaded = false
        worldConversationsLoading = true
        worldConversationsLoaded = false
        worldSetupStep = .intro
        worldSetupPhone = ""; worldSetupCode = ""; worldSetupName = ""
        worldSetupAvatarData = nil; worldSetupAvatarURL = nil; worldPhone = nil
        worldSettingsName = ""; worldSettingsAvatarData = nil
        worldSettingsError = nil; worldSettingsSaved = false
    }

    func signOut() {
        persistTask?.cancel()
        travelMatchTask?.cancel()
        partnerOfferTask?.cancel()
        partnerJobTask?.cancel()
        SessionStore.clear()
        AuthSession.shared.clear()
        // The message archive is the account's plaintext history — it must not
        // outlive the account on a shared device. The envelope vault holds the
        // same plaintext at the wire boundary, and the signal store holds the
        // ratchets and the published-keys flag: left behind, the next account
        // on this device would be told its keys were already published and
        // would never appear in the directory at all.
        WorldMessageArchive.shared.wipe()
        // The thread list carries the last line of every conversation, which is
        // the same plaintext in shorter form.
        WorldConversationCache.shared.wipe()
        WorldEnvelopeVault.shared.wipe()
        WorldSignalStore.shared.wipe()
        // Phase D: these open the account's photos and voice notes.
        WorldMediaKeyStore.shared.wipe()
        // Phase E: one account's "I checked this is them" says nothing about
        // the next account's contacts, and the downgrade mark is per-identity.
        WorldVerificationStore.shared.wipe()
        WorldSignalSession.forgetSealedPeers()
        // Phase G: the notification extension reads the signed-in profile id
        // from the shared suite. Left behind, it would keep decrypting the
        // departed account's pushes into banners on this device. (The store's
        // own `reset()` below clears it too, via `myProfileId`'s didSet — this
        // is the belt to that pair of braces, because the consequence of one of
        // them being reordered away is an account's messages on a stranger's
        // lock screen.)
        WorldAppGroup.clearAccountState()
        SocialStore.shared.reset()
        StoriesStore.shared.reset()
        WatchStore.shared.reset()
        MusicStore.shared.reset()
        ProfileStore.shared.reset()
        EconomyStore.shared.reset()
        DeliveryStore.shared.reset()
        showSellerHub = false
        sellerListings = []
        sellerStats = nil
        editingListing = nil
        economySeededListingIDs = []
        economyNextBefore = nil
        economyNoticeTask?.cancel()
        economyNotice = nil
        // Phase 5: two catalogs, two consoles and a basket, none of which the
        // next person to sign in on this device is entitled to see. The basket
        // most of all — it is the only one that could turn into somebody else's
        // order.
        economySegment = .marketplace
        shopProducts = []
        shopNextBefore = nil
        shopCategory = "All"
        browsingShopProduct = nil
        shopProductReviews = []
        shopBasket = []
        showShopCheckout = false
        shopOrders = []
        showShopOrders = false
        entitlements = []
        services = []
        servicesNextBefore = nil
        serviceCategory = "All"
        browsingService = nil
        serviceSlots = nil
        serviceReviews = []
        bookings = []
        showBookings = false
        isSeller = false
        isServiceProvider = false
        showSellerConsole = false
        showProviderConsole = false
        myShopId = nil
        myProviderId = nil
        myShop = nil
        myShopProducts = []
        shopOrderQueue = []
        shopPromotions = []
        shopWallet = nil
        myProvider = nil
        myServices = []
        providerBookings = []
        providerAvailability = []
        providerExceptions = []
        providerDocuments = []
        providerWallet = nil
        transfers = []
        showTransfers = false
        openTransferID = nil
        transferDocuments = []
        deliveryPollTask?.cancel()
        deliveryLiveOrderID = nil
        deliveryNoticeTask?.cancel()
        deliveryNotice = nil
        deliveryAddresses = []
        selectedDeliveryAddressID = nil
        merchantNoticeTask?.cancel()
        merchantNotice = nil
        merchantAccount = nil
        merchantStorefront = nil
        showMerchantPartner = false
        businessNoticeTask?.cancel()
        businessNotice = nil
        ownedBusinesses = []
        showBusinessProfiles = false
        // Trust & safety: the block list is per-account, so it must not survive
        // into the next person who signs in on this device.
        blockedAccounts = []
        showBlockedAccounts = false
        showDeleteAccount = false
        pendingBlock = nil
        reportTarget = nil
        reportSubmitted = false
        reportNotice = nil
        safetyNotice = nil
        deletionStatus = nil
        // The safety pack is as personal as the block list: an emergency
        // contact list left behind on a shared device is somebody else's
        // mother's phone number.
        emergencyContacts = []
        showEmergencyContacts = false
        tripShare = nil
        sos = nil
        confirmingSos = false
        verificationInvites = []
        openVerification = nil
        stopActingAsBusiness()
        WorldSocket.shared.disconnect()
        MessagingStore.shared.reset()
        PushRegistrar.shared.reset()
        clearGojoMessages()
        backendConnected = false
        backendResolved = false
        pendingOnboarding = false
        authPassword = ""
        authCode = ""
        authError = nil
        emailAuthStep = .credentials

        partnerRoles = []
        partnerOnboardingRole = nil
        partnerDashboardRole = nil
        partnerOnline = false
        partnerJob = nil
        partnerJobPhase = .idle
        partnerEarningsByRole = [:]
        partnerJobsByRole = [:]
        partnerRatingByRole = [:]

        profileHomeBlocks = []
        otherProfileHomes = [:]
        profileHomeEditing = false
        editingHomeBlockID = nil
        showHomeBlockPicker = false

        showProfile = false
        profileUser = nil
        showActivity = false
        showEditProfile = false
        viewingPostID = nil
        commentingPostID = nil
        dmPeer = nil
        dmThreads = [:]

        email = ""
        user = GGUser()
        interests = SampleData.interests
        stories = SampleData.stories
        posts = SampleData.posts
        videos = SampleData.videos
        shorts = SampleData.shorts
        products = SampleData.products
        featuredProduct = SampleData.featuredProduct
        people = SampleData.people
        profilePhotos = SampleData.profileGridURLs
        savedPostIDs = []
        commentsByPost = [:]
        chatMessages = []
        notifications = SampleData.notifications
        subscribedChannels = []
        dislikedVideoIDs = []
        downloadedVideoIDs = []
        notifyHandles = []
        tvShows = SampleData.tvShows
        tvHero = SampleData.tvHero
        activeTab = .home
        watchSubFeed = .feed
        travelPhase = .home
        onboardingStep = 1
        bootstrapFreshSession()

        withAnimation(.easeInOut(duration: 0.45)) { phase = .welcome }
    }

    var watchingVideo: VideoItem? {
        guard let id = watchingVideoID else { return nil }
        return videos.first(where: { $0.id == id })
    }

    // MARK: Onboarding

    func toggleInterest(_ id: UUID) {
        guard let i = interests.firstIndex(where: { $0.id == id }) else { return }
        interests[i].selected.toggle()
    }

    func finishOnboarding() {
        if user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !user.handle.isEmpty {
            user.name = user.handle
        }
        user.interests = interests.filter(\.selected).map(\.title)
        remapOwnContentToCurrentHandle()
        user.postCount = myPosts.count
        withAnimation(.easeInOut(duration: 0.5)) { phase = .app }
        pendingOnboarding = false
        syncOnboardingProfile()
        persistSession()
    }

    private func remapOwnContentToCurrentHandle() {
        let seedTexts: Set<String> = [
            "First frames on gojogo — more coming.",
            "Studio light tests. Saving the ones that stay.",
            "Building in public. Notes later.",
        ]
        for i in posts.indices {
            guard let text = posts[i].text, seedTexts.contains(text) else { continue }
            let old = posts[i]
            posts[i] = Post(
                id: old.id,
                author: user.handle,
                meta: old.meta,
                avatarGradient: user.avatarGradient,
                avatarURL: user.avatarURL,
                imageURL: old.imageURL,
                imageData: old.imageData,
                videoURL: old.videoURL,
                imageAspect: old.imageAspect,
                text: old.text,
                bookmarked: old.bookmarked,
                likeCount: old.likeCount,
                commentCount: old.commentCount
            )
        }
    }

    func advanceOnboarding() {
        if onboardingStep < 3 {
            withAnimation(.easeInOut(duration: 0.35)) { onboardingStep += 1 }
        } else {
            finishOnboarding()
        }
    }

    // MARK: Posts

    func toggleLike(_ id: UUID) {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[i].liked.toggle()
        posts[i].likeCount += posts[i].liked ? 1 : -1
        syncLike(postID: id, liked: posts[i].liked)
        schedulePersist()
    }

    /// Like only (Instagram double-tap) — no-ops if already liked. Returns whether newly liked.
    @discardableResult
    func likePost(_ id: UUID) -> Bool {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return false }
        guard !posts[i].liked else { return false }
        posts[i].liked = true
        posts[i].likeCount += 1
        syncLike(postID: id, liked: true)
        schedulePersist()
        return true
    }

    func toggleFeedVideoMute() {
        feedVideosMuted.toggle()
        // Home cards pick this up via `isMuted` — do not touch Shorts players.
    }

    func toggleShortsMute() {
        shortsMuted.toggle()
    }

    func toggleBookmark(_ id: UUID) {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[i].bookmarked.toggle()
        if posts[i].bookmarked { savedPostIDs.insert(id) }
        else { savedPostIDs.remove(id) }
        syncBookmark(postID: id, bookmarked: posts[i].bookmarked)
        schedulePersist()
    }

    func toggleFollow(postID: UUID) {
        guard let i = posts.firstIndex(where: { $0.id == postID }) else { return }
        posts[i].following.toggle()
        user.followingCount += posts[i].following ? 1 : -1
        let following = posts[i].following
        let author = posts[i].author
        // Mirror across every post by the same author.
        for j in posts.indices where posts[j].author == author {
            posts[j].following = following
            posts[j].showFollow = !following
        }
        syncFollow(postID: postID, following: following)
        schedulePersist()
    }

    /// Removes a post from *this* device's feed. Someone else's post is only
    /// ever hidden — deleting it is `deleteMyPost`, and the server enforces the
    /// same rule.
    func hidePost(_ id: UUID) {
        posts.removeAll { $0.id == id }
        savedPostIDs.remove(id)
        schedulePersist()
    }

    func isMyPost(_ id: UUID) -> Bool {
        guard let post = posts.first(where: { $0.id == id }) else { return false }
        return isOwnChannel(post.author)
    }

    /// Deletes your own post for everyone. The optimistic removal is reverted
    /// if the server refuses, so the feed never shows a post that still exists.
    func deleteMyPost(_ id: UUID) {
        guard let index = posts.firstIndex(where: { $0.id == id }),
              isOwnChannel(posts[index].author) else { return }
        let removed = posts[index]
        posts.remove(at: index)
        savedPostIDs.remove(id)
        commentsByPost[id] = nil
        if viewingPostID == id { closePostViewer() }
        if commentingPostID == id { closeComments() }
        // A voice post that keeps playing after its row is gone sounds like the
        // delete didn't take.
        if ChatAudioPlayer.shared.loadedID == id { ChatAudioPlayer.shared.stop() }
        user.postCount = max(0, user.postCount - 1)
        if profileUser?.isOwn == true {
            profileUser?.postCount = max(0, (profileUser?.postCount ?? 1) - 1)
        }
        schedulePersist()
        syncDeletePost(id, restoring: removed, at: index)
    }

    func postShareURL(for id: UUID) -> URL {
        URL(string: "https://gojogo.app/p/\(id.uuidString.lowercased())")!
    }

    /// True when this id addresses a video/short rather than a feed post — the
    /// two live in different modules, so every comment call has to pick one.
    func isVideoThread(_ id: UUID) -> Bool {
        WatchStore.shared.isLive(id)
            || videos.contains(where: { $0.id == id })
            || shorts.contains(where: { $0.id == id })
    }

    func openComments(for postID: UUID) {
        // One drawer under the player — Madeleine yields to comments.
        if showWatching, watchingWithMadeleine {
            watchingWithMadeleine = false
        }
        commentingPostID = postID
        draftComment = ""
        cancelReply()
        expandedCommentIDs = []
        if isVideoThread(postID) {
            if commentsByPost[postID] == nil { commentsByPost[postID] = [] }
            if WatchStore.shared.isLive(postID) { refreshVideoComments(for: postID) }
        } else if SocialStore.shared.remotePostIds.contains(postID) {
            if commentsByPost[postID] == nil { commentsByPost[postID] = [] }
            refreshComments(for: postID)
        } else if commentsByPost[postID] == nil {
            commentsByPost[postID] = SampleData.defaultComments
        }
    }

    func closeComments() {
        commentingPostID = nil
        draftComment = ""
        cancelReply()
        expandedCommentIDs = []
    }

    // MARK: Replies

    /// Aims the draft at `comment`. The `@handle` prefix is the reply's own
    /// record of who it answers — threads are flat, so nothing else carries it.
    func beginReply(to comment: Comment) {
        replyingToCommentID = comment.id
        replyingToHandle = comment.author
        let handle = comment.author.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if !handle.isEmpty, handle.lowercased() != user.handle.lowercased() {
            draftComment = "@\(handle) "
        }
        if let parent = threadRoot(of: comment.id) {
            expandedCommentIDs.insert(parent)
        }
    }

    func cancelReply() {
        replyingToCommentID = nil
        replyingToHandle = nil
    }

    func toggleRepliesExpanded(_ commentID: UUID) {
        if expandedCommentIDs.contains(commentID) {
            expandedCommentIDs.remove(commentID)
        } else {
            expandedCommentIDs.insert(commentID)
            // A thread whose replies the server hasn't sent yet — ask for them.
            if let postID = commentingPostID, !isVideoThread(postID),
               let root = comment(commentID, in: postID),
               root.replies.count < root.replyCount {
                refreshReplies(postID: postID, commentID: commentID)
            }
        }
    }

    func addComment() {
        guard let id = commentingPostID else { return }
        let text = draftComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Video threads live in the watch module, which has no reply table —
        // the sheet hides the affordance there, and this is the belt to that
        // braces.
        let parentID = isVideoThread(id) ? nil : replyingToCommentID
        let comment = Comment(author: user.handle, text: text,
                              avatarURL: user.avatarURL, timeAgo: "now",
                              parentID: parentID.flatMap { threadRoot(of: $0) },
                              mentions: MentionParser.resolveLocally(in: text))
        var list = commentsByPost[id] ?? []
        if let parentID, let root = threadRoot(of: parentID),
           let i = list.firstIndex(where: { $0.id == root }) {
            list[i].replies.append(comment)
            list[i].replyCount = max(list[i].replyCount + 1, list[i].replies.count)
            expandedCommentIDs.insert(root)
        } else {
            list.insert(comment, at: 0)
        }
        commentsByPost[id] = list
        applyCommentCount(Self.totalComments(list), to: id)
        draftComment = ""
        if isVideoThread(id) {
            syncNewVideoComment(text: text, videoID: id, optimisticID: comment.id)
        } else {
            syncNewComment(text: text, postID: id, parentID: parentID,
                           optimisticID: comment.id)
        }
        cancelReply()
        schedulePersist()
    }

    func toggleCommentLike(postID: UUID, commentID: UUID) {
        guard var list = commentsByPost[postID] else { return }
        var liked = false
        if let i = list.firstIndex(where: { $0.id == commentID }) {
            list[i].liked.toggle()
            list[i].likeCount += list[i].liked ? 1 : -1
            liked = list[i].liked
        } else if let (root, reply) = indexOfReply(commentID, in: list) {
            list[root].replies[reply].liked.toggle()
            list[root].replies[reply].likeCount += list[root].replies[reply].liked ? 1 : -1
            liked = list[root].replies[reply].liked
        } else {
            return
        }
        commentsByPost[postID] = list
        if isVideoThread(postID) {
            syncVideoCommentLike(commentID: commentID, liked: liked)
        } else {
            syncCommentLike(commentID: commentID, liked: liked)
        }
        schedulePersist()
    }

    // MARK: Thread helpers

    /// A comment anywhere in the post's thread, top level or reply.
    func comment(_ commentID: UUID, in postID: UUID) -> Comment? {
        guard let list = commentsByPost[postID] else { return nil }
        if let found = list.first(where: { $0.id == commentID }) { return found }
        return list.lazy.flatMap(\.replies).first { $0.id == commentID }
    }

    /// The top-level comment a thread hangs off — itself if it is one. Mirrors
    /// the server's flattening so the optimistic copy lands where the real one will.
    func threadRoot(of commentID: UUID) -> UUID? {
        guard let postID = commentingPostID, let list = commentsByPost[postID] else { return nil }
        if list.contains(where: { $0.id == commentID }) { return commentID }
        return list.first { $0.replies.contains { $0.id == commentID } }?.id
    }

    private func indexOfReply(_ commentID: UUID, in list: [Comment]) -> (Int, Int)? {
        for (root, comment) in list.enumerated() {
            if let reply = comment.replies.firstIndex(where: { $0.id == commentID }) {
                return (root, reply)
            }
        }
        return nil
    }

    /// Replies count toward a post's comment count — the badge is "how much
    /// conversation is here", not "how many threads".
    static func totalComments(_ list: [Comment]) -> Int {
        list.reduce(0) { $0 + 1 + max($1.replyCount, $1.replies.count) }
    }

    func applyCommentCount(_ count: Int, to id: UUID) {
        if let i = posts.firstIndex(where: { $0.id == id }) {
            posts[i].commentCount = count
        }
        if let i = videos.firstIndex(where: { $0.id == id }) {
            videos[i].commentCount = count
        }
    }

    func playVideo(_ id: UUID) {
        watchingVideoID = id
        watchingWithMadeleine = false
        watchingDraft = ""
        watchingChat = SampleData.watchingChat
        showWatching = true
        registerVideoView(id)
    }

    /// Opens the long-form details editor for a published video you own.
    func editVideoDetails(_ id: UUID) {
        guard canDeleteVideo(id) else { return }
        editingVideoID = id
    }

    func closeVideoDetails() {
        editingVideoID = nil
        editingLongFormAttachmentID = nil
    }

    var editingLongFormAttachment: ComposeAttachment? {
        guard let id = editingLongFormAttachmentID else { return nil }
        return composeAttachments.first(where: { $0.id == id })
    }

    /// Opens a feed video (single or carousel slide) in Shorts.
    func openFeedVideoAsShort(postID: UUID, videoURL preferredURL: String? = nil) {
        guard let post = posts.first(where: { $0.id == postID }) else { return }

        let url: String = {
            if let preferredURL, !preferredURL.isEmpty { return preferredURL }
            if let v = post.videoURL, !v.isEmpty { return v }
            if let slideURL = post.carouselSlides.first(where: {
                $0.isVideo && !($0.videoURL ?? "").isEmpty
            })?.videoURL, !slideURL.isEmpty {
                return slideURL
            }
            return ""
        }()
        guard !url.isEmpty else { return }

        let slide = post.carouselSlides.first(where: { $0.videoURL == url })
        let posterURL = slide?.imageURL ?? post.imageURL
        let posterData = slide?.imageData ?? post.imageData

        if let existing = shorts.first(where: { $0.videoURL == url }) {
            focusedShortID = existing.id
        } else {
            let short = Short(
                channel: post.author,
                caption: post.text ?? "",
                gradient: post.avatarGradient,
                imageURL: posterURL,
                imageData: posterData,
                videoURL: url,
                authorAvatarURL: post.avatarURL,
                liked: post.liked,
                following: post.following,
                likeCount: post.likeCount,
                publishedAt: Date()
            )
            shorts.insert(short, at: 0)
            focusedShortID = short.id
            schedulePersist()
        }

        withAnimation(.easeOut(duration: 0.25)) {
            activeTab = .watch
            watchSubFeed = .shorts
        }
    }

    func closeWatching() {
        LongFormOrientation.lock(.portrait)
        if commentingPostID != nil { closeComments() }
        showWatching = false
        watchingVideoID = nil
        watchingWithMadeleine = false
        watchingDraft = ""
    }

    func openMadeleineWhileWatching() {
        // One drawer under the player — comments yield to Madeleine.
        if commentingPostID != nil { closeComments() }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            watchingWithMadeleine = true
        }
    }

    func sendWatchingChat() {
        let text = watchingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        watchingChat.append(ChatMessage(text: text, fromUser: true))
        watchingDraft = ""
        let lower = text.lowercased()
        let reply: String
        if lower.contains("summar") || lower.contains("paper") {
            reply = "Here’s the gist: three papers cited — the 2024 toolformer study carries most of the argument. Want the PDF?"
        } else if lower.contains("who") || lower.contains("channel") {
            reply = "You’re watching \(watchingVideo?.channel ?? "this channel"). I can pull their other videos if you want."
        } else {
            reply = "Noted while we watch. Ask me to summarize, find sources, or queue related videos."
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.watchingChat.append(ChatMessage(text: reply, fromUser: false))
            if lower.contains("summar") || lower.contains("paper") {
                self?.watchingChat.append(ChatMessage(
                    text: "", fromUser: false,
                    fileChip: FileChip(name: "research-summary.pdf", sub: "3 sources · 2 min read")))
            }
        }
    }

    func publishPost(text: String?, imageData: Data?, videoURL: String? = nil,
                     audioURL: String? = nil,
                     mediaItems: [PostMediaItem] = []) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (trimmed?.isEmpty == false) ? trimmed : nil
        let slides = mediaItems
        let first = slides.first
        let resolvedImage = imageData ?? first?.imageData
        let resolvedVideo = videoURL ?? first?.videoURL
        guard body != nil || resolvedImage != nil || resolvedVideo != nil
                || audioURL != nil || !slides.isEmpty else { return }

        let post = Post(
            author: user.handle,
            meta: "just now",
            avatarGradient: user.avatarGradient,
            avatarURL: user.avatarURL,
            imageData: resolvedImage,
            videoURL: resolvedVideo,
            audioURL: audioURL,
            mediaItems: slides,
            imageAspect: resolvedImage != nil || resolvedVideo != nil || !slides.isEmpty ? 1.25 : 1.0,
            text: body,
            // Tags typed in the composer, resolved against handles this device
            // already knows, so the optimistic copy carries them until the
            // server's authoritative list arrives with the published post.
            mentions: MentionParser.resolveLocally(in: body ?? ""),
            likeCount: 0,
            isHalfWidth: false
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            posts.insert(post, at: 0)
            user.postCount += 1
        }
        schedulePersist()
        if backendConnected {
            syncPublishPost(localID: post.id, text: body, imageData: resolvedImage,
                            videoURL: resolvedVideo, audioURL: audioURL, slides: slides)
        } else {
            simulateEngagement(on: post.id)
        }
    }

    /// Prototype delight: a fresh post starts collecting likes/comments after a beat.
    private func simulateEngagement(on postID: UUID) {
        let fans = people.map(\.name) + ["marta.st", "kal.eb", "sena.films"]
        let firstFan = fans.randomElement() ?? "dani"
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 3.0...5.0)) { [weak self] in
            guard let self, let i = self.posts.firstIndex(where: { $0.id == postID }) else { return }
            self.posts[i].likeCount += Int.random(in: 3...9)
            self.pushActivity(ActivityItem(
                kind: .like, actor: firstFan,
                text: "and others liked your post.",
                timeAgo: "now",
                avatarURL: nil,
                previewURL: self.posts[i].imageURL))
            self.schedulePersist()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 7.0...11.0)) { [weak self] in
            guard let self, let i = self.posts.firstIndex(where: { $0.id == postID }) else { return }
            let commenter = fans.randomElement() ?? "lea"
            let text = ["This is great 🔥", "Okay this goes hard.",
                        "More of this please.", "Instant save."].randomElement()!
            var list = self.commentsByPost[postID] ?? []
            list.insert(Comment(author: commenter, text: text,
                                avatarURL: nil,
                                timeAgo: "now"), at: 0)
            self.commentsByPost[postID] = list
            self.posts[i].commentCount = list.count
            self.pushActivity(ActivityItem(
                kind: .comment, actor: commenter,
                text: "commented: “\(text)”",
                timeAgo: "now",
                avatarURL: nil,
                previewURL: self.posts[i].imageURL))
            self.schedulePersist()
        }
    }

    func openComposer() {
        guard activeTab == .home else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isComposing = true
            showAttachMenu = false
        }
    }

    func closeComposer() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isComposing = false
            showAttachMenu = false
            composeText = ""
            composeAttachments = []
            editingAttachmentID = nil
            showCompose = false
        }
    }

    func removeAttachment(_ id: UUID) {
        composeAttachments.removeAll { $0.id == id }
        if editingAttachmentID == id { editingAttachmentID = nil }
    }

    func addAttachment(_ attachment: ComposeAttachment, closeMenu: Bool = true) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            composeAttachments.append(attachment)
            if closeMenu { showAttachMenu = false }
        }
    }

    func addAttachments(_ attachments: [ComposeAttachment]) {
        guard !attachments.isEmpty else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            composeAttachments.append(contentsOf: attachments)
            showAttachMenu = false
        }
    }

    func updateAttachment(_ id: UUID, mutate: (inout ComposeAttachment) -> Void) {
        guard let i = composeAttachments.firstIndex(where: { $0.id == id }) else { return }
        mutate(&composeAttachments[i])
    }

    func openMediaEditor(_ id: UUID) {
        editingAttachmentID = id
    }

    func closeMediaEditor() {
        editingAttachmentID = nil
    }

    var editingAttachment: ComposeAttachment? {
        guard let id = editingAttachmentID else { return nil }
        return composeAttachments.first(where: { $0.id == id })
    }

    var canSendCompose: Bool {
        !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !composeAttachments.isEmpty
    }

    func publishCompose() {
        guard canSendCompose else { return }
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = text.isEmpty ? nil : text

        if composeAttachments.isEmpty {
            publishPost(text: caption, imageData: nil)
            closeComposer()
            persistSession()
            return
        }

        // Photo / mixed photo+video attachments → one carousel when 2+.
        let feedMedia = composeAttachments.filter { $0.kind == .photo }
        let audios = composeAttachments.filter { $0.kind == .audio }
        let shorts = composeAttachments.filter { $0.kind == .short }
        let longForms = composeAttachments.filter { $0.kind == .longForm }

        if feedMedia.count >= 2 {
            let slides = feedMedia.map {
                PostMediaItem(
                    imageData: $0.imageData,
                    videoURL: Self.persistedVideoURL(from: $0.videoURL)
                )
            }
            publishPost(text: caption, imageData: slides.first?.imageData,
                        videoURL: slides.first?.videoURL, mediaItems: slides)
        } else if let att = feedMedia.first {
            publishPost(text: caption, imageData: att.imageData,
                        videoURL: Self.persistedVideoURL(from: att.videoURL),
                        mediaItems: [PostMediaItem(imageData: att.imageData,
                                                   videoURL: Self.persistedVideoURL(from: att.videoURL))])
        }

        // A voice post keeps the recording, not the waveform picture the recorder
        // drew for the composer chip: it renders as a player, and a poster would
        // put it in the photo grid as a tile nobody can play.
        for att in audios {
            publishPost(text: caption, imageData: nil,
                        audioURL: AudioLibrary.persist(att.audioURL))
        }

        for att in shorts {
            let stored = Self.persistedVideoURL(from: att.videoURL)
            let short = Short(channel: user.handle,
                              caption: caption ?? "",
                              gradient: user.avatarGradient,
                              imageData: att.imageData,
                              videoURL: stored,
                              authorAvatarURL: user.avatarURL,
                              likeCount: 0,
                              publishState: .uploading(progress: 0))
            withAnimation { self.shorts.insert(short, at: 0) }
            // A short's caption rides in `title` — the server has no separate
            // body for one, so `description` stays empty.
            syncPublishVideo(localID: short.id, kind: "SHORT",
                             title: caption, description: nil,
                             thumbData: att.imageData, videoRef: stored,
                             durationSeconds: Self.durationSeconds(att.durationLabel))
            activeTab = .watch
            watchSubFeed = .shorts
        }

        for att in longForms {
            // Title / description / cover come from the details sheet; the
            // compose caption is the fallback title when it was skipped.
            let title = att.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let details = att.details.trimmingCharacters(in: .whitespacesAndNewlines)
            let stored = Self.persistedVideoURL(from: att.videoURL)
            let resolvedTitle = title.isEmpty ? (caption ?? "Untitled video") : title
            let video = VideoItem(title: resolvedTitle,
                                  channel: user.handle,
                                  details: details,
                                  duration: att.durationLabel ?? "0:08",
                                  thumbGradient: user.avatarGradient,
                                  thumbData: att.imageData,
                                  videoURL: stored,
                                  authorAvatarURL: user.avatarURL,
                                  likes: 0,
                                  publishState: .uploading(progress: 0))
            withAnimation { videos.insert(video, at: 0) }
            syncPublishVideo(localID: video.id, kind: "LONG_FORM",
                             title: resolvedTitle, description: details,
                             thumbData: att.imageData, videoRef: stored,
                             durationSeconds: Self.durationSeconds(att.durationLabel))
            activeTab = .watch
            watchSubFeed = .feed
        }

        closeComposer()
        persistSession()
    }

    /// Copies picker temp movies into Application Support so they survive rebuilds.
    private static func persistedVideoURL(from source: URL?) -> String? {
        VideoLibrary.persist(source)
    }

    /// "1:23" → 83. The server stores whole seconds and the client formats them
    /// back, so the label never has to round-trip as a string.
    static func durationSeconds(_ label: String?) -> Int? {
        guard let label else { return nil }
        let parts = label.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return nil
        }
    }

    /// Quick path — a bare photo with no editor. Same pipeline as the composer.
    func addStory(imageData: Data) {
        postStory([DraftStoryFrame(kind: .image, imageData: imageData)])
    }

    func openOwnProfile() {
        profileUser = .own(from: user, posts: myPosts.count)
        showProfile = true
        if backendConnected {
            Task {
                await refreshOwnCounts()
                if showProfile, profileUser?.isOwn == true {
                    profileUser = .own(from: user, posts: user.postCount)
                }
            }
        }
    }

    func openUserProfile(handle: String, name: String? = nil,
                         avatarURL: String? = nil, avatarGradient: [Color]? = nil) {
        // A profile is a page hosted under the root, and everything a profile
        // gets opened *from* sits above it — so a tapped author or a tapped
        // @tag pushed the profile in behind the still-open comments drawer, or
        // behind the long-form player it was embedded in. Nothing had gone
        // wrong, but the tap looked like it had half-worked. Whatever is
        // covering the destination is a place the user has now left.
        if showWatching {
            closeWatching()          // takes the embedded comments drawer with it
        } else if commentingPostID != nil {
            closeComments()
        }
        let cleaned = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if cleaned.lowercased() == user.handle.lowercased() {
            openOwnProfile()
            return
        }
        let authorPosts = posts.filter {
            $0.author == cleaned || $0.author == "@\(cleaned)"
        }
        let sample = authorPosts.first
        profileUser = ProfileUser(
            name: name ?? cleaned,
            handle: cleaned,
            avatarURL: avatarURL ?? sample?.avatarURL,
            avatarGradient: avatarGradient ?? sample?.avatarGradient ?? SampleData.g1,
            bio: "On gojogo.",
            category: "Creator",
            postCount: max(authorPosts.count, 1),
            followerCount: Int.random(in: 800...180_000),
            followingCount: Int.random(in: 40...900),
            isOwn: false,
            following: sample?.following ?? false
        )
        showProfile = true
        refreshRemoteProfile(handle: cleaned)
    }

    /// Opens the profile behind a tapped `@tag`. The id is the reliable half —
    /// a tag written before someone renamed still carries the right one — but
    /// the profile screen is keyed by handle, so a known id is resolved back to
    /// its current handle before opening.
    func openTaggedProfile(handle: String, profileID: UUID?) {
        if let profileID, let known = SocialStore.shared.handle(forProfileId: profileID) {
            openUserProfile(handle: known)
        } else {
            openUserProfile(handle: handle)
        }
    }

    /// People the picker can offer without asking the server: whoever is already
    /// on screen. This is the whole source when running on sample content, and
    /// the instant first page when connected.
    var mentionCandidates: [MentionCandidate] {
        var seen: Set<String> = []
        var out: [MentionCandidate] = []
        func add(handle rawHandle: String, name: String?, avatarURL: String?) {
            let handle = rawHandle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            guard handle.count >= 2, handle.lowercased() != user.handle.lowercased(),
                  seen.insert(handle.lowercased()).inserted else { return }
            out.append(MentionCandidate(
                id: SocialStore.shared.profileId(forHandle: handle) ?? UUID(),
                name: name ?? handle, handle: handle, avatarURL: avatarURL))
        }
        for post in posts { add(handle: post.author, name: nil, avatarURL: post.avatarURL) }
        if let id = commentingPostID, let thread = commentsByPost[id] {
            for comment in thread {
                add(handle: comment.author, name: nil, avatarURL: comment.avatarURL)
                for reply in comment.replies {
                    add(handle: reply.author, name: nil, avatarURL: reply.avatarURL)
                }
            }
        }
        return out
    }

    func closeProfile() {
        showProfile = false
        profileUser = nil
    }

    func toggleProfileFollow() {
        guard var p = profileUser, !p.isOwn else { return }
        p.following.toggle()
        p.followerCount += p.following ? 1 : -1
        profileUser = p
        // Mirror onto feed posts with same author when present.
        for i in posts.indices where posts[i].author == p.handle || posts[i].author == "@\(p.handle)" {
            posts[i].following = p.following
            posts[i].showFollow = !p.following
        }
        syncProfileFollow(handle: p.handle, following: p.following)
        schedulePersist()
    }

    func openStory(_ story: Story, at frame: Int = 0) {
        guard story.hasMedia else { return }
        let start = min(max(frame, 0), max(story.frames.count - 1, 0))
        let preferred: Int = {
            if let unseen = story.frames.firstIndex(where: { !$0.seen }) { return unseen }
            return start
        }()
        playingHighlightRing = nil
        viewingHighlightTitle = nil
        storyViewerRail = storyTray.filter(\.hasMedia).map(\.id)
        viewingFrameIndex = preferred
        viewingStory = stories.first(where: { $0.id == story.id }) ?? story
        // Overlay on Home avoids fullScreenCover fight with swipe-down.
        storyOverlayActive = !showStoriesBrowser
        loadInsightsForCurrentFrame()
    }

    func closeStoryViewer() {
        viewingStory = nil
        viewingFrameIndex = 0
        storyViewerRail = []
        storyOverlayActive = false
        playingHighlightRing = nil
        viewingHighlightTitle = nil
        storyReplies = []
        storyViewers = []
        stories = storyTray
        schedulePersist()
    }

    func markFrameSeen(storyID: UUID, frameID: UUID) {
        // A highlight replays frames whose seen-state was settled 24h ago.
        guard playingHighlightRing == nil else { return }
        guard let si = stories.firstIndex(where: { $0.id == storyID }),
              let fi = stories[si].frames.firstIndex(where: { $0.id == frameID }) else { return }
        guard !stories[si].frames[fi].seen else { return }
        stories[si].frames[fi].seen = true
        if viewingStory?.id == storyID {
            viewingStory = stories[si]
        }
        syncFrameSeen(frameID: frameID)
        schedulePersist()
    }

    func liveStory(id: UUID) -> Story? {
        if let ring = playingHighlightRing, ring.id == id { return ring }
        return stories.first(where: { $0.id == id })
    }

    /// Advance within the person, then to the next person. Returns false if finished.
    @discardableResult
    func advanceStory() -> Bool {
        guard let current = viewingStory,
              let live = liveStory(id: current.id) else {
            closeStoryViewer(); return false
        }
        if viewingFrameIndex + 1 < live.frames.count {
            viewingFrameIndex += 1
            viewingStory = live
            return true
        }
        guard let authorIndex = storyViewerRail.firstIndex(of: current.id),
              authorIndex + 1 < storyViewerRail.count,
              let next = liveStory(id: storyViewerRail[authorIndex + 1]) else {
            closeStoryViewer()
            return false
        }
        viewingFrameIndex = 0
        viewingStory = next
        return true
    }

    /// Go back within the person, then to the previous person.
    @discardableResult
    func retreatStory() -> Bool {
        guard let current = viewingStory,
              let live = liveStory(id: current.id) else {
            closeStoryViewer(); return false
        }
        if viewingFrameIndex > 0 {
            viewingFrameIndex -= 1
            viewingStory = live
            return true
        }
        guard let authorIndex = storyViewerRail.firstIndex(of: current.id),
              authorIndex > 0,
              let prev = liveStory(id: storyViewerRail[authorIndex - 1]) else {
            return false
        }
        viewingFrameIndex = max(prev.frames.count - 1, 0)
        viewingStory = prev
        return true
    }

    func jumpToAdjacentAuthor(forward: Bool) {
        guard let current = viewingStory,
              let authorIndex = storyViewerRail.firstIndex(of: current.id) else { return }
        if forward {
            guard authorIndex + 1 < storyViewerRail.count,
                  let next = liveStory(id: storyViewerRail[authorIndex + 1]) else {
                closeStoryViewer()
                return
            }
            viewingFrameIndex = 0
            viewingStory = next
        } else if authorIndex > 0,
                  let prev = liveStory(id: storyViewerRail[authorIndex - 1]) {
            viewingFrameIndex = 0
            viewingStory = prev
        }
    }

    // MARK: Videos / Shorts

    func toggleVideoLike(_ id: UUID) {
        guard let i = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[i].liked.toggle()
        videos[i].likes += videos[i].liked ? 1 : -1
        syncVideoLike(id, liked: videos[i].liked)
        schedulePersist()
    }

    func toggleVideoSave(_ id: UUID) {
        guard let i = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[i].saved.toggle()
        syncVideoSave(id, saved: videos[i].saved)
        schedulePersist()
    }

    func toggleShortLike(_ id: UUID) {
        guard let i = shorts.firstIndex(where: { $0.id == id }) else { return }
        shorts[i].liked.toggle()
        shorts[i].likeCount += shorts[i].liked ? 1 : -1
        syncVideoLike(id, liked: shorts[i].liked)
        schedulePersist()
    }

    /// Like only (double-tap) — no-ops if already liked. Returns whether newly liked.
    @discardableResult
    func likeShort(_ id: UUID) -> Bool {
        guard let i = shorts.firstIndex(where: { $0.id == id }) else { return false }
        guard !shorts[i].liked else { return false }
        shorts[i].liked = true
        shorts[i].likeCount += 1
        syncVideoLike(id, liked: true)
        schedulePersist()
        return true
    }

    func toggleShortBookmark(_ id: UUID) {
        guard let i = shorts.firstIndex(where: { $0.id == id }) else { return }
        shorts[i].bookmarked.toggle()
        syncVideoSave(id, saved: shorts[i].bookmarked)
        schedulePersist()
    }

    func toggleShortFollow(_ id: UUID) {
        guard let i = shorts.firstIndex(where: { $0.id == id }) else { return }
        shorts[i].following.toggle()
        schedulePersist()
    }

    // MARK: Economy / people

    var savedProducts: [Product] {
        ([featuredProduct] + products).filter { !$0.name.isEmpty && $0.saved }
    }

    func liveProduct(id: UUID) -> Product? {
        if featuredProduct.id == id { return featuredProduct }
        return products.first(where: { $0.id == id })
    }

    func openProduct(_ product: Product) {
        browsingProduct = liveProduct(id: product.id) ?? product
    }

    func closeProduct() {
        browsingProduct = nil
    }

    /// "Message seller". A live listing opens the real My World thread with the
    /// seller; everything else (SampleData catalog, signed out) keeps the local
    /// demo conversation so the marketplace still demos end to end.
    func openSellerChat(for product: Product) {
        if canMessageSeller(product) {
            openLiveSellerChat(for: product)
            return
        }
        openLocalSellerChat(for: product)
    }

    func openLocalSellerChat(for product: Product) {
        messagingProduct = liveProduct(id: product.id) ?? product
        if sellerChat.isEmpty {
            sellerChat = [
                ChatMessage(text: "Hey — is \(product.name) still available?", fromUser: true),
                ChatMessage(
                    text: "Yes. I can meet near \(product.distance) · usually free after 6.",
                    fromUser: false),
            ]
        }
        sellerDraft = ""
    }

    func closeSellerChat() {
        messagingProduct = nil
        sellerDraft = ""
    }

    func sendSellerMessage() {
        let text = sellerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, messagingProduct != nil else { return }
        sellerChat.append(ChatMessage(text: text, fromUser: true))
        sellerDraft = ""
        let replies = [
            "Sounds good — I can hold it until tomorrow.",
            "Cash or transfer both work.",
            "Want a couple more photos?",
        ]
        let reply = replies.randomElement() ?? "Got it."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.sellerChat.append(ChatMessage(text: reply, fromUser: false))
            self?.schedulePersist()
        }
        schedulePersist()
    }

    func toggleSaveProduct(_ id: UUID) {
        if featuredProduct.id == id {
            featuredProduct.saved.toggle()
            if browsingProduct?.id == id { browsingProduct?.saved = featuredProduct.saved }
            syncListingSave(id, saved: featuredProduct.saved)
            schedulePersist()
            return
        }
        guard let i = products.firstIndex(where: { $0.id == id }) else { return }
        products[i].saved.toggle()
        if browsingProduct?.id == id { browsingProduct?.saved = products[i].saved }
        syncListingSave(id, saved: products[i].saved)
        schedulePersist()
    }

    // MARK: GojoTV

    func openTVShow(_ id: UUID?) {
        guard let id else {
            selectedTVShow = tvHero
            return
        }
        if tvHero.id == id {
            selectedTVShow = tvHero
            return
        }
        selectedTVShow = tvShows.first(where: { $0.id == id })
    }

    func closeTVShow() {
        selectedTVShow = nil
    }

    func toggleTVWatchlist(_ id: UUID) {
        if tvHero.id == id {
            tvHero.onWatchlist.toggle()
            if selectedTVShow?.id == id { selectedTVShow?.onWatchlist = tvHero.onWatchlist }
            schedulePersist()
            return
        }
        guard let i = tvShows.firstIndex(where: { $0.id == id }) else { return }
        tvShows[i].onWatchlist.toggle()
        if selectedTVShow?.id == id { selectedTVShow?.onWatchlist = tvShows[i].onWatchlist }
        schedulePersist()
    }

    func playTVShow(_ show: TVShow) {
        let key = String(show.title.prefix(10)).lowercased()
        let match = videos.first(where: { $0.title.lowercased().contains(key) || key.contains(String($0.title.prefix(8)).lowercased()) })
        playVideo((match ?? videos.first)?.id ?? UUID())
    }

    /// Play a specific episode: marks it watched, updates show progress, then plays.
    func playEpisode(showID: UUID, episodeID: UUID) {
        func advance(_ show: inout TVShow) {
            guard let e = show.episodes.firstIndex(where: { $0.id == episodeID }) else { return }
            show.episodes[e].watched = true
            let watched = show.episodes.filter(\.watched).count
            show.progress = min(1, Double(watched) / Double(max(show.episodes.count, 1)))
        }
        if tvHero.id == showID {
            advance(&tvHero)
            if selectedTVShow?.id == showID { selectedTVShow = tvHero }
            playTVShow(tvHero)
        } else if let i = tvShows.firstIndex(where: { $0.id == showID }) {
            advance(&tvShows[i])
            if selectedTVShow?.id == showID { selectedTVShow = tvShows[i] }
            playTVShow(tvShows[i])
        }
        schedulePersist()
    }

    func toggleFollowPerson(_ id: UUID) {
        guard let i = people.firstIndex(where: { $0.id == id }) else { return }
        people[i].following.toggle()
        user.followingCount += people[i].following ? 1 : -1
        schedulePersist()
    }

    // MARK: Partner — become a driver / delivery partner

    /// True once the user can work this side of the marketplace.
    func isPartner(_ role: PartnerRole) -> Bool { partnerRoles.contains(role) }

    /// Entry point from the GojoTravel / GojoDelivery header button.
    /// Opens the working dashboard if already onboarded, else starts the flow.
    func openPartner(_ role: PartnerRole) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if partnerRoles.contains(role) {
            openPartnerDashboard(role)
        } else {
            startPartnerOnboarding(role)
        }
    }

    // MARK: Partner — onboarding flow

    func startPartnerOnboarding(_ role: PartnerRole) {
        partnerApplication = PartnerApplication(role: role)
        partnerAgreedToTerms = false
        partnerStakeProcessing = false
        partnerStep = .rules
        partnerResolving = backendConnected
        withAnimation(.easeInOut(duration: 0.28)) { partnerOnboardingRole = role }
        // All fetched here rather than on connect: only this flow needs any of
        // it, and by the time the rules page has been read the answers are
        // waiting. The application has to exist before the stake page can name
        // an amount, so it is opened (or created) first — and it is also what
        // decides which page opens at all, which is why the cover holds until
        // it answers.
        Task {
            await loadDriverApplication(role)
            withAnimation(.easeInOut(duration: 0.22)) { partnerResolving = false }
            await refreshWallet()
            await refreshIdentity()
        }
    }

    func cancelPartnerOnboarding() {
        partnerStakeProcessing = false
        partnerResolving = false
        withAnimation(.easeInOut(duration: 0.28)) { partnerOnboardingRole = nil }
    }

    /// "I agree" on the rules page → move to the stake payment.
    func agreePartnerRules() {
        guard partnerAgreedToTerms else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.3)) { partnerStep = .stake }
    }

    /// The stake and the submission both live in `AppState+Driver.swift` now:
    /// they are server calls (a real ledger movement, and a real place in a
    /// human's queue), not the 1.6-second sleep and local `Set.insert` they used
    /// to be. Kept out of this file so the difference is obvious.

    /// Dismiss the completion screen; optionally jump straight into the dashboard.
    func finishPartnerOnboarding(openDashboard: Bool) {
        let role = partnerOnboardingRole
        withAnimation(.easeInOut(duration: 0.28)) { partnerOnboardingRole = nil }
        if openDashboard, let role {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openPartnerDashboard(role)
            }
        }
    }

    // MARK: Partner — per-role stats

    func partnerEarnings(_ role: PartnerRole) -> Double { partnerEarningsByRole[role.rawValue] ?? 0 }

    /// Jobs done. From the dispatch registry once there is one — a local
    /// counter and a server counter would disagree the first time somebody
    /// reinstalled.
    func partnerJobs(_ role: PartnerRole) -> Int {
        isDispatchRegistered ? dispatchCompleted(role) : partnerJobsByRole[role.rawValue] ?? 0
    }

    func partnerRating(_ role: PartnerRole) -> Double {
        if isDispatchRegistered { return dispatchRating(role) ?? 5.0 }
        return partnerRatingByRole[role.rawValue] ?? 5.0
    }

    // MARK: Partner — working dashboard

    func openPartnerDashboard(_ role: PartnerRole) {
        // Never reset the stage over a real trip in progress — the ride exists
        // on the server whether or not this screen was open to watch it.
        if driverRide == nil {
            partnerJobPhase = .idle
            partnerJob = nil
            partnerJobProgress = 0
        }
        withAnimation(.easeInOut(duration: 0.3)) { partnerDashboardRole = role }
        Task {
            await refreshDispatch()
            // A trip picked back up (this device or another): redraw its card.
            if let ride = driverRide {
                applyDriverRide(ride)
                if !ride.isOver, driverRidePollTask == nil { startDriverRidePolling() }
            }
            // A driver who was already available when the app was killed is
            // still available as far as the server is concerned; pick the duty
            // loops back up rather than leaving them invisible.
            if dispatchOnline {
                partnerOnline = true
                startDispatchDuty()
            }
        }
    }

    func closePartnerDashboard() {
        goOffline()
        withAnimation(.easeInOut(duration: 0.28)) { partnerDashboardRole = nil }
    }

    /// Live for anybody in a dispatch registry, simulated for everybody else.
    ///
    /// The demo is not dead code: somebody who has never been approved has no
    /// other way to see what this screen is for, and showing them an empty
    /// dashboard would be accurate and useless. What must never happen is the
    /// reverse — a *real* driver being shown an invented offer — so the branch
    /// is on the registry rather than on a debug flag.
    func togglePartnerOnline() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard let role = partnerDashboardRole else { return }
        if isDispatchRegistered {
            let goingOnline = !partnerOnline
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                partnerOnline = goingOnline
            }
            // Going offline stops new offers; it must not erase a trip already
            // accepted — that ride exists on the server whether or not the
            // driver keeps taking work after it.
            if !goingOnline && driverRide == nil { partnerJob = nil; partnerJobPhase = .idle }
            setDispatchAvailable(goingOnline, role: role)
            return
        }
        if partnerOnline { goOffline() } else { goOnline() }
    }

    private func goOnline() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { partnerOnline = true }
        scheduleNextOffer(initial: true)
    }

    private func goOffline() {
        partnerOfferTask?.cancel()
        // Never cancel an in-progress navigation job — that froze the car on the map.
        if partnerJobPhase == .offer {
            partnerJobTask?.cancel()
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            partnerOnline = false
            if partnerJobPhase == .offer {
                partnerJobPhase = .idle
                partnerJob = nil
            }
        }
    }

    /// Queue up an incoming request after a short delay.
    private func scheduleNextOffer(initial: Bool = false) {
        guard let role = partnerDashboardRole, partnerOnline else { return }
        partnerOfferTask?.cancel()
        partnerOfferTask = Task { @MainActor in
            let delay: UInt64 = initial ? 2_200_000_000 : UInt64.random(in: 3_000_000_000...5_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, partnerOnline, partnerJobPhase == .idle else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                partnerJob = SampleData.samplePartnerJob(role: role)
                partnerJobPhase = .offer
            }
        }
    }

    func declinePartnerJob() {
        if let live = liveOffer {
            withAnimation(.easeInOut(duration: 0.25)) {
                partnerJob = nil
                partnerJobPhase = .idle
            }
            declineDispatchOffer(live)
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.25)) {
            partnerJob = nil
            partnerJobPhase = .idle
        }
        scheduleNextOffer()
    }

    func acceptPartnerJob() {
        guard partnerJob != nil else { return }
        if let live = liveOffer {
            // A real acceptance ends the *offer* here on purpose, and what
            // happens next belongs to the vertical that asked: a delivery
            // becomes the courier card below, driven by `delivery` (Phase 4 M1).
            // What it must never become is the demo's animated route, which
            // would be this app inventing a trip over a real assignment.
            withAnimation(.easeInOut(duration: 0.25)) {
                partnerJob = nil
                partnerJobPhase = .idle
            }
            acceptDispatchOffer(live)
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        partnerJobProgress = 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { partnerJobPhase = .toPickup }
        runPartnerJob()
    }

    /// The server-sent offer the card on screen is showing, if it is one.
    /// Matched by id, because a demo job and a real one are the same struct and
    /// answering the wrong one would be worse than answering neither.
    private var liveOffer: DispatchOfferDTO? {
        guard let shown = partnerJob else { return nil }
        return dispatchOffers.first { $0.id == shown.id }
    }

    /// Drives the accepted job through pickup → dropoff → completion,
    /// animating the partner's position along both legs for the map guide.
    private func runPartnerJob() {
        partnerJobTask?.cancel()
        partnerJobTask = Task { @MainActor in
            // ~20 fps along each leg for smooth marker motion.
            let legSteps = 120
            let tickNs: UInt64 = 75_000_000 // 75ms → ~9s per leg

            // Leg 1 — heading to pickup / restaurant.
            for step in 1...legSteps {
                try? await Task.sleep(nanoseconds: tickNs)
                guard !Task.isCancelled, partnerJob != nil else { return }
                partnerJobProgress = Double(step) / Double(legSteps)
            }
            guard !Task.isCancelled, partnerJob != nil else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            partnerJobProgress = 0
            partnerJobPhase = .toDropoff

            // Leg 2 — trip / delivery in progress to the customer.
            for step in 1...legSteps {
                try? await Task.sleep(nanoseconds: tickNs)
                guard !Task.isCancelled, partnerJob != nil else { return }
                partnerJobProgress = Double(step) / Double(legSteps)
            }
            guard !Task.isCancelled, let job = partnerJob else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            partnerEarningsByRole[job.role.rawValue, default: 0] += job.fare
            partnerJobsByRole[job.role.rawValue, default: 0] += 1
            // No withAnimation — avoids leaving the nav map stuck mid-transition.
            partnerJobPhase = .completed
        }
    }

    /// Dismiss the completed-job card and return to waiting for offers.
    func clearCompletedPartnerJob() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if driverRide != nil {
            // A real trip: clear the ride state too, and never invent a demo
            // offer for a registered driver — their next job comes from dispatch.
            clearDriverRide()
            schedulePersist()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            partnerJob = nil
            partnerJobProgress = 0
            partnerJobPhase = .idle
        }
        schedulePersist()
        if !isDispatchRegistered { scheduleNextOffer() }
    }

    /// Label describing what the partner is doing right now (dashboard subtitle).
    var partnerStatusLine: String {
        guard let role = partnerDashboardRole else { return "" }
        switch partnerJobPhase {
        case .idle:
            return partnerOnline ? "Online · waiting for \(role.jobNoun) requests" : "You're offline"
        case .offer:
            return "New \(role.jobNoun) request"
        case .toPickup:
            return role == .driver ? "Heading to pickup" : "Heading to the restaurant"
        case .toDropoff:
            return role == .driver ? "Trip in progress" : "Delivering to customer"
        case .completed:
            return "\(role.jobNoun.capitalized) complete"
        }
    }

    // MARK: GojoTravel

    /// What the destination list shows: recents until somebody types, then the
    /// geocoder's guesses with any matching recent kept on top — a place you
    /// have actually been to is a better answer than a place that merely
    /// matches the letters.
    var filteredTravelPlaces: [TravelPlace] {
        let q = travelQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Array(travelRecent.prefix(6)) }
        let matchingRecent = travelRecent.filter {
            $0.name.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
        let fresh = travelSearchResults.filter { result in
            !matchingRecent.contains { $0.name.caseInsensitiveCompare(result.name) == .orderedSame }
        }
        return matchingRecent + fresh
    }

    /// True while there is genuinely nothing to show — used to tell "still
    /// typing" apart from "no such place", which look the same otherwise.
    var travelSearchIsEmpty: Bool {
        !travelQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !travelSearching
            && filteredTravelPlaces.isEmpty
    }

    /// Debounced forward geocode. Called on every keystroke; only the last one
    /// in any 300ms window actually reaches the network.
    func travelQueryChanged(_ text: String) {
        travelSearchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            travelSearchResults = []
            travelSearching = false
            return
        }
        travelSearching = true
        travelSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            // Bias toward the rider only once there is a real fix — proximity to
            // the placeholder would rank results around a city they aren't in.
            let near = travelPickupState.isReal
                ? CLLocationCoordinate2D(latitude: travelPickup.latitude,
                                         longitude: travelPickup.longitude)
                : nil
            let results = await PlaceSearch.suggest(q, near: near)
            guard !Task.isCancelled else { return }
            // A slower reply for an older query must not overwrite a newer one.
            guard self.travelQuery.trimmingCharacters(in: .whitespacesAndNewlines) == q else { return }
            self.travelSearchResults = results
            self.travelSearching = false
        }
    }

    // MARK: Pickup

    /// Puts the pickup pin where the rider actually is.
    ///
    /// The app opens on a placeholder coordinate so the map has something to
    /// draw; leaving it there means every ride is requested from that spot. One
    /// GPS fix plus a reverse geocode replaces it with a real corner and a name
    /// somebody would recognise.
    func refreshTravelPickup(force: Bool = false) {
        guard force || !travelPickupState.isReal else { return }
        travelPickupTask?.cancel()
        travelPickupState = .locating
        travelPickupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let place = try await LiveLocationProvider.shared.currentPlace()
                guard !Task.isCancelled else { return }
                updateTravelPickup(latitude: place.coordinate.latitude,
                                   longitude: place.coordinate.longitude,
                                   label: place.name)
                travelPickupState = .live
            } catch LiveLocationProvider.LocationError.denied {
                guard !Task.isCancelled else { return }
                travelPickupState = .denied
            } catch {
                guard !Task.isCancelled else { return }
                travelPickupState = .unavailable
            }
        }
    }

    /// What the pickup row should read, given where the coordinate came from.
    var travelPickupLabel: String {
        switch travelPickupState {
        case .live: return travelPickup.name
        case .locating: return "Finding your location…"
        case .denied: return "Location is off — tap to fix"
        case .unavailable: return "No GPS fix — tap to retry"
        case .unknown: return "Set your pickup"
        }
    }

    func openTravelSearch() {
        travelQuery = ""
        travelSearchResults = []
        travelSearching = false
        refreshTravelPickup()
        withAnimation(.easeInOut(duration: 0.28)) { travelPhase = .searching }
    }

    func closeTravelSearch() {
        travelSearchTask?.cancel()
        travelQuery = ""
        travelSearchResults = []
        travelSearching = false
        withAnimation(.easeInOut(duration: 0.28)) { travelPhase = .home }
    }

    func selectTravelDestination(_ place: TravelPlace) {
        travelDropoff = place
        travelRideOptions = SampleData.rideOptions(from: travelPickup, to: place)
        selectedRide = travelRideOptions.first
        if !travelRecent.contains(where: { $0.name == place.name }) {
            travelRecent.insert(place, at: 0)
            if travelRecent.count > 8 { travelRecent = Array(travelRecent.prefix(8)) }
        }
        travelSearchTask?.cancel()
        travelSearchResults = []
        travelSearching = false
        travelQuery = ""
        withAnimation(.easeInOut(duration: 0.32)) { travelPhase = .choosingRide }
    }

    func backFromRideChoice() {
        selectedRide = nil
        travelRideOptions = []
        withAnimation(.easeInOut(duration: 0.28)) { travelPhase = .searching }
    }

    func confirmTravelRide() {
        guard selectedRide != nil, travelDropoff != nil else { return }
        travelDriver = nil
        travelRating = 0
        withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .matching }
        travelMatchTask?.cancel()
        travelMatchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            let eta = selectedRide?.etaMinutes ?? 4
            let driver = SampleData.sampleDriver(near: travelPickup, eta: max(2, eta / 2))
            travelDriver = driver
            travelPhase = .enRoute

            let pickupCoord = CLLocationCoordinate2D(
                latitude: travelPickup.latitude, longitude: travelPickup.longitude)
            let startCoord = CLLocationCoordinate2D(
                latitude: driver.latitude, longitude: driver.longitude)

            // Drive toward the customer — paced by distance so it never teleports.
            await animateTravelDriver(from: startCoord, to: pickupCoord, pace: .approaching)
            guard !Task.isCancelled else { return }

            travelPhase = .inTrip

            if let drop = travelDropoff {
                let dropCoord = CLLocationCoordinate2D(
                    latitude: drop.latitude, longitude: drop.longitude)
                let from = CLLocationCoordinate2D(
                    latitude: travelDriver?.latitude ?? pickupCoord.latitude,
                    longitude: travelDriver?.longitude ?? pickupCoord.longitude)
                await animateTravelDriver(from: from, to: dropCoord, pace: .inTrip)
            }
            guard !Task.isCancelled else { return }
            completeTravelTrip()
        }
    }

    private enum TravelDriverPace {
        case approaching  // driver → pickup
        case inTrip       // pickup → dropoff

        /// Same pace for both legs. Lower secondsPerKm = faster car.
        var secondsPerKm: Double { 9 }
        var minSeconds: Double { 16 }
        var maxSeconds: Double { 42 }
    }

    /// Moves `travelDriver` along a road route at a calm demo pace.
    private func animateTravelDriver(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        pace: TravelDriverPace
    ) async {
        let route = await MapboxDirections.route(from: from, to: to) ?? [from, to]
        let km = routePathLengthKm(route)
        let seconds = min(pace.maxSeconds, max(pace.minSeconds, km * pace.secondsPerKm))
        let steps = max(48, Int((seconds * 20).rounded())) // ~20 fps
        let tickNs = UInt64((seconds / Double(steps)) * 1_000_000_000)
        let startEta = max(1, Int(seconds / 60.0 + 0.5))
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: tickNs)
            guard !Task.isCancelled else { return }
            let point = PartnerRoute.point(on: route, at: Double(step) / Double(steps))
            guard var driver = travelDriver else { return }
            driver.latitude = point.latitude
            driver.longitude = point.longitude
            let left = max(1, Int((Double(steps - step) / Double(steps) * Double(startEta)).rounded()))
            driver.etaMinutes = left
            travelDriver = driver
        }
    }

    private func routePathLengthKm(_ route: [CLLocationCoordinate2D]) -> Double {
        guard route.count > 1 else { return 0.5 }
        var meters = 0.0
        for i in 1..<route.count {
            meters += CLLocation(latitude: route[i - 1].latitude, longitude: route[i - 1].longitude)
                .distance(from: CLLocation(latitude: route[i].latitude, longitude: route[i].longitude))
        }
        return max(0.3, meters / 1000.0)
    }

    func startTravelTrip() {
        withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .inTrip }
    }

    func completeTravelTrip() {
        travelMatchTask?.cancel()
        withAnimation(.easeInOut(duration: 0.35)) { travelPhase = .completed }
    }

    func cancelTravelRide() {
        travelMatchTask?.cancel()
        travelDriver = nil
        selectedRide = nil
        travelRideOptions = []
        travelDropoff = nil
        travelRating = 0
        withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .home }
    }

    func finishTravelTrip() {
        travelMatchTask?.cancel()
        travelDriver = nil
        selectedRide = nil
        travelRideOptions = []
        travelDropoff = nil
        travelRating = 0
        withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .home }
    }

    func updateTravelPickup(latitude: Double, longitude: Double, label: String? = nil) {
        travelPickup = TravelPlace(
            id: travelPickup.id,
            name: label ?? travelPickup.name,
            // The street is now in `name`, so the second line says where the
            // street came from rather than repeating it.
            subtitle: label == nil ? travelPickup.subtitle : "Current location",
            latitude: latitude,
            longitude: longitude,
            icon: "location.fill"
        )
    }

    // MARK: GojoDelivery

    var selectedDeliveryRestaurant: DeliveryRestaurant? {
        guard let id = selectedDeliveryRestaurantID else { return nil }
        return deliveryRestaurants.first(where: { $0.id == id })
    }

    var deliveryOrderRestaurant: DeliveryRestaurant? {
        guard let id = deliveryOrderRestaurantID else { return nil }
        return deliveryRestaurants.first(where: { $0.id == id })
    }

    var filteredDeliveryRestaurants: [DeliveryRestaurant] {
        var list = deliveryRestaurants
        if deliveryCategory != "All" {
            list = list.filter { $0.categories.contains(deliveryCategory) }
        }
        let q = deliverySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q)
                    || $0.cuisine.lowercased().contains(q)
                    || $0.menu.contains { $0.items.contains { $0.name.lowercased().contains(q) } }
            }
        }
        return list
    }

    func openDeliveryRestaurant(_ id: UUID) {
        // Browse returns restaurants without their menus — pull this one's now.
        loadDeliveryMenuIfNeeded(id)
        withAnimation(.easeInOut(duration: 0.28)) { selectedDeliveryRestaurantID = id }
    }

    func closeDeliveryRestaurant() {
        withAnimation(.easeInOut(duration: 0.28)) { selectedDeliveryRestaurantID = nil }
    }

    // MARK: GojoDelivery — cart

    var deliveryCartCount: Int { deliveryCart.reduce(0) { $0 + $1.qty } }

    var deliveryCartSubtotal: Double {
        deliveryCart.reduce(0) { $0 + $1.item.price * Double($1.qty) }
    }

    /// Every kitchen's fee, because the courier makes a stop at each of them
    /// and is paid for each (Phase 4 M3). The server's quote replaces this the
    /// moment there is one; it is the offline demo's arithmetic.
    var deliveryFeeAmount: Double {
        let ids = Set(deliveryCart.map(\.merchantID))
        guard !ids.isEmpty else { return 0 }
        return ids.reduce(0.0) { running, id in
            guard let r = deliveryRestaurants.first(where: { $0.id == id }) else {
                return running + 1.49
            }
            return running + Double(r.feeCents) / 100
        }
    }

    /// Once per checkout, not per kitchen — the platform charges for the order.
    var deliveryServiceFee: Double { deliveryCart.isEmpty ? 0 : 0.99 }

    var deliveryCartTotal: Double {
        deliveryCartSubtotal + deliveryFeeAmount + deliveryServiceFee
    }

    /// How many kitchens an order may span, mirroring the server's own cap
    /// (`delivery.order.max.merchants`). One courier collects every bag, so
    /// three counters is a trip one person makes and five is a relay.
    static let deliveryMaxMerchants = 3

    /// The cart grouped the way it will be sent, and the way checkout draws it.
    /// Ordered by when each kitchen first entered the cart, so the list does
    /// not reshuffle under somebody's thumb as they add things.
    var deliveryCartByMerchant: [(merchantID: UUID, name: String, lines: [DeliveryCartLine])] {
        var order: [UUID] = []
        var byMerchant: [UUID: [DeliveryCartLine]] = [:]
        for line in deliveryCart {
            if byMerchant[line.merchantID] == nil { order.append(line.merchantID) }
            byMerchant[line.merchantID, default: []].append(line)
        }
        return order.map { id in
            let lines = byMerchant[id] ?? []
            return (id, lines.first?.merchantName ?? "Restaurant", lines)
        }
    }

    var deliveryCartMerchantIDs: [UUID] { deliveryCartByMerchant.map(\.merchantID) }

    func deliveryQty(of item: DeliveryMenuItem) -> Int {
        deliveryCart.first(where: { $0.id == item.id })?.qty ?? 0
    }

    /// Whether adding from this restaurant would exceed the cap. Asked by the
    /// menu screen so the refusal lands on the button rather than at checkout,
    /// where somebody has already chosen the food.
    func deliveryCartIsFull(for restaurant: DeliveryRestaurant) -> Bool {
        let ids = Set(deliveryCart.map(\.merchantID))
        return !ids.contains(restaurant.id) && ids.count >= Self.deliveryMaxMerchants
    }

    /// Adds an item. Since Phase 4 M3 a second restaurant joins the cart
    /// instead of replacing it — up to the cap, past which the add is refused
    /// out loud rather than silently wiping a cart somebody built.
    func addDeliveryItem(_ item: DeliveryMenuItem, from restaurant: DeliveryRestaurant) {
        guard !deliveryCartIsFull(for: restaurant) else {
            showDeliveryNotice(
                "One order can cover \(Self.deliveryMaxMerchants) restaurants — one courier picks it all up.")
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            if deliveryCartRestaurantID == nil { deliveryCartRestaurantID = restaurant.id }
            if let i = deliveryCart.firstIndex(where: { $0.id == item.id }) {
                deliveryCart[i].qty += 1
            } else {
                deliveryCart.append(DeliveryCartLine(item: item, qty: 1,
                                                     merchantID: restaurant.id,
                                                     merchantName: restaurant.name))
            }
        }
    }

    func decrementDeliveryItem(_ item: DeliveryMenuItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            guard let i = deliveryCart.firstIndex(where: { $0.id == item.id }) else { return }
            if deliveryCart[i].qty > 1 {
                deliveryCart[i].qty -= 1
            } else {
                deliveryCart.remove(at: i)
            }
            // The cart-level id names the first kitchen left in it, which is
            // what the demo path and every "which restaurant is this" read
            // still ask for.
            deliveryCartRestaurantID = deliveryCart.first?.merchantID
            if deliveryCart.isEmpty {
                showDeliveryCheckout = false
            }
        }
    }

    func clearDeliveryCart() {
        withAnimation(.easeOut(duration: 0.2)) {
            deliveryCart = []
            deliveryCartRestaurantID = nil
            showDeliveryCheckout = false
            // Both are properties of *this* checkout rather than standing
            // preferences: the next cart is a fresh decision about how and when
            // to get it.
            deliveryWantsPickup = false
            deliveryScheduledFor = nil
            deliveryRecipientName = ""
            deliveryRecipientPhone = ""
        }
    }

    // MARK: GojoDelivery — order lifecycle

    func placeDeliveryOrder() {
        guard !deliveryCart.isEmpty, let rid = deliveryCartRestaurantID else { return }
        // Live restaurants mean a real order: the backend prices it and owns the
        // fulfilment timeline. Everything below is the offline demo.
        //
        // `deliveryCartIsLive` asks about *every* kitchen in the cart, not just
        // the first: since Phase 4 M3 a cart can span restaurants, and sending
        // one the server has never heard of would 404 a checkout that the demo
        // can run perfectly well on its own.
        if deliveryCartIsLive {
            placeLiveDeliveryOrder(merchantID: rid)
            return
        }
        deliveryOrderRestaurantID = rid
        deliveryOrderTotalLabel = String(format: "$%.2f", deliveryCartTotal)
        deliveryOrderSummary = deliveryCart
            .map { "\($0.qty)× \($0.item.name)" }
            .joined(separator: ", ")
        showDeliveryCheckout = false
        selectedDeliveryRestaurantID = nil
        deliveryCart = []
        deliveryCartRestaurantID = nil
        deliveryCourier = nil
        deliveryCourierProgress = 0
        deliveryRating = 0
        deliveryEtaMinutes = (deliveryOrderRestaurant?.etaMinutes ?? 20)
        withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = .confirmed }

        deliveryTask?.cancel()
        deliveryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = .preparing }

            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            deliveryCourier = SampleData.sampleCourier()
            deliveryEtaMinutes = max(8, deliveryEtaMinutes - 6)
            withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = .courierToRestaurant }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = .delivering }

            // Courier rides from the restaurant to your door.
            let steps = 24
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 0.42)) {
                    deliveryCourierProgress = Double(step) / Double(steps)
                }
                if step % 6 == 0 {
                    deliveryEtaMinutes = max(1, deliveryEtaMinutes - 2)
                }
            }

            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeInOut(duration: 0.35)) { deliveryStatus = .delivered }
        }
    }

    /// Cancels while the kitchen still has it — once the courier is moving it's locked.
    var canCancelDeliveryOrder: Bool {
        guard let s = deliveryStatus else { return false }
        return s < .delivering
    }

    func cancelDeliveryOrder() {
        if let orderID = deliveryLiveOrderID {
            cancelLiveDeliveryOrder(orderID)
            return
        }
        deliveryTask?.cancel()
        deliveryCourier = nil
        deliveryCourierProgress = 0
        deliveryOrderRestaurantID = nil
        withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = nil }
    }

    func finishDeliveryOrder() {
        if let orderID = deliveryLiveOrderID {
            finishLiveDeliveryOrder(orderID)
            return
        }
        deliveryTask?.cancel()
        if let r = deliveryOrderRestaurant {
            deliveryPastOrders.insert(DeliveryPastOrder(
                restaurantName: r.name,
                imageURL: r.imageURL,
                itemsSummary: deliveryOrderSummary,
                totalLabel: deliveryOrderTotalLabel,
                dateLabel: "Today",
                rating: deliveryRating
            ), at: 0)
        }
        deliveryCourier = nil
        deliveryCourierProgress = 0
        deliveryOrderRestaurantID = nil
        deliveryRating = 0
        withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = nil }
    }

    // MARK: Madeleine chat

    func sendMadeleine(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatMessages.append(ChatMessage(text: trimmed, fromUser: true))
        schedulePersist()

        let (reply, chip) = madeleineReply(to: trimmed)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.6...1.1)) { [weak self] in
            guard let self else { return }
            self.chatMessages.append(ChatMessage(text: reply, fromUser: false))
            if let chip {
                self.chatMessages.append(ChatMessage(text: "", fromUser: false, fileChip: chip))
            }
            self.schedulePersist()
        }
    }

    /// Lightweight on-device intent matching (prototype — no backend).
    private func madeleineReply(to text: String) -> (String, FileChip?) {
        let lower = text.lowercased()
        let name = user.name

        if lower.contains("feed") || lower.contains("summar") {
            if posts.isEmpty {
                return ("Your feed is empty right now — nothing to summarize yet. Share a post and I’ll dig in.", nil)
            }
            let top = posts.max(by: { $0.likeCount < $1.likeCount })
            let reply = "Your feed has \(posts.count) posts right now. The one doing best is from \(top?.author ?? "someone") with \(formatCount(top?.likeCount ?? 0)) likes. You have \(unreadActivityCount) unread notifications — want the highlights?"
            return (reply, FileChip(name: "feed-digest.pdf", sub: "\(posts.count) posts · 1 min read"))
        }
        if lower.contains("weekend") || lower.contains("plan") {
            return ("Here's your weekend: Saturday 10:00 — 5-a-side at Mission Dolores Park (3 spots left). Saturday night — City Night Live is streaming on GojoTV. Sunday — night market walk, weather looks clear. Want me to pin all three?", nil)
        }
        if lower.contains("football") || lower.contains("group") {
            return ("Found 3 open football groups within 4 km: Sunday League (11-a-side, competitive), Dolores 5-a-side (casual, Sat mornings), and Night Kicks (weekdays, floodlit). Want me to request an invite to any of them?", nil)
        }
        if lower.contains("homework") || lower.contains("study") || lower.contains("essay") {
            return ("Happy to help, \(name). Drop the assignment here or tell me the topic — I'll build an outline, sources, and a study plan you can actually follow.",
                    FileChip(name: "study-plan.pdf", sub: "outline · 5 steps"))
        }
        if lower.contains("ride") || lower.contains("taxi") || lower.contains("airport") || lower.contains("go to") {
            return ("I can get you a ride. Open GojoTravel and pick a destination — I'll help with options from there.", nil)
        }
        if lower.contains("sell") || lower.contains("listing") {
            return ("Selling is easy: snap a photo, set a price, and I'll suggest a category. Tap Sell in Economy to start.", nil)
        }
        if lower.contains("buy") || lower.contains("phone") || lower.contains("camera") {
            let catalog = ([featuredProduct] + products).filter { !$0.name.isEmpty }
            guard let match = catalog.first(where: { lower.contains($0.category.lowercased()) }) ?? catalog.first else {
                return ("There aren’t any Economy listings yet. Check back soon, or tap Sell if you want to list something yourself.", nil)
            }
            return ("Best match nearby: \(match.name) at \(match.price), \(match.distance) away from \(match.seller). Condition is listed as \(match.condition.lowercased()). Want me to open it?", nil)
        }
        if lower.contains("watch") || lower.contains("show") || lower.contains("movie") {
            if let pick = tvShows.randomElement()?.title ?? (tvHero.title.isEmpty ? nil : tvHero.title) {
                let progressNote = tvHero.title.isEmpty || tvHero.progress <= 0
                    ? ""
                    : " You're also \(Int(tvHero.progress * 100))% through \(tvHero.title) if you'd rather finish that."
                return ("Based on what you've been watching, try “\(pick)” tonight — it's on GojoTV.\(progressNote)", nil)
            }
            return ("GojoTV is empty right now — nothing queued to recommend yet.", nil)
        }
        if lower.contains("hello") || lower.contains("hey") || lower.contains("hi ") || lower == "hi" {
            return ("Hey \(name)! I can plan your weekend, summarize your feed, find rides, or hunt deals on Economy. What do you need?", nil)
        }
        if lower.contains("thank") {
            return ("Anytime. That's what I'm here for.", nil)
        }
        let fallbacks = [
            "Got it — I'll keep an eye on that. Anything else while I'm at it?",
            "Noted. I'll surface anything relevant in your feed and ping you.",
            "On it. Give me a moment and check your notifications.",
            "Interesting — tell me a bit more and I can act on it.",
        ]
        return (fallbacks.randomElement()!, nil)
    }
}
