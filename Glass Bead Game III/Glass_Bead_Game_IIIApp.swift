//
//  Glass_Bead_Game_IIIApp.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 2/22/24.
//

import SwiftUI

// utility class for the app
var sound = Sound() // sound is a generic class that wraps both the audio out and midi out classes

// Process-wide shared state (like `sound` above), not owned by any one window - needed for the
// external-display audience window (Stage 2+ of that feature), whose UIWindowSceneDelegate is
// instantiated by UIKit itself when a scene connects, entirely outside the SwiftUI view tree,
// so it can't reach anything via .environmentObject or a view's own init. ContentView now wraps
// these same instances rather than constructing its own - see GraphScaleState.swift's own
// header comment for the fuller reasoning.
var appSettings = AppSettings()
var appRecordingState = RecordingState(settings: appSettings, sampleRateProvider: { sound.audio.sampleRate })
var graphScaleState = GraphScaleState(settings: appSettings)

@main
struct GlassBeadGameIIIApp: App {
    #if os(iOS)
    // Only needed to name a delegate for the external-display scene role - see AppDelegate's own
    // header comment. Ordinary launch and the main window are untouched by this.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    init() {
        sound.initSound()
        #if os(macOS)
        // AppKit's tooltip hover delay (NSInitialToolTipDelay, milliseconds) isn't exposed as a
        // System Settings toggle, but it IS just a standard user default - and since defaults
        // are per-bundle-identifier, registering it here only changes this app's own tooltip
        // delay, not the system default or any other app's. Norm: the toolbar tooltips (piano
        // keys, portamento, pedal, drone, gear) were taking a while to first appear - macOS's
        // out-of-the-box default is on the order of a second or more.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        // Window width should exactly match its content (graph + Z-slider, no dead space) - a
        // plain generous defaultSize left a gap, since windowResizability only bounds later
        // manual resizes, it doesn't shrink an oversized initial size down to fit. So this
        // computes the actual content size ContentView's own layout would produce at the
        // screen's available height (square graph + ZSliderView's fixed 70pt), rather than
        // guessing a width.
        .defaultSize(idealWindowSize())
    }
}

#if os(macOS)
import AppKit

// Shared by both the launch-time defaultSize above and ContentView's live aspect-ratio lock, so
// the two can never drift apart into two different "correct" sizes.
func idealWindowSize() -> CGSize {
    let titleBarAllowance: CGFloat = 28
    let zSliderWidth: CGFloat = 70

    let screenHeight = NSScreen.main?.visibleFrame.height ?? 1000
    let graphHeight = screenHeight - titleBarAllowance
    let width = graphHeight + zSliderWidth
    let height = graphHeight
    return CGSize(width: width, height: height)
}
#else
func idealWindowSize() -> CGSize {
    CGSize(width: 800, height: 552)
}
#endif

