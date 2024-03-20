//
//  NoteNameFrequency.swift
//  Glass Bead Game 2
//
//  Created by Norman Sohl on 3/14/24.
//

import Foundation

struct NoteEntry{
    var noteName: String = ""
    var octave: Int = 0
    var noteFreq: Double = 0.0
    var noteMIDI: UInt8 = 0
}

// midi number to frequency according to http://www.phys.unsw.edu.au/jw/notes.html
// m is midi number
// fm is frequency for that midi number
//var m = 21 // midi number for A0
//var fm  =  pow(2, (m - 69)/12) * 440 // 440 Hz

class NoteList{
    
    var list:[NoteEntry] = []
    let noteNames = ["C","C#","D","Eb","E","F","F#","G","Ab","A", "A","Bb","B","C"]
    let octaves = [0,1,2,3,4,5,6,7,8]
    
    init(){
        print ("NoteList: Init:")
        var noteNameIndex = 0
        var octaveIndex = 0
        
        // loop through possible midi notes:
        for midiNum in 12...108 {
            let entry = NoteEntry(
                noteName: noteNames[noteNameIndex],
                octave: octaves[octaveIndex],
                noteFreq: pow(2, Double(midiNum - 69)/12) * 440.0, // midi number to frequency according to http://www.phys.unsw.edu.au/jw/notes.html
                noteMIDI: UInt8(midiNum))
            
            list.append(entry)
            //print ("NoteList: NoteEntry added: midiNum = \(entry.noteMIDI), noteName = \(entry.noteName), octave = \(entry.octave), frequency = \(entry.noteFreq)")

            noteNameIndex += 1
            if noteNameIndex >= 12 {
                noteNameIndex -= 12
                octaveIndex += 1
            }
        }
    }
    
    // if searchFrequency == list element frequency, add its value to both low and high
    struct listReturn {
        var lowerNote: NoteEntry = NoteEntry()
        var higherNote: NoteEntry = NoteEntry()
    }
    
    // brute force search, starting with first element. Should really do this as a binary search tree or AVL tree but that adds a LOT of complexity, even if one takes code from: https://github.com/kodecocodes/swift-algorithm-club/tree/master/AVL%20Tree
    // if exact match same value is returned by low and high members
    // if out of range return default values in listReturn
    func searchList(frequency: Double)->listReturn{
        var ret = listReturn()
        for i in 0 ..< list.count - 1 {  // less than max element because we may evaluate for i+1 below.
            if list[i].noteFreq == frequency {
                // nailed it! hit the exact frequency. This is a corner case and will not be hit very often
                ret.lowerNote = list[i]
                ret.higherNote = list[i]
                return ret
            }
            if list[i].noteFreq > frequency {
                // process for the first element that is higher than the search frequency
                ret.lowerNote = list[i]
                ret.higherNote = list[i+1]
                return ret
            }
        }
        return ret  // out of range, returns default values of 0
    }
}

