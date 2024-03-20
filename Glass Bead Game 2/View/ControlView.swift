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
        ){
            let color = Color(red: 0.2, green: 0.4, blue: 0.8)
            Text("Glass Bead Game").bold().font(Font.headline)
            Divider()
            Toggle("Diamonds", isOn: $settings.showDiamonds).tint(color)
            Toggle("Drone", isOn: $settings.playDrone).tint(color)
            Toggle("Note X", isOn: $settings.playNoteX).tint(color)
            Toggle("Note Y", isOn: $settings.playNoteY).tint(color)
            Toggle("Snapping", isOn: $settings.snap).tint(color)
            Toggle("pedal", isOn: $settings.pedal).tint(color)
            Divider()
#if os(iOS)
            Text("Harmonics:")
#endif
            Picker("Harmonics:", selection: $settings.selectedLimit) { // picker does not show label. Don't know why. using Text to fake
                Text("3").tag(Limit.Three)
                Text("5").tag(Limit.Five)
                Text("7").tag(Limit.Seven)
                Text("9").tag(Limit.Nine)
                Text("11").tag(Limit.Eleven)
                Text("13").tag(Limit.Thirteen)
                Text("17").tag(Limit.Seventeen)
                Text("19").tag(Limit.Nineteen)
            }
            .accentColor(.blue)
            .pickerStyle(.segmented)
            Text("(Number of harmonic partials used to generate the scale used in the graph)")
            Divider()
            
#if os(iOS)
            Text("View:")
#endif
            Picker("View:", selection: $settings.selectedGraphShape){
                ForEach(GraphShape.allCases) { shape in
                    Text(shape.rawValue.capitalized)
                }
            }

            .accentColor(.blue)
            .pickerStyle(.segmented)
            .onChange(of: settings.selectedGraphShape){
                setView()
            }
            
            Divider()
            
            Text("Sound source:")
            Text("(Turn off internal synth in order to enable MIDI output)")
            
            Divider()
            
            Toggle("Use internal synth", isOn:$settings.useSynth).tint(color).onChange(of: settings.useSynth) {sound.outputToAudio = settings.useSynth}
            Toggle("Use Midi", isOn:$settings.useMIDI).tint(color).onChange(of: settings.useSynth) {sound.outputToAudio = settings.useMIDI}
#if os(iOS)
            Text("MIDI Destination:")
#endif
            Picker("MIDI Destination:" ,selection: $settings.destinationIndex) {
                ForEach(sound.midi.midiDestinations.indices, id: \.self) { index in
                    Text(sound.midi.midiDestinations[index].Name)
                }
            }
            .onChange(of: settings.destinationIndex) {
                let destinationIndex = settings.destinationIndex
                print(settings.destinationIndex,destinationIndex)
                sound.midi.setMidiDestination(destination: destinationIndex)
            }
            .pickerStyle(.automatic)
            //.disabled(settings.useSynth)
            
            Button(action: {sound.midi.test()}){
                Text("Test MIDI")
            }
            .accentColor(.white)
            .buttonStyle(.bordered)
            //.disabled(settings.useSynth)
            
            Spacer()
        }
        .padding([.leading,.trailing,.top], 20)
    }
    
    func setView() {
        // square graph
        switch settings.selectedGraphShape {
        case .Square:
            settings.viewRotation = 0.0 // rotation in degrees
            settings.viewScale = 1.0 // scaling 0.0 equals no change. negitive and positve are possible .73 is good for 45 degree rotation
            settings.viewOffsetX = 0.0 // horizontal offset
            settings.viewOffsetY = 0.0 // Vertical offset, inverted. negative numbers to go up
            settings.contentMode = .fit
            
        case .Diamond:
            settings.viewRotation = -45.0 // rotation in degrees
            settings.viewScale = 0.73 // scaling 0.0 equals no change. negitive and positve are possible .73 is good for 45 degree rotation
            settings.viewOffsetX = 0.0 // horizontal offset
            settings.viewOffsetY = 0.0 // Vertical offset, inverted. negative numbers to go up
            settings.contentMode = .fit
            
        case .Triangle:
            settings.viewRotation = 45.0 // rotation in degrees
            settings.viewScale = 0.73 // scaling 0.0 equals no change. negitive and positve are possible .73 is good for 45 degree rotation
            settings.viewOffsetX = 0.0 // horizontal offset
            settings.viewOffsetY = -400 // Vertical offset, inverted. negative numbers to go up
            settings.contentMode = .fill
        }
    }
}

