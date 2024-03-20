//
//  Glass_Bead_Game_2App.swift
//  Glass Bead Game 2
//
//  Created by Norman Sohl on 2/22/24.
//

import SwiftUI

// utility classes for the app
var audio = Audio()
var midi = Midi()
var audioGeneric = AudioGeneric()

@main
struct GBG_01App: App {
    
    init() {
        _ = midi.noteList.octaves  // any call to trigger lazy instantiation
        audio.stopAudio() // any call to trigger lazy instantiation
        // test the midi code - this should be removed after testing
        midi.initMidi() // need a better function to trigger lazy instantiation, otherwise destinations don't show up in control in view
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
