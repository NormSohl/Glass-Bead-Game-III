//
//  SeqApp.swift
//  Seq
//
//  Entry point for the standalone sequencer app. Constructs the settings and sequencer state and
//  shows SequencerView as the entire window's content.
//

import SwiftUI
import GBGCore
import GBGSound

@main
struct SeqApp: App {
    @StateObject private var settings: SeqSettings
    @StateObject private var sequencer: SequencerState

    init() {
        let initialSettings = SeqSettings()
        _settings = StateObject(wrappedValue: initialSettings)
        _sequencer = StateObject(wrappedValue: SequencerState(settings: initialSettings))
    }

    var body: some Scene {
        WindowGroup {
            SequencerView(settings: settings, sequencer: sequencer)
        }
    }
}
