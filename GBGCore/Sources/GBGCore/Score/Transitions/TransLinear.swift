//
//  transRamp.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 7/18/22.
//

import Foundation

// Transitions start and end at different values. Always start at 0 and end at 1
// Envelopes start and end at the same value (0) and max at 1 somewhere in the middle
// Linear interpolation shape = /
class TransLinear:Transition {
    override func interpolate(percentComplete:Double) -> Double {
        return percentComplete  // 0 to 1 value, linear interpolation
    }
}
