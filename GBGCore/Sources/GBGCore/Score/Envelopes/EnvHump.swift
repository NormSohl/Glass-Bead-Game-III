//
//  EnvHump.swift
//  GBGCore
//
//  Created by Norman Sohl on 7/18/22.
//

import Foundation

// Transitions start and end at different values. Always start at 0 and end at 1
// Envelopes start and end at the same value (0) and max at 1 somewhere in the middle
// An envelope that builds on the sin function used in EaseIn
// shape = /\
class EnvHump:Envelope {
    let start:Double = 0
    let end:Double = 180
    var location:Double = 0
        
    override func interpolate(percentComplete:Double) -> Double {
        location = start + ((end-start) * percentComplete)
        // convert location to radians, perform sin on that value
        // sin over 0...180 degrees is already 0 -> 1 -> 0 on its own, no shift needed
        return sin(location * .pi / 180)
    }
}
