//
//  TransEaseInEaseOut.swift
//  GBGCore
//
//  Created by Norman Sohl on 7/18/22.
//

import Foundation

// Transitions start and end at different values. Always start at 0 and end at 1
// Envelopes start and end at the same value (0) and max at 1 somewhere in the middle
// Shape = S-curve (slow-fast-slow), Range 0 to 1
class TransEaseInEaseOut:Transition{
    let start:Double = 90
    let end:Double = 270
    var location:Double = 0

    override func interpolate(percentComplete:Double) -> Double {
        location = start + ((end-start) * percentComplete)
        // convert location to radians, perform sin on that value
        // sin(90+180p) = cos(180p), so (1 - cos(180p))/2 is the standard raised-cosine 0->1 ease
        return  (1 - sin( location * .pi / 180)) / 2
    }
}
