//
//  ControlView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 2/2/24.
//

import SwiftUI

struct ControlView: View {
    @ObservedObject var settings: AppSettings
    
    var body: some View {
        ZStack{
            Color.black.ignoresSafeArea(.all)
            ScrollView {
            VStack(
                alignment: .leading
            ){
                let tintcolor = Color(red: 0.2, green: 0.4, blue: 0.8)

                Text("A Glass Bead Game").bold().font(Font.headline).foregroundStyle(.white)
                Divider()
                Toggle(isOn: $settings.showDiamonds, label:{
                    Text("Diamonds")
                })
                .tint(tintcolor)
                .foregroundStyle(.white)
                // Tetrad Layers is the generalization Diamonds reduces to at Z=unison (see
                // TetradsTests) - not a separate thing to compare against, so it takes over
                // entirely rather than drawing alongside it.
                .disabled(settings.showTetrads)

                Toggle(isOn: $settings.showDissonance, label:{
                    Text("Dissonance Field")
                })
                .tint(tintcolor)
                .foregroundStyle(.white)

                Toggle(isOn: $settings.showTetrads, label:{
                    Text("3rd Moving Tone")
                })
                .tint(tintcolor)
                .foregroundStyle(.white)
                // Norm: turning this on should start at the 1:1 (unison) plane every time, so
                // the display reads as unchanged at the moment it switches on (unison's tetrad
                // slice is identical to the default 2D view) - it only switches layers once the
                // slider is actually moved off of that plane, never just from toggling on.
                .onChange(of: settings.showTetrads) {
                    if settings.showTetrads {
                        settings.zFrequency = settings.rootFrequency
                    }
                }

                Toggle("Drone", isOn: $settings.playDrone)
                    .tint(tintcolor)
                    .onChange(of: settings.playDrone){sound.enableDrone = settings.playDrone}
                    .foregroundStyle(.white)
                
                Toggle("Note X", isOn: $settings.playNoteX)
                    .tint(tintcolor)
                    .onChange(of: settings.playNoteX){sound.enableX = settings.playNoteX}
                    .foregroundStyle(.white)

                Toggle("Note Y", isOn: $settings.playNoteY)
                    .tint(tintcolor)
                    .onChange(of: settings.playNoteY){sound.enableY = settings.playNoteY}
                    .foregroundStyle(.white)

                Toggle("Note Z", isOn: $settings.playNoteZ)
                    .tint(tintcolor)
                    .onChange(of: settings.playNoteZ){sound.enableZ = settings.playNoteZ}
                    .foregroundStyle(.white)

                Toggle("Snapping", isOn: $settings.snap)
                    .tint(tintcolor)
                    .foregroundStyle(.white)
                
                Toggle("pedal", isOn: $settings.pedal)
                    .tint(tintcolor)
                    .foregroundStyle(.white)

                Divider()
#if os(iOS)
                Text("Harmonics:").foregroundStyle(.white)
#endif
                Picker("Harmonics:", selection: $settings.selectedLimit) { // picker does not show label. Don't know why. using Text to fake
                    Text("3").tag(Limit.three)
                    Text("5").tag(Limit.five)
                    Text("7").tag(Limit.seven)
                    Text("9").tag(Limit.nine)
                    Text("11").tag(Limit.eleven)
                    Text("13").tag(Limit.thirteen)
                    Text("17").tag(Limit.seventeen)
                    Text("19").tag(Limit.nineteen)
                }
                .listItemTint(.blue)
                .background(tintcolor)
                .pickerStyle(.segmented)
                Text("(Number of harmonic partials used to generate the scale used in the graph)").foregroundStyle(.white)
                
                Divider()
                
#if os(iOS)
                Text("View:").foregroundStyle(.white)
#endif
                Picker("View:", selection: $settings.selectedGraphShape){
                    ForEach(GraphShape.allCases) { shape in
                        Text(shape.rawValue.capitalized).foregroundStyle(.white)
                    }
                }
                .listItemTint(.white)
                .background(tintcolor)
                .pickerStyle(.segmented)
                .onChange(of: settings.selectedGraphShape){
                    setView()
                }
                
                Divider()
                
                Toggle("Use internal synth", isOn:$settings.useSynth)
                    .tint(tintcolor)
                    .onChange(of: settings.useSynth) {sound.outputToAudio = settings.useSynth}
                    .foregroundStyle(.white)
                
                Toggle("Use Midi", isOn:$settings.useMIDI)
                    .tint(tintcolor)
                    .onChange(of: settings.useMIDI) {sound.outputToMidi = settings.useMIDI}
                    .foregroundStyle(.white)
                
                Toggle("Use MPE", isOn:$settings.useMIDI_MPE)
                    .tint(tintcolor)
                    .onChange(of: settings.useMIDI_MPE) {sound.midi.useMPE(useMpe: settings.useMIDI_MPE)}
                    .disabled(!settings.useMIDI)
                    .foregroundStyle(.white)
                
                Divider().foregroundColor(.white)
#if os(iOS)
                Text("MIDI Destination:").foregroundStyle(.white)
#endif
                Picker("MIDI Destination:" ,selection: $settings.destinationIndex) {
                    ForEach(sound.midi.midiDestinations.indices, id: \.self) { index in
                        Text(sound.midi.midiDestinations[index].name).foregroundStyle(.white)
                    }
                }
                .listItemTint(.white)
                .background(tintcolor)
                .onChange(of: settings.destinationIndex) {
                    let destinationIndex = settings.destinationIndex
                    //print(settings.destinationIndex,destinationIndex)
                    sound.midi.setMidiDestination(destination: destinationIndex)
                }
                .pickerStyle(.menu)
                .disabled(!settings.useMIDI)
                .tint(.white)
                
                Divider()
                
                let details = "Midi channels 1, 2, 3, and 4 are sending A: 440 hz" // to the \(sound.midi.midiDestinations[settings.destinationIndex].name)"
                Button("Tune Midi"){
                    if settings.tuneMidi == false{
                        sound.midi.tuneStart()
                        settings.tuneMidi = true
                    }
                    else {
                        sound.midi.tuneStop()
                        settings.tuneMidi = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .alert(
                    "Tuning",
                    isPresented: $settings.tuneMidi,
                    presenting: details
                ) { details in
                    Button(role: .cancel) {
                        sound.midi.tuneStop()
                    } label: {
                        Text("Stop")
                    }
                    
                } message:{ details in
                    Text(details)
                }
                .disabled(!settings.useMIDI)
                
                let details2 = "Midi test sent" //to the \(sound.midi.midiDestinations[settings.destinationIndex].name)"
                
                Button("Test"){
                    if settings.test == false{
                        sound.midi.test(enable: true)
                        settings.test = true
                    }
                    else {
                        sound.midi.test(enable: false)
                        settings.test = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .alert(
                    "Testing",
                    isPresented: $settings.test,
                    presenting: details2
                ) { details2 in
                    Button(role: .cancel) {
                        sound.midi.test(enable: false )
                    } label: {
                        Text("Stop")
                    }
                    
                } message:{ details2 in
                    Text(details2)
                }
                .disabled(!settings.useMIDI)
                
                Spacer()
            }.padding([.leading,.trailing,.top], 20)
            }
        }
    }
    
    func setView() {
        // square graph
        switch settings.selectedGraphShape {
        case .square:
            settings.viewRotation = 0.0 // rotation in degrees
            settings.viewScale = 1.0 // scaling 0.0 equals no change. negative and positive are possible .73 is good for 45 degree rotation
            settings.viewOffsetX = 0.0 // horizontal offset
            settings.viewOffsetY = 0.0 // Vertical offset, inverted. negative numbers to go up
            settings.contentMode = .fit
            
        case .diamond:
            settings.viewRotation = -45.0 // rotation in degrees
            settings.viewScale = 0.73 // scaling 0.0 equals no change. negative and positive are possible .73 is good for 45 degree rotation
            settings.viewOffsetX = 0.0 // horizontal offset
            settings.viewOffsetY = 0.0 // Vertical offset, inverted. negative numbers to go up
            settings.contentMode = .fit
            
        case .triangle:
            settings.viewRotation = 45.0 // rotation in degrees
            settings.viewScale = 0.73 // scaling 0.0 equals no change. negative and positive are possible .73 is good for 45 degree rotation
            settings.viewOffsetX = 0.0 // horizontal offset
            settings.viewOffsetY = -400 // Vertical offset, inverted. negative numbers to go up
            settings.contentMode = .fill
        }
    }
}

