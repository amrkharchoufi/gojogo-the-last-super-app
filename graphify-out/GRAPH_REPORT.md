# Graph Report - .  (2026-07-17)

## Corpus Check
- 75 files · ~163,665 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1085 nodes · 2763 edges · 62 communities (59 shown, 3 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 199 edges (avg confidence: 0.81)
- Token cost: 340,610 input · 9,600 output

## Community Hubs (Navigation)
- Domain Models & Feed Actions
- Session Persistence
- Media Editing Tools
- Video Player Engine
- Welcome & Compose Kinds
- Long-Form Player UI
- Scroll Chrome Coordinator
- AppState Navigation Actions
- AppState Media Actions
- Glass Theme System
- Media Images & Avatars
- App Delegate & Chat Scroll
- My World Screen Shell
- Shorts Feed
- Audio Recorder
- Home Feed Cards
- Chat Bubbles UI
- Economy Marketplace
- Story Viewer
- Screen Modules & Frameworks
- Feed Viewport Observer
- World Messaging Logic
- Gojo TV
- Profile Grid
- Interest Onboarding Layout
- App Entry & Travel Map
- Profile & Madeleine Actions
- Compose & Share Actions
- Travel Map Camera
- Design Components
- Activity & DM Screens
- Travel Ride UI
- Madeleine Home
- World Message Kinds
- Story & Like Actions
- Meme Sample Images
- Onboarding Flow Shell
- Root Navigation
- Watch Feed
- Chat Apps Drawer
- Birth Year Onboarding
- User & Story Actions
- Travel Phases
- World Chat Module
- Name Onboarding
- App Tabs Enum
- Mapbox Config
- Madeleine Orb
- Batman Sample Art
- Email Signup
- Auth Phases
- Comments Sheet
- Compose Post View
- BMW Sample Art
- Porsche Desert Art
- Porsche Dubai Art
- Picked Movie Transfer
- App Icon Branding
- Logo Branding
- Cats Duo Sample
- Cosmic Face Sample
- Lighthouse Sample

## God Nodes (most connected - your core abstractions)
1. `AppState` - 167 edges
2. `Color` - 94 edges
3. `Text` - 50 edges
4. `SwiftUI` - 41 edges
5. `LongFormPlayerModel` - 36 edges
6. `Post` - 33 edges
7. `WorldConversation` - 31 edges
8. `VideoItem` - 29 edges
9. `WorldMessage` - 29 edges
10. `SampleData` - 29 edges

## Surprising Connections (you probably didn't know these)
- `Msg` --calls--> `Color`  [INFERRED]
  GojoGo/Navigation/GGTabBar.swift → GojoGo/DesignSystem/Theme.swift
- `storyCell()` --calls--> `Text`  [INFERRED]
  GojoGo/Screens/StoriesBrowserView.swift → GojoGo/DesignSystem/Theme.swift
- `AppState` --calls--> `GGUser`  [INFERRED]
  GojoGo/Models/AppState.swift → GojoGo/Models/Models.swift
- `SampleData` --calls--> `circles`  [INFERRED]
  GojoGo/Models/SampleData.swift → GojoGo/Models/Models.swift
- `SampleData` --calls--> `WorldMessage`  [INFERRED]
  GojoGo/Models/SampleData.swift → GojoGo/Models/Models.swift

## Import Cycles
- None detected.

## Communities (62 total, 3 thin omitted)

### Community 0 - "Domain Models & Feed Actions"
Cohesion: 0.08
Nodes (55): Equatable, ActivityItem, ActivityKind, comment, follow, like, mention, order (+47 more)

### Community 1 - "Session Persistence"
Cohesion: 0.09
Nodes (27): Codable, CachedChatMessage, CachedComment, CachedCommentThread, CachedInterest, CachedPerson, CachedPost, CachedPostMedia (+19 more)

### Community 2 - "Media Editing Tools"
Cohesion: 0.05
Nodes (42): CaseIterable, CGSize, WatchSubFeed, feed, tv, CropAspect, original, square (+34 more)

### Community 3 - "Video Player Engine"
Cohesion: 0.09
Nodes (25): AnyClass, AVKit, AVLayerVideoGravity, AVPlayer, AVPlayerLayer, AVRoutePickerView, Coordinator, Entry (+17 more)

### Community 4 - "Welcome & Compose Kinds"
Cohesion: 0.06
Nodes (38): ButtonStyle, EnvironmentKey, GoogleMark, AppState, CGFloat, Void, WelcomeView, ComposeMediaKind (+30 more)

### Community 5 - "Long-Form Player UI"
Cohesion: 0.09
Nodes (24): Combine, Float, FullscreenIgnoreSafeArea, LongFormFullscreenChrome, LongFormInlineChrome, LongFormOrientation, LongFormPlayerModel, LongFormPlayerSurface (+16 more)

### Community 6 - "Scroll Chrome Coordinator"
Cohesion: 0.10
Nodes (22): ChromeScrollGate, Coordinator, HeartBurstOverlay, ScrollChromeTracker, ScrollOffsetReader, Binding, Bool, CGFloat (+14 more)

### Community 7 - "AppState Navigation Actions"
Cohesion: 0.07
Nodes (5): AppState, Never, Task, Void, Set

### Community 8 - "AppState Media Actions"
Cohesion: 0.09
Nodes (3): UUID, shorts, people

### Community 9 - "Glass Theme System"
Cohesion: 0.15
Nodes (13): Glass, Font, GGBackground, GlassBackground, GlassCapsule, LiquidGlassBackground, Bool, CGFloat (+5 more)

### Community 10 - "Media Images & Avatars"
Cohesion: 0.10
Nodes (16): ContentMode, PressableStyle, Configuration, MediaImage, Bool, CGFloat, Data, String (+8 more)

### Community 11 - "App Delegate & Chat Scroll"
Cohesion: 0.13
Nodes (18): AppDelegate, Any, Bool, UIInterfaceOrientationMask, Coordinator, Binding, CGFloat, Context (+10 more)

### Community 12 - "My World Screen Shell"
Cohesion: 0.11
Nodes (15): Color, IMColor, Content, Void, MyWorldView, NewWorldMessageSheet, AppState, Bool (+7 more)

### Community 13 - "Shorts Feed"
Cohesion: 0.12
Nodes (14): ShortCard, ShortsView, AppState, Bool, CGFloat, Int, String, UUID (+6 more)

### Community 14 - "Audio Recorder"
Cohesion: 0.14
Nodes (13): AVAudioRecorder, AVAudioRecorderDelegate, AudioRecorderController, AudioRecorderSheet, Bool, CGFloat, Data, String (+5 more)

### Community 15 - "Home Feed Cards"
Cohesion: 0.13
Nodes (14): HomeView, InstagramPostCard, AppState, CGFloat, Int, PhotosPickerItem, Story, PostActions (+6 more)

### Community 16 - "Chat Bubbles UI"
Cohesion: 0.20
Nodes (10): Text, String, Void, BubbleShape, AppState, Bool, WorldChatView, RoundedRectangle (+2 more)

### Community 17 - "Economy Marketplace"
Cohesion: 0.14
Nodes (12): Product, EconomyView, ProductDetailView, SellerChatView, SellListingSheet, AppState, Binding, Bool (+4 more)

### Community 18 - "Story Viewer"
Cohesion: 0.22
Nodes (9): StoryViewer, AppState, Bool, CGFloat, Double, Gesture, Int, Story (+1 more)

### Community 19 - "Screen Modules & Frameworks"
Cohesion: 0.19
Nodes (8): AVFoundation, CoreImage, CoreImage.CIFilterBuiltins, ChatBubble, PhotosUI, SwiftUI, UIKit, UniformTypeIdentifiers

### Community 20 - "Feed Viewport Observer"
Cohesion: 0.22
Nodes (7): CADisplayLink, FeedViewportObserver, FeedViewportUIView, Bool, Context, Void, UIView

### Community 21 - "World Messaging Logic"
Cohesion: 0.24
Nodes (3): Date, WorldConversation, WorldMessage

### Community 22 - "Gojo TV"
Cohesion: 0.18
Nodes (11): GojoTVView, RailStyle, landscape, poster, AppState, Bool, Double, Int (+3 more)

### Community 23 - "Profile Grid"
Cohesion: 0.16
Nodes (14): ProfileGridItem, ProfileGridKind, image, text, video, ProfileGridTarget, longForm, post (+6 more)

### Community 24 - "Interest Onboarding Layout"
Cohesion: 0.16
Nodes (12): FlowLayout, InterestChip, OnboardingInterestsView, AppState, Bool, CGFloat, CGRect, Int (+4 more)

### Community 25 - "App Entry & Travel Map"
Cohesion: 0.16
Nodes (11): App, CoreLocation, GojoGoApp, DriverMapMarker, String, TravelPin, TravelPinKind, dropoff (+3 more)

### Community 26 - "Profile & Madeleine Actions"
Cohesion: 0.18
Nodes (3): Double, Int, String

### Community 28 - "Travel Map Camera"
Cohesion: 0.26
Nodes (7): CLLocationCoordinate2D, CLLocationDirection, Bool, CGFloat, Viewport, TravelCamera, TravelMapView

### Community 29 - "Design Components"
Cohesion: 0.33
Nodes (11): AccentButton, AvatarBlob, MediaPlaceholder, MonoChip, SectionHeader, StripePattern, Bool, CGFloat (+3 more)

### Community 30 - "Activity & DM Screens"
Cohesion: 0.24
Nodes (8): ActivityView, DirectMessageView, EditProfileSheet, PostViewerSheet, AppState, Binding, Bool, String

### Community 31 - "Travel Ride UI"
Cohesion: 0.21
Nodes (6): GojoTravelView, AppState, Bool, String, Viewport, Label

### Community 32 - "Madeleine Home"
Cohesion: 0.24
Nodes (7): GGColor, FileChipView, MadeleineHomeView, AppState, Bool, String, LinearGradient

### Community 33 - "World Message Kinds"
Cohesion: 0.18
Nodes (11): WorldMessageKind, audio, carousel, emoji, file, location, photo, system (+3 more)

### Community 35 - "Meme Sample Images"
Cohesion: 0.22
Nodes (8): Sample Cockpit Cat Image, Fighter Pilot Cat Selfie (AI-generated meme), Sample Media Asset for GojoGo Video/Feed Content, Sample Pilot Cat Image, Meme-Style Cat Sample Content, SampleSpidey Image Asset, Spider-Man Motivational Poster, Quote: They Won't Care Until You Win

### Community 36 - "Onboarding Flow Shell"
Cohesion: 0.22
Nodes (7): MadeleineBubble, OnboardingFlow, ProgressDots, AppState, Content, Int, String

### Community 37 - "Root Navigation"
Cohesion: 0.25
Nodes (7): AppState, MainAppView, RootView, Story, AppState, Bool, Hasher

### Community 38 - "Watch Feed"
Cohesion: 0.28
Nodes (8): formatCount(), LongFormFeedView, AppState, CGFloat, Int, String, VideoCard, WatchView

### Community 39 - "Chat Apps Drawer"
Cohesion: 0.22
Nodes (8): WorldAppAction, audio, camera, location, photos, polls, sendLater, stickers

### Community 40 - "Birth Year Onboarding"
Cohesion: 0.43
Nodes (5): OnboardingYearView, AppState, CGFloat, Gesture, Int

### Community 42 - "Travel Phases"
Cohesion: 0.25
Nodes (8): TravelPhase, choosingRide, completed, enRoute, home, inTrip, matching, searching

### Community 43 - "World Chat Module"
Cohesion: 0.29
Nodes (5): AnyTransition, MessageBubbleAppear, TypingIndicatorBubble, WorldMessageKind, MapKit

### Community 44 - "Name Onboarding"
Cohesion: 0.33
Nodes (5): OnboardingNameView, AppState, Bool, String, Void

### Community 45 - "App Tabs Enum"
Cohesion: 0.29
Nodes (7): AppTab, economy, home, madeleine, search, travel, watch

### Community 46 - "Mapbox Config"
Cohesion: 0.40
Nodes (4): Foundation, MapboxConfig, Bool, String

### Community 47 - "Madeleine Orb"
Cohesion: 0.47
Nodes (5): AuroraBlobs, MadeleineOrb, MiniOrb, Bool, CGFloat

### Community 48 - "Batman Sample Art"
Cohesion: 0.50
Nodes (5): SampleBatman Asset Image (Batman over Gotham in Starry Night style), Batman Character (caped silhouette on rooftop), Gothic Night Cityscape (Gotham-style spires and lit windows), Sample Media Thumbnail Asset (bundled demo content for GojoGo), Van Gogh Starry Night Painterly Style (swirling impasto sky)

### Community 49 - "Email Signup"
Cohesion: 0.40
Nodes (3): EmailSignUpView, AppState, Bool

### Community 50 - "Auth Phases"
Cohesion: 0.40
Nodes (5): AuthPhase, app, email, onboarding, welcome

### Community 51 - "Comments Sheet"
Cohesion: 0.40
Nodes (4): CommentsSheet, AppState, Bool, UUID

### Community 52 - "Compose Post View"
Cohesion: 0.40
Nodes (5): ComposePostView, AppState, Bool, Data, PhotosPickerItem

### Community 53 - "BMW Sample Art"
Cohesion: 0.50
Nodes (4): Sample BMW M4 Poster Image, Automotive Poster Art Style, BMW M4 Competition, GojoGo Sample Media Asset

### Community 54 - "Porsche Desert Art"
Cohesion: 0.50
Nodes (4): Sample Porsche Desert Photo, Desert Red-Rock Canyon Setting, Purple Porsche 911 GT3 RS, Sample Media Asset for Video Feed UI

### Community 55 - "Porsche Dubai Art"
Cohesion: 0.67
Nodes (4): Dubai Skyline with Burj Khalifa, Porsche 911 GT3 RS (White, Rear Wing, GT3 RS Livery), Bundled Sample Media Asset for GojoGo Feeds, Sample Photo: Porsche 911 GT3 RS with Dubai Skyline

### Community 56 - "Picked Movie Transfer"
Cohesion: 0.50
Nodes (4): PickedMovie, URL, Transferable, TransferRepresentation

### Community 57 - "App Icon Branding"
Cohesion: 1.00
Nodes (3): GojoGo App Icon, Gojo Brand Identity (lowercase 'gojo' wordmark, teal-and-white on black), GojoGo Superapp

### Community 58 - "Logo Branding"
Cohesion: 1.00
Nodes (3): Dark Background with Teal Accent Theme, GojoGo Brand Identity, GojoGo Logo Image

### Community 59 - "Cats Duo Sample"
Cohesion: 0.67
Nodes (3): SampleCatsDuo Image Asset, Two Cats in Traditional Headwear (Meme-Style Photo), Sample Media Thumbnail Content

### Community 60 - "Cosmic Face Sample"
Cohesion: 0.67
Nodes (3): Sample Cosmic Face Artwork, Sample Media Placeholder Content, Vertical Short-Form Video Thumbnail

### Community 61 - "Lighthouse Sample"
Cohesion: 0.67
Nodes (3): SampleLighthouse Image Asset, Paper-Cut Style Lighthouse Artwork (portrait 9:16 illustration: white lighthouse on rocky cliff, radiant golden sun halo breaking through layered blue storm clouds, swirling ocean waves below), Sample Media Thumbnail for GojoGo Video/Content Feeds

## Knowledge Gaps
- **104 isolated node(s):** `myWorld`, `collections`, `home`, `watch`, `madeleine` (+99 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppState` connect `AppState Navigation Actions` to `Domain Models & Feed Actions`, `Session Persistence`, `Story & Like Actions`, `Video Player Engine`, `Media Editing Tools`, `AppState Media Actions`, `User & Story Actions`, `Travel Phases`, `App Tabs Enum`, `Audio Recorder`, `Economy Marketplace`, `Auth Phases`, `Screen Modules & Frameworks`, `World Messaging Logic`, `Profile & Madeleine Actions`, `Compose & Share Actions`?**
  _High betweenness centrality (0.217) - this node is a cross-community bridge._
- **Why does `SwiftUI` connect `Screen Modules & Frameworks` to `Domain Models & Feed Actions`, `Session Persistence`, `Media Editing Tools`, `Video Player Engine`, `Welcome & Compose Kinds`, `Long-Form Player UI`, `Scroll Chrome Coordinator`, `Glass Theme System`, `My World Screen Shell`, `Shorts Feed`, `Economy Marketplace`, `Gojo TV`, `Profile Grid`, `Interest Onboarding Layout`, `App Entry & Travel Map`, `Design Components`, `Activity & DM Screens`, `Madeleine Home`, `Meme Sample Images`, `Onboarding Flow Shell`, `Root Navigation`, `Watch Feed`, `Birth Year Onboarding`, `World Chat Module`, `Name Onboarding`, `Madeleine Orb`, `Email Signup`, `Comments Sheet`?**
  _High betweenness centrality (0.166) - this node is a cross-community bridge._
- **Why does `Color` connect `My World Screen Shell` to `Domain Models & Feed Actions`, `Session Persistence`, `Welcome & Compose Kinds`, `Long-Form Player UI`, `Glass Theme System`, `Media Images & Avatars`, `Shorts Feed`, `Audio Recorder`, `Home Feed Cards`, `Chat Bubbles UI`, `Economy Marketplace`, `Story Viewer`, `World Messaging Logic`, `Gojo TV`, `Profile & Madeleine Actions`, `Design Components`, `Activity & DM Screens`, `Travel Ride UI`, `Madeleine Home`, `Birth Year Onboarding`, `User & Story Actions`, `Name Onboarding`?**
  _High betweenness centrality (0.116) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `Color` (e.g. with `Msg` and `.waveformPoster()`) actually correct?**
  _`Color` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `myWorld`, `collections`, `home` to the rest of the system?**
  _104 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Domain Models & Feed Actions` be split into smaller, more focused modules?**
  _Cohesion score 0.07995520716685331 - nodes in this community are weakly interconnected._
- **Should `Session Persistence` be split into smaller, more focused modules?**
  _Cohesion score 0.08961748633879782 - nodes in this community are weakly interconnected._