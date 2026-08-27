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
    }
}

