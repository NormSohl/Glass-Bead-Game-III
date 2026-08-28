//
//  Part.swift
//  GBGCore
//
//  Created by Norman Sohl on 7/15/22.
//

import Foundation

// Parts hold melodic lines of Notes
class Part:Node, HasLength{
    var memberList: [Node] = []
    var parentNode: Node?
    
    // support for audio rendering
    var currentNoteIndex:Int = 0
    
    //var waveform: WaveForm?  // obsolete
    var name: String?
    
    init (name:String){
        self.name = name
    }
    
    // TODO: this function sums the length of all notes in memberList
    func getLengthInSamples()->Int{
        let length = 0
        return length
    }

    // find the note that contains timeSlice. This is a brute force search that should only be called to start.
    func getCurrentNote (timeSlice:Int)->Note?{
        for index:Int in 0..<memberList.endIndex{
            let note:Note = memberList[index] as! Note
            if timeSlice >= note.startTime && timeSlice <= note.endTime {
                currentNoteIndex = index
                return (memberList[index]  as! Note)
            }
        }
        print("ERROR: getCurrentNote called with invalid timeSlice")
        return nil // timeslice is not represented in any note. Before or after the sequence?
    }
    
    // this needs to be fast as it is called from the audio render loop. Can it be optimized?
    func getNextNote()->Note?{
        currentNoteIndex += 1
        if currentNoteIndex < memberList.endIndex{
            return memberList[currentNoteIndex] as? Note
        }
        else{
            return nil
        }
    }
}
        
