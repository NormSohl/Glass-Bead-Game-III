//
//  Glass_Bead_Game_2App.swift
//  Glass Bead Game 2
//
//  Created by Norman Sohl on 2/22/24.
//

import SwiftUI

// utility class for the app
var sound = Sound() // sound is a generic class that wraps both the audio out and midi out classes

@main
struct GBG_01App: App {
    
    init() {
        sound.initSound()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

