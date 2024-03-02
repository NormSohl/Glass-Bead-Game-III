//
//  ContentView.swift
//  GBG_01
//
//  Created by Norman Sohl on 5/9/22.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()
    
    var body: some View {
        HStack(spacing:0) {
            
            ZStack(){
                // create scale and diamonds on the fly
                let intLimit = LimitMap[settings.selectedLimit]
                let scale = Scale(limit: intLimit ?? 0, highestRatio: settings.highestRatio)
                let diamonds = Diamonds(scale:scale)
                GraphView(scale: scale,
                          diamonds: diamonds,
                          settings: settings
                )//.rotationEffect(.degrees(-45.0)).scaleEffect(CGSize(width: 0.73, height: 0.73))
            }
            .aspectRatio(1/1, contentMode: .fit)
            .layoutPriority(1)
            .background()
            
            ControlView(settings: settings).background().frame(minWidth: 200)// all ui in right panel goes here
        }
        .frame (minWidth: 800, minHeight: 500)
    }
}
