//
//  TransRecordedContour.swift
//  GBGCore
//

import Foundation

// A recorded live performance's pitch-bend curve - evenly-spaced samples, each the deviation
// (in cents) of the real recorded pitch from what a plain linear interpolation between
// startFrequency and endFrequency would have produced at that same moment. Not a replacement
// for the normal glide - a deviation from it (see Transition.centsOffset's own comment). When
// startFrequency == endFrequency (the ordinary case for a plain recorded touch, which doesn't
// pre-decide where it'll land), that reference path is just a constant and this deviation is
// the whole recorded shape; when they differ (e.g. a deliberate portamento kept as one note),
// the deviation rides on top of a genuine glide - same data, same math, no special-casing.
//
// Self-contained - holds its own copy of the samples, no reference back to the Note it came
// from. A Note's own `recordedPitchBend` buffer (GBGCore/Score/Note.swift) is the persistent
// storage; this class is constructed fresh from that buffer whenever `.recordedContour` is the
// selected transition, and discarded (without touching the buffer) when something else is
// selected instead.
class TransRecordedContour: Transition {
    private let samples: [Double]

    init(samples: [Double]) {
        self.samples = samples
    }

    // Plain linear glide, same formula TransLinear already uses - correct whether
    // startFrequency/endFrequency match (multiplied by a zero range, contributes nothing) or
    // genuinely differ (a real glide for the deviation to ride on top of).
    override func interpolate(percentComplete: Double) -> Double {
        return percentComplete
    }

    override func centsOffset(percentComplete: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        guard samples.count > 1 else { return samples[0] }

        let clamped = min(max(percentComplete, 0), 1)
        let position = clamped * Double(samples.count - 1)
        let lowerIndex = Int(position)
        let upperIndex = min(lowerIndex + 1, samples.count - 1)
        let fraction = position - Double(lowerIndex)

        return samples[lowerIndex] + (samples[upperIndex] - samples[lowerIndex]) * fraction
    }
}
