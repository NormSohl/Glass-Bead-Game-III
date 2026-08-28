//
//  Score.swift
//  GBGCore
//
//  Created by Norman Sohl on 7/14/22.
//

import Foundation

// Score holds Parts. Usually three in gbg
class Score: HasLength {
    var parts: [Part] = []

    var name: String = ""
    var beatsPerMin: Int = 0

    init (name:String, beatsPerMin:Int){
        self.name = name
        self.beatsPerMin = beatsPerMin
    }

    func addPart(_ part: Part) {
        parts.append(part)
    }

    // functions to serve data to the audio render loop
    // first, a brute force function to get an initial set of three notes at a particular timeSlice
    func getTriadNotes(timeSlice:Int)->TriadParts
    {
        var triadParts:TriadParts = TriadParts()

        if parts.count == 3 {   // all is good, assumes that score has three parts, ordered as:
            triadParts.drone = parts[0]    // parts[0] = drone
            triadParts.x = parts[1]        // parts[1] = tone x
            triadParts.y = parts[2]        // parts[2] = tone y
        }
        else{
            print ("Wrong number of parts in score! Should be three parts.")
        }
        return triadParts
    }

    func getLengthInSamples()->Int{
        var length = 0
        for part in parts {
            let partLength = part.getLengthInSamples()
            if partLength > length{
                length = partLength
            }
        }
        return length
    }

    // Ripple time edits apply to every Part in lockstep. Chord identity is defined purely by
    // notes across different Parts sharing the same startTime (there's no explicit chord
    // object) - if one Part's notes shifted independently of another's, notes that used to
    // sound together would silently drift apart in absolute time and stop reading as a chord.
    func insertTime(at: Int, duration: Int) {
        for part in parts {
            part.insertTime(at: at, duration: duration)
        }
    }

    func deleteTime(from: Int, duration: Int) {
        for part in parts {
            part.deleteTime(from: from, duration: duration)
        }
    }
}

struct TriadParts {
    var drone: Part? = nil
    var x: Part? = nil
    var y: Part? = nil
}
