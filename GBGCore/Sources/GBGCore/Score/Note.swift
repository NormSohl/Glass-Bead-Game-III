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
        return startFrequency + (freqRange * self.transition.interpolate(percentComplete:percentComplete))
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
    
