//
//  transEaseIn.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 7/18/22.
//

import Foundation

// Transitions start and end at different values. Always start at 0 and end at 1
// Envelopes start and end at the same value (0) and max at 1 somewhere in the middle
// Shape = /-  Range 0 to 1
class TransEaseIn:Transition {
    let start:Double = 0
    let end:Double = 90
    var location:Double = 0
    
    override func interpolate(percentComplete:Double) -> Double {
        location = start + ((end-start) * percentComplete)
        // convert location to radians, perform sin on that value
        return sin (location * 180 / .pi)
    }
}
