//
//  ContentView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 5/9/22.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()
    
    var body: some View {
        HStack(spacing:0) {
            ZStack(){
                Color.black.ignoresSafeArea(.all)
                // create scale and diamonds on the fly
                let intLimit = limitMap[settings.selectedLimit]
                let scale = Scale(limit: intLimit ?? 0, highestRatio: settings.highestRatio, lowestRatio: settings.lowestRatio)
                let diamonds = Diamonds(scale:scale)
                GraphView(scale: scale,
                          diamonds: diamonds,
                          settings: settings
                ).rotationEffect(.degrees(settings.viewRotation)).scaleEffect(CGSize(width: settings.viewScale, height: settings.viewScale)).offset(x: settings.viewOffsetX, y: settings.viewOffsetY)
            }
            .aspectRatio(1/1, contentMode: settings.contentMode)
            .layoutPriority(1)
            .background()
            .animation(/*@START_MENU_TOKEN@*/.easeIn/*@END_MENU_TOKEN@*/, value: settings.viewRotation)
            
            ControlView(settings: settings).background().frame(minWidth: 200)// all ui in right panel goes here
        }
        .frame (minWidth: 800, minHeight: 500)
    }
}
