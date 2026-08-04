import SwiftUI
import UIKit
import UserNotifications
import MapboxMaps

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MapboxOptions.accessToken = MapboxConfig.accessToken
        // Larger shared HTTP cache so cacheable responses (and any AsyncImage still
        // in use) survive; media itself is cached explicitly by ImageCache.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 512 * 1024 * 1024)
        UNUserNotificationCenter.current().delegate = self
        // Every SwiftUI ScrollView/List is backed by UIScrollView — make drag
        // dismiss the keyboard app-wide, including sheets.
        UIScrollView.appearance().keyboardDismissMode = .interactive
        DispatchQueue.main.async {
            KeyboardDismissInstaller.shared.installIfNeeded()
        }
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

    // MARK: APNs registration

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushRegistrar.shared.updateToken(hex)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    // Show activity pushes while the app is foregrounded, and refresh the feed.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        PushRegistrar.shared.onPushReceived?(notification.request.content.userInfo)
        // Stay quiet for a message push about the thread the user is already
        // reading — the bubble is already on screen. Other chats still banner.
        let info = notification.request.content.userInfo
        if info["type"] as? String == "message",
           let idString = info["conversationId"] as? String,
           let conversationID = UUID(uuidString: idString),
           conversationID == PushRegistrar.shared.activeConversationID {
            return []
        }
        return [.banner, .badge, .sound]
    }

    // Tapping a push opens the app and refreshes the activity feed.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        PushRegistrar.shared.onPushReceived?(response.notification.request.content.userInfo)
    }
}

@main
struct GojoGoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        // Phase G, and it has to be first. The notification extension can only
        // read keychain items in the shared access group, and everything this
        // device already has — the auth tokens and, critically, the libsignal
        // identity — was written to the app's own group. Moving them here, in
        // `init`, means nothing has read a token or an identity yet: there is
        // one process, no ratchet in flight, and no chance of a half-migrated
        // read minting a second identity and changing this device's safety
        // number with every contact it has.
        KeychainStore.migrateToSharedAccessGroup()

        // Gate for Phase C: verifies the five protocol stores against the real
        // Double Ratchet before any live message depends on them. Debug-only.
        #if DEBUG
        WorldSignalSelfCheck.run()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(appState.appTheme.colorScheme)
                .tint(GGColor.accent)
                .dismissesKeyboard()
                .animation(.easeInOut(duration: 0.3), value: appState.appTheme)
        }
    }
}
