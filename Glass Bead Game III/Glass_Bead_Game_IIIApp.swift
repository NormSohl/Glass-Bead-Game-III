//
//  Glass_Bead_Game_IIIApp.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 2/22/24.
//

import SwiftUI

// utility class for the app
var sound = Sound() // sound is a generic class that wraps both the audio out and midi out classes

@main
struct GlassBeadGameIIIApp: App {
    
    init() {
        sound.initSound()
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
        // screen's available height (square graph + ZSliderView's fixed 70pt, when shown +
        // RootIndicatorView's fixed 12pt), rather than guessing a width. Launch always starts
        // with the sequencer panel hidden and the 3rd moving tone off (AppSettings' own
        // defaults), so this uses that ratio - see ContentView's WindowAspectLockView for the
        // version that also accounts for both toggles live.
        .defaultSize(idealWindowSize(sequencerShown: false, thirdToneShown: false))
    }
}

#if os(macOS)
import AppKit

// Shared by both the launch-time defaultSize above and ContentView's live aspect-ratio lock, so
// the two can never drift apart into two different "correct" sizes.
func idealWindowSize(sequencerShown: Bool, thirdToneShown: Bool) -> CGSize {
    let titleBarAllowance: CGFloat = 28
    let rootIndicatorHeight: CGFloat = 12
    let zSliderWidth: CGFloat = thirdToneShown ? 70 : 0
    let sequencerHeight: CGFloat = sequencerShown ? 300 : 0

    let screenHeight = NSScreen.main?.visibleFrame.height ?? 1000
    let graphHeight = screenHeight - titleBarAllowance - sequencerHeight - rootIndicatorHeight
    let width = graphHeight + zSliderWidth
    let height = graphHeight + rootIndicatorHeight + sequencerHeight
    return CGSize(width: width, height: height)
}
#else
func idealWindowSize(sequencerShown: Bool, thirdToneShown: Bool) -> CGSize {
    CGSize(width: 800, height: sequencerShown ? 852 : 552)
}
#endif

