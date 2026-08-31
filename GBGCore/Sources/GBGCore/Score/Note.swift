//
//  Note.swift
//  GBGCore
//
//  Created by Norman Sohl on 7/15/22.
//

import Foundation

public class Note:HasLength{

    public var startTime:Int = 0  // in samples, like timeSlice
    public var endTime:Int = 0  // in samples, like timeSlice
    public var startFrequency: Double
    public var endFrequency: Double
    public var amplitude: Double

    var envelope: Envelope = EnvFlat()
    var transition: Transition = TransFlat()

    // The recorded pitch-bend buffer, if this note has one - independent of `transition`
    // above, which only determines what's currently *played*. Set once when a recording is
    // captured/segmented; untouched by later transition switches (the UI lets a note's
    // transition be changed freely - via a picker on its own indicator in the piano roll -
    // without discarding a recorded buffer just because something else is selected right now);
    // cleared only by an explicit purge. Reselecting `.recordedContour` from that picker
    // constructs a fresh TransRecordedContour from this same buffer.
    public var recordedPitchBend: [Double]? = nil

    init (startTime:Int, endTime:Int, startFrequency:Double, endFrequency:Double, amplitude:Double){
        self.startTime = startTime // in samples from start of piece
        self.endTime = endTime  // in samples from start of piece
        self.startFrequency = startFrequency
        self.endFrequency = endFrequency
        self.amplitude = amplitude
    }
    
    func getStartTime()->Int {
        return self.startTime
    }

    // 0 to 1 position of an absolute sample time within this note - the inverse of startTime/
    // endTime, for callers (Part's insert/split logic) that need to evaluate this note's own
    // pitch/amplitude curves at a specific cut point rather than at "now."
    public func percentComplete(at time: Int) -> Double {
        Double(time - startTime) / Double(endTime - startTime)
    }

    // The only public window onto transition/envelope for callers outside this module (e.g.
    // the persistence DTO layer in SeqDocument.swift) - exposes just the classification, not
    // the instances themselves, so TransLinear/TransEaseIn/etc never need to become public.
    public var transitionKind: TransitionKind { TransitionKind.kind(of: transition) }
    public var envelopeKind: EnvelopeKind { EnvelopeKind.kind(of: envelope) }

    /// Sets this note's active transition to `kind`, reconstructing it fresh - `.recordedContour`
    /// specially, from this note's own `recordedPitchBend` buffer (an empty/inert contour if
    /// that's nil, matching `TransitionKind.makeTransition()`'s own safe-fallback behavior),
    /// everything else via `TransitionKind.makeTransition()` directly. `recordedPitchBend` itself
    /// is left untouched either way - see that property's own doc comment on why the buffer
    /// outlives whichever transition is currently selected. The one public entry point for a
    /// picker UI outside this module (Seq's piano-roll transition picker) to change a note's
    /// transition without GBGCore needing to expose `TransRecordedContour` itself.
    public func selectTransition(_ kind: TransitionKind) {
        if kind == .recordedContour {
            transition = TransRecordedContour(samples: recordedPitchBend ?? [])
        } else {
            transition = kind.makeTransition()
        }
    }
    
    // TODO: Returns the length of the note based on its start time and end time
    func getLengthInSamples()->Int{
        let length = endTime - startTime
        return length
    }
    
    // percentComplete is a 0 to 1 value indicating chronological position in current note. 0 is start, 1 is finished
    // 0 to 1 value giving place in note.
    public func getCurrentFrequency (percentComplete:Double)->Double{
        //let location:Double = Double(endTime) / Double(startTime)
        let freqRange = endFrequency - startFrequency
        let base = startFrequency + (freqRange * self.transition.interpolate(percentComplete:percentComplete))
        let centsOffset = self.transition.centsOffset(percentComplete:percentComplete)
        guard centsOffset != 0 else { return base }
        return base * pow(2, centsOffset / 1200)
    }

    // percentComplete is a 0 to 1 value indicating chronological position in current note. 0 is start, 1 is finished
    // 0 to 1 value giving place in note.
    public func getCurrentAmplitude (percentComplete:Double)->Double{
        //let percentComplete:Double = Double(endTime) / Double(startTime)
        return  self.amplitude * self.envelope.interpolate(percentComplete:percentComplete)
    }
    
    func validateSubClass()->Bool{
        return true
    }
}
    
