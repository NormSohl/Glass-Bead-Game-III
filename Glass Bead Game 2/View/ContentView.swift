//
//  ContentView.swift
//  GBG_01
//
//  Created by Norman Sohl on 5/9/22.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings(playDrone:true, showDiamonds:true, snap:true, selectedLimit:Limit.Eleven)
    
    //var audio: AudioUtil
    var border:Double = 25
    var body: some View {
        HStack(spacing:0) {
            ZStack(){
                // create scale and diamonds on the fly
                let intLimit = LimitMap[settings.selectedLimit]
                let scale = Scale(Limit: intLimit ?? 0 )
                let diamonds = Diamonds(scale:scale)
                GraphView(scale: scale, diamonds: diamonds, border: border)
                HitTestView(scaleIn: scale, borderIn: border, snapIn: settings.snap)
            }
            .aspectRatio(1/1, contentMode: .fit)
            .layoutPriority(1)
            .background()
            
            ControlView(settings: settings).background().frame(minWidth: 200)// all ui in right panel goes here
        }
        .frame (minWidth: 800, minHeight: 500)
    }
}
