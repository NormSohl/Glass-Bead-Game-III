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
    var border:Double = 40
    var body: some View {
        HStack() {
            ZStack(){  // All graphics in left panel go here
                GeometryReader { geo in
                    let _ = print("ContentView: geo = \(geo.size)")
                    // create scale and diamonds on the fly
                    let intLimit = LimitMap[settings.selectedLimit]
                    let scale = Scale(Limit: intLimit ?? 0 )
                    GraphView(scale: scale, border: border)
                    let diamonds = Diamonds(scale:scale)
                    DiamondView(showDiamonds: settings.showDiamonds, diamonds: diamonds, geo: geo, border: border)
                    TickView( geo: geo, border: border)
                    HitTestView(geoIn: geo, scaleIn: scale, borderIn: border, snapIn: settings.snap)//, audioIn: audio)
                }
            }
            //.edgesIgnoringSafeArea(.all)
            .aspectRatio(1/1, contentMode: .fit)
            .layoutPriority(1)
            .background(.red)
            
            ControlView(settings: settings).background(.blue)// all ui in right panel goes here
        }
        .frame (minWidth: 800, minHeight: 500)
    }
}
