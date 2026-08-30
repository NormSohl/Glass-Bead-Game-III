//
//  SeqApp.swift
//  Seq
//
//  Entry point for the standalone sequencer app - see the standalone-sequencer
//  foundation plan (phase 2) for context. This is currently just a skeleton target;
//  the actual sequencer document model and piano-roll UI are ported in a later step.
//

import SwiftUI
// Imported here (unused for now) to prove this target can see both packages - the same
// GBGCore/GBGSound the main "Glass Bead Game III" target already depends on.
import GBGCore
import GBGSound

@main
struct SeqApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
