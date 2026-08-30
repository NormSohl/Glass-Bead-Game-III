//
//  TransFlat.swift
//  GBGCore
//
//  Created by Norman Sohl on 7/18/22.
//

import Foundation

// Transitions start and end at different values. Always start at 0 and end at 1
// Envelopes start and end at the same value (0) and max at 1 somewhere in the middle
// Special case of null transition. 0 to 0 range
public class TransFlat:Transition {
    public override init() {}

    override func interpolate(percentComplete:Double) -> Double {
        return 0
    }
}

