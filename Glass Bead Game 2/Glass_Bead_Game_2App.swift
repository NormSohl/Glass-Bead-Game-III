//
//  Glass_Bead_Game_2App.swift
//  Glass Bead Game 2
//
//  Created by Norman Sohl on 2/22/24.
//

import SwiftUI

var triad = Triad()
var audio = AudioUtil()
var midiTest = MidiTest()

@main
struct GBG_01App: App {
    
    init() {
        audio.stopAudio() // any call to trigger lazy instantiation
        let _ = triad.getRootPitch() // same
        // test the midi code - this should be removed after testing
        midiTest.test()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
