//
//  ControlData.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 2/3/24.
//
//  This struct contains published data that is shared between the UI and the drawing code

import SwiftUI

class AppSettings: ObservableObject{
    @Published var showDiamonds: Bool = true
    @Published var showSettings: Bool = false // settings panel is a popover now, freeing the right edge for the Z slider
    @Published var showDissonance: Bool = false // opt-in: unverified visually, and recomputes a full grid on toggle/limit/resize
    @Published var showTetrads: Bool = false // opt-in: the Z-aware depth-slider layer view, alongside (not replacing) showDiamonds
    @Published var useLinearHarmonicWeighting: Bool = true // linear vs. 1/n falloff for the dissonance field's harmonic weighting; linear is the default
    @Published var selectedLimit: Limit = Limit.eleven
    @Published var playDrone: Bool = true
    @Published var playNoteX: Bool = true
    @Published var playNoteY: Bool = true
    @Published var playNoteZ: Bool = true
    @Published var snap: Bool = true
    @Published var pedal: Bool = false
    @Published var useSynth: Bool = true
    @Published var useMIDI: Bool = true
    @Published var useMIDI_MPE: Bool = true
    @Published var tuneMidi: Bool = false
    @Published var test: Bool = false
    @Published var selectedGraphShape: GraphShape = .square
    
    // root pitch
    @Published var rootFrequency: Double = 261.6255653005986 // middle c  // no UI yet if ever. MIDI note number 60
    @Published var rootMidiNote: Int = 60  // middle c

    // Z: the third moving tone, controlled by the vertical slider strip - a real 4th voice,
    // wired into Sound/Triad/MIDI the same way X/Y are. ZSliderView publishes the touched pitch
    // here every frame (also read directly by TetradView to pick the crossfade layer) and calls
    // sound.setZPitch(frequency:) to make it audible.
    @Published var zFrequency: Double = 261.6255653005986 // starts at unison with the root

    //@Published var numberOfOctaves: Double = 2
    // Highest ratio =
    // 3/2 gives range of a fifth above 1/1
    // 2/1 gives a range of one octave above 1/1
    // 3/1 is an octave and a fifth above 1/1
    // 4/1 gives two octaves above 1/1
    // 8/1 gives three octaves above 1/1
    @Published var highestRatio: Double = 3/1
    @Published var highestRatioNormalized:Double = 0.0 // initialized in the init function 0 to 1 is an octave. >1 for higher values
    @Published var destinationIndex:Int = 0
    
    // Lowest ratio =
    // 2/3 is a fifth below 1/1
    // 1/2 gives a range of one octave below 1/1
    // 1/3 gives a range of one octave and a fifth below 1/1
    // 1/4 gives two octaves below 1/1
    // 1/8 gives three octaves below 1/1
    @Published var lowestRatio: Double = 1/2
    @Published var lowestRatioNormalized: Double = 0.0  // initialized in the init function -1 to 0 for an octave. < -1 for lower values
    
    // combine into range
    @Published var rangeNormalized: Double = 0.0  // initialized in the init function
    
    // support for rotated views - replaced by UI
    
    // square graph: default. should really zero these out at init and let the UI set the appropriate values, even for defaults
    @Published var viewRotation: Double = 0.0 // rotation in degrees
    @Published var viewScale: Double = 1.0 // scaling 1.0 equals no change. negative and positive are possible .73 is good for 45 degree rotation
    @Published var viewOffsetX: Double = 0.0 // horizontal offset
    @Published var viewOffsetY: Double = 0.0 // Vertical offset, inverted. negative numbers to go up
    @Published var contentMode: ContentMode = .fit
    @Published var border: Double = 40
    
    // MIDI data
    @Published var pitchBendRange: Int = 12
    @Published var pitchBendRangeMPE: Int = 24
    
    init(){
        self.highestRatioNormalized = log(self.highestRatio) / log(2)
        self.lowestRatioNormalized = log(self.lowestRatio) / log(2)
        
        // combine highest and lowest normalized ratios to give the full range of the graph
        self.rangeNormalized = self.highestRatioNormalized - self.lowestRatioNormalized // positive, need to handle negative value
        
        sound.setRootPitch(frequency: self.rootFrequency)
        sound.setRootNote(midiNote: self.rootMidiNote)
        sound.setPitchBendRange(pitchBendRange: self.pitchBendRange)
        sound.setPitchBendRangeMPE(pitchBendRange: self.pitchBendRangeMPE)
    }
}

enum Limit: String, CaseIterable, Identifiable {
    case three, five, seven, nine, eleven, thirteen, seventeen, nineteen
    var id: Self { self }
}

enum GraphShape: String, CaseIterable, Identifiable {
    case square, diamond, triangle
    var id: Self {self}
}

let limitMap: [Limit: Int] = [
    Limit.three: 3,
    Limit.five: 5,
    Limit.seven: 7,
    Limit.nine: 9,
    Limit.eleven: 11,
    Limit.thirteen: 13,
    Limit.seventeen: 17,
    Limit.nineteen: 19
]

