//
//  ControlData.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 2/3/24.
//
//  This struct contains published data that is shared between the UI and the drawing code

import SwiftUI

class AppSettings: ObservableObject{
    @Published var showDiamonds: Bool = true
    @Published var selectedLimit: Limit = Limit.Eleven
    @Published var playDrone: Bool = true
    @Published var playNoteX: Bool = true
    @Published var playNoteY: Bool = true
    @Published var snap: Bool = true
    @Published var pedal: Bool = false
    @Published var useSynth: Bool = true
    @Published var useMIDI: Bool = true
    @Published var selectedGraphShape: GraphShape = .Square
    
    // root pitch
    @Published var root: Double = 130.813 * 2 // middle c  // no UI yet if ever

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
    
    // square graph
    @Published var viewRotation: Double = 0.0 // rotation in degrees
    @Published var viewScale: Double = 1.0 // scaling 0.0 equals no change. negitive and positve are possible .73 is good for 45 degree rotation
    @Published var viewOffsetX: Double = 0.0 // horizontal offset
    @Published var viewOffsetY: Double = 0.0 // Vertical offset, inverted. negative numbers to go up
    @Published var contentMode: ContentMode = .fit
    @Published var border: Double = 40
    
    // MIDI data
    @Published var pitchBendRange: UInt8 = 1 // 1 = one semi up and one down, for a full range of 1 tone // no ui yet if ever
    
    init(){
        self.highestRatioNormalized = log(self.highestRatio) / log(2)
        self.lowestRatioNormalized = log(self.lowestRatio) / log(2)
        
        // combine highest and lowest normalized ratios to give the full range of the graph
        self.rangeNormalized = self.highestRatioNormalized - self.lowestRatioNormalized // positive, need to handle negative value
        
        sound.setRootPitch(frequency: self.root)
        sound.sesetPitchBendRange(pitchBendRange: self.pitchBendRange)
    }
}

enum Limit: String, CaseIterable, Identifiable {
    case Three, Five, Seven, Nine, Eleven, Thirteen, Seventeen, Nineteen
    var id: Self { self }
}

enum GraphShape: String, CaseIterable, Identifiable {
    case Square, Diamond, Triangle
    var id: Self {self}
}

let LimitMap: [Limit: Int] = [
    Limit.Three: 3,
    Limit.Five: 5,
    Limit.Seven: 7,
    Limit.Nine: 9,
    Limit.Eleven: 11,
    Limit.Thirteen: 13,
    Limit.Seventeen: 17,
    Limit.Nineteen: 19
]

