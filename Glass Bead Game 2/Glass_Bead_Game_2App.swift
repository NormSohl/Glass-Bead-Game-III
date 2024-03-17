//
//  Glass_Bead_Game_2App.swift
//  Glass Bead Game 2
//
//  Created by Norman Sohl on 2/22/24.
//

import SwiftUI

var triad = Triad()
var audio = Audio()
var midi = Midi()
var audioGeneric = AudioGeneric()
var noteList = NoteList()
@main
struct GBG_01App: App {
    
    init() {
        _ = noteList.octaves  // any call to trigger lazy instantiation
        audio.stopAudio() // any call to trigger lazy instantiation
        let _ = triad.getRootPitch() // same
        // test the midi code - this should be removed after testing
        midi.test() // need a better function to trigger lazy instantiation, otherwise destinations don't show up in control in view
        //audioGeneric.testCentsToPitchBend()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
