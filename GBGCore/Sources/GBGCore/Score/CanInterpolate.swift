//
//  CanInterpolate.swift
//  GBGCore
//
//  Created by Norman Sohl on 7/18/22.
//

import Foundation

// Transitions start and end at different values. Always start at 0 and end at 1
// Envelopes start and end at the same value (0) and max at 1 somewhere in the middle

// not a node, no children only parents.
// protocol for envelopes, transitions.

public class Transition {
    func interpolate (percentComplete:Double)->Double{
        return 0
    }

    // A deviation, in cents, applied on top of the normal startFrequency/endFrequency
    // interpolation - not a replacement for it. Defaults to 0 for every existing transition
    // (no behavior change). Exists for TransRecordedContour: a recorded performance is
    // expressed as "how far did the real pitch deviate from the normal straight/eased path at
    // this moment," which stays meaningful whether that path is a genuine glide or, when
    // startFrequency == endFrequency (the ordinary case for a plain recorded touch, which
    // doesn't pre-decide where it'll land), just a constant - the deviation is then the whole
    // recorded shape, with no special-casing needed here or in Note.getCurrentFrequency.
    func centsOffset (percentComplete:Double)->Double{
        return 0
    }
}

public class Envelope {
    func interpolate (percentComplete:Double)->Double{
        return 0
    }
}
