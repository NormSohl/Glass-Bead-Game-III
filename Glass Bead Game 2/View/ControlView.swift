//
//  ControlView.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 2/2/24.
//

import SwiftUI

struct ControlView: View {
    @ObservedObject var settings: AppSettings
    
    var body: some View {
            VStack(
                alignment: .leading
                //spacing: 10
            ){
                let color = Color(red: 0.2, green: 0.4, blue: 0.8)
                Text("Glass Bead Game").bold().font(Font.headline)
                Divider()
                Toggle("Diamonds", isOn: $settings.showDiamonds).tint(color)
                Toggle("Drone", isOn: $settings.playDrone).tint(color)
                Toggle("Snapping", isOn: $settings.snap).tint(color)
                
                HStack{
                    #if os(iOS)
                    Text("Harmonics:")
                    #endif
                    Picker("Harmonics", selection: $settings.selectedLimit) { // picker does not show label. Don't know why. using Text to fake
                        Text("3").tag(Limit.Three)
                        Text("5").tag(Limit.Five)
                        Text("7").tag(Limit.Seven)
                        Text("11").tag(Limit.Eleven)
                        Text("13").tag(Limit.Thirteen)
                        Text("17").tag(Limit.Seventeen)
                        Text("19").tag(Limit.Nineteen)
                    }.accentColor(.blue)
                }
                Text("Number of harmonic partials used to generate the scale used in the graph")
                Spacer()
            }
            .padding([.leading,.trailing,.top], 20)
        }
    }
