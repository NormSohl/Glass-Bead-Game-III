//
//  SeqApp.swift
//  Seq
//
//  Entry point for the standalone sequencer app - see the standalone-sequencer phase-2 plan.
//  Constructs the document/settings state and shows the ported sequencer UI (SequencerView) as
//  the entire window's content - Seq has no other screens yet (no MIDI setup UI until Step 3,
//  no save/load UI until Step 5).
//

import SwiftUI
import GBGCore
import GBGSound

@main
struct SeqApp: App {
    @StateObject private var settings = SeqSettings()
    @StateObject private var sequencer: SequencerState
    private let scale: Scale

    init() {
        let initialSettings = SeqSettings()
        _settings = StateObject(wrappedValue: initialSettings)
        _sequencer = StateObject(wrappedValue: SequencerState(settings: initialSettings))
        // Same defaults as Graph's own initial Scale (11-limit, a fifth above root to an octave
        // below) - Seq doesn't need Graph's harmonics-limit picker UI, just a working scale.
        scale = Scale(limit: 11, highestRatio: 3.0 / 1.0, lowestRatio: 1.0 / 2.0)
    }

    var body: some Scene {
        WindowGroup {
            SequencerView(settings: settings, sequencer: sequencer, scale: scale)
        }
    }
}
