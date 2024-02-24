//
//  Glass_Bead_Game_2App.swift
//  Glass Bead Game 2
//
//  Created by Norman Sohl on 2/22/24.
//

import SwiftUI

var triad = Triad()
var audio = AudioUtil()

@main
struct GBG_01App: App {
    //@Environment(\.scenePhase) var scenePhase
    //var audio = AudioUtil()
    init() {
        audio.stopAudio() // any call to trigger lazy instantiation
        let _ = triad.getRootPitch() // same
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()//audio:audio)
        }
        //#if os(macOS)
        //.windowStyle(.hiddenTitleBar)
        //#endif
    }
}
