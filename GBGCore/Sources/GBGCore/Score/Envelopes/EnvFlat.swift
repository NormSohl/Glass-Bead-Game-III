//
//  EnvFlat.swift
//  GBGCore
//
//  Created by Norman Sohl on 7/21/22.
//

import Foundation

// Transitions start and end at different values. Always start at 0 and end at 1
// Envelopes start and end at the same value (0) and max at 1 somewhere in the middle
// An envelope that builds on the sin function used in EaseIn
// shape = 1---1
public class EnvFlat:Envelope {
    public override init() {}

    override func interpolate(percentComplete:Double) -> Double {
        // no scaling applied
        return 1
    }
}
