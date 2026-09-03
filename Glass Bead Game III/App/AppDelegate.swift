//
//  AppDelegate.swift
//  Glass Bead Game III
//
//  UIKit bridging, needed only for the external-display scene role - SwiftUI's plain
//  Scene/WindowGroup has no way to name a delegate for a scene it doesn't itself create. The
//  ordinary app window is untouched: returning the default, delegate-less configuration for
//  .windowApplication leaves SwiftUI's own WindowGroup fully in charge of it, exactly as before
//  this file existed. Only .windowExternalDisplay (an HDMI/AirPlay connection) gets routed to
//  ExternalDisplaySceneDelegate.
//
//  iOS-only - Mac already gets a second display for free at the OS/window-manager level (see
//  the external-display plan's own "explicitly out of scope" section).
//

#if os(iOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        switch connectingSceneSession.role {
        case .windowExternalDisplay:
            let config = UISceneConfiguration(name: "External Display Configuration", sessionRole: connectingSceneSession.role)
            config.delegateClass = ExternalDisplaySceneDelegate.self
            return config
        default:
            return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        }
    }
}
#endif
