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
        PushRegistrar.shared.onPushReceived?()
        return [.banner, .badge, .sound]
    }

    // Tapping a push opens the app and refreshes the activity feed.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        PushRegistrar.shared.onPushReceived?()
    }
}

@main
struct GojoGoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(appState.appTheme.colorScheme)
                .tint(GGColor.accent)
                .animation(.easeInOut(duration: 0.3), value: appState.appTheme)
        }
    }
}
