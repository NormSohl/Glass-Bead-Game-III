//
//  ExternalDisplaySceneDelegate.swift
//  Glass Bead Game III
//
//  Builds the audience-facing window the instant an external display (wired or AirPlay)
//  connects - see AppDelegate's own header comment for how this delegate gets picked. No
//  sceneDidDisconnect override needed: UIKit tears the window down on its own when the scene
//  session goes away (display unplugged, AirPlay session ends), and AudienceGraphView holds no
//  state of its own to clean up - it only reads the shared globals ContentView already keeps
//  alive for the whole process lifetime.
//

#if os(iOS)
import UIKit
import SwiftUI

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: AudienceGraphView())
        self.window = window
        window.makeKeyAndVisible()
    }
}
#endif
