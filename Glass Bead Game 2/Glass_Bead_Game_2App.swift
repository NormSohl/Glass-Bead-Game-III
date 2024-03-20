//
//  Glass_Bead_Game_2App.swift
//  Glass Bead Game 2
//
//  Created by Norman Sohl on 2/22/24.
//

import SwiftUI

// utility classes for the app
//var audio = Audio
//var audio = sound.Audio()
//var midi = sound.Midi()
var sound = Sound()

@main
struct GBG_01App: App {
    
    init() {
        _ = sound.midi.noteList.octaves  // any call to trigger lazy instantiation
        sound.audio.stopAudio() // any call to trigger lazy instantiation
        // test the midi code - this should be removed after testing
        sound.midi.initMidi() // need a better function to trigger lazy instantiation, otherwise destinations don't show up in control in view
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
