//
//  ControlData.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 2/3/24.
//
//  This struct contains published data that is shared between the UI and the drawing code

import SwiftUI

class AppSettings: ObservableObject{
    @Published var showDiamonds: Bool
    @Published var selectedLimit: Limit
    @Published var playDrone: Bool
    @Published var snap: Bool
   // private var scale: Scale = Scale(Limit: 11)
    //private var geo:GeometryProxy
    //private var border:Double
    
    init(playDrone: Bool, showDiamonds: Bool, snap:Bool, selectedLimit: Limit){
        self.showDiamonds = showDiamonds
        self.selectedLimit =  selectedLimit
        self.playDrone = playDrone
        self.snap = snap
    }
}

    enum Limit: String, CaseIterable, Identifiable {
        case Three, Five, Seven, Eleven, Thirteen, Seventeen, Nineteen
        var id: Self { self }
    }
    
    let LimitMap: [Limit: Int] = [
        Limit.Three: 3,
        Limit.Five: 5,
        Limit.Seven: 7,
        Limit.Eleven: 11,
        Limit.Thirteen: 13,
        Limit.Seventeen: 17,
        Limit.Nineteen: 19
    ]
