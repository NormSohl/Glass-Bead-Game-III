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

    @Environment(\.scenePhase) private var scenePhase

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
        #if os(iOS)
        // Norm: swiping up from the bottom to close the app on iPad starts a note that keeps
        // sounding for about a second before fading out. The swipe gesture's own initial touch-
        // down originates right where the graph's own DragGesture lives (minimumDistance: 0,
        // .defersSystemGestures(on: .all) - see HitTestView), so it's briefly seen as a real
        // graph touch before iOS's system gesture recognizer takes over and steals it; the
        // stolen touch's own onEnded may never fire, so nothing ever calls endGraphTouch. Rather
        // than carve out a dead zone at the bottom edge (real graph interactivity lost there for
        // an edge case), force everything silent as soon as the app leaves the foreground - safe
        // and correct regardless of what left a touch stuck, matching how panic() is already
        // meant to be used.
        //
        // Reacts to .inactive, not just .background - Norm, after testing: .background alone
        // (which iOS delays until the close animation finishes, ~a second) stopped the *stuck*
        // case cleanly, but with a pedal-held note already sounding, the stray touch's own hit-
        // test could still write a brief pitch-jump/retrigger onto it before .background ever
        // fired - a delayed panic can silence what follows but can't undo a glitch that already
        // happened. .inactive fires right as the swipe begins instead, closing that gap. Traded
        // off deliberately, with Norm's explicit go-ahead: .inactive also fires for things like
        // Control Center or a phone call banner, so a pedal-held note won't survive those either
        // now, not just an actual close.
        //
        // iOS-only - macOS's own equivalent, the window losing focus via Cmd-Tab, is a normal
        // way to keep a sustained drone going in the background, not something to silence.
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                sound.panic()
            }
        }
        #endif
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

