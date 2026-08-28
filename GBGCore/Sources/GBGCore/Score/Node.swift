//
//  Node.swift
//  GBGCore
//
//  Created by Norman Sohl on 7/15/22.
//

import Foundation

// superclass for all classes that have a member list

protocol Node:AnyObject {
    var memberList:[Node] {get set}
    var parentNode:Node? {get set}
    
    func addToList(newNode:Node)
    func getList()->[Node]
    func validateMemberList()->Bool
    //func setMemberParent(parentNode: Node)
}

extension Node {
    
    func addToList(newNode:Node){
        memberList.append(newNode)
        newNode.parentNode = self
    }
    
    func getList()->[Node]{
        return self.memberList
    }
    
    func validateMemberList()->Bool{
        // validate this superclass
        if self.memberList.count == 0{
            return false
        }
        
        // validate children of this class
        for node in self.memberList {
            if node.validateMemberList() == false{
                return false
            }
        }
        // all is as it should be
        return true
    }
    
    func setMembersParent (parentNode: Node){
        if self.memberList.count != 0{
            for node in self.memberList {
                node.parentNode = parentNode
            }
        }
    }
}

// protocols that can optionally be used with Node.
// these use samples as the atomic time unit
protocol HasLength {
    func getLengthInSamples()->Int
}

// render returns a 0 to 1 value that would translate to - maxvalue to + maxvalue sent to the output port?
protocol CanRender {
    func render (timeSlice:Int)->Double
}
