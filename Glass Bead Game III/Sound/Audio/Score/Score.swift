//
//  Score.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 7/14/22.
//

import Foundation

// Score holds Parts. Usually three in gbg
class Score:Node, HasLength {
    var memberList: [Node] = []
    var parentNode: Node? = nil
    
    var name:String = ""
    var beatsPerMin:Int = 0
    
    init (name:String, beatsPerMin:Int){
        self.name = name
        self.beatsPerMin = beatsPerMin
    }
    
    // functions to serve data to the audio render loop
    // first, a brute force function to get an initial set of three notes at a particular timeSlice
    func getTriadNotes(timeSlice:Int)->TriadParts
    {
        var triadParts:TriadParts = TriadParts()
        
        if memberList.count == 3 {   // all is good, assumes that score has three parts, ordered as:
            triadParts.drone = memberList[0] as? Part    // memberList[0] = drone
            triadParts.x = memberList[1] as? Part        // memberList[1] = tone x
            triadParts.y = memberList[2] as? Part        // memberList[2] = tone y
        }
        else{
            print ("Wrong number of parts in score! Should be three parts.")
        }
        return triadParts
    }
    
    //    // query the parts and average their values
    //    func render (timeSlice:Int)->Double{
    //        var value = 0.0
    //        for node in self.memberList {
    //            let part = node as! Part
    //            //value += part.render(timeSlice:timeSlice)
    //            //value /= Double(memberList.count)
    //        }
    //        return value
    //   }
    
    func getLengthInSamples()->Int{
        var length = 0
        for node in memberList {
            let part = node as! Part
            let loopLength = part.getLengthInSamples()
            if loopLength > length{
                length = loopLength
            }
        }
        return length
    }
}

struct TriadParts {
    var drone: Part? = nil
    var x: Part? = nil
    var y: Part? = nil
}
