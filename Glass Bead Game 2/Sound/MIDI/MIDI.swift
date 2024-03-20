//
//  MIDI.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 2/8/24.
//

import Foundation
import CoreMIDI
import AudioToolbox

class Midi{
    
    // midi working variables
    private var RootMidiFrequency: Double = 0.0
    private var RootMidiNote: UInt8 = 0
    private var RootMidiVelocity: UInt8 = 80
    
    private var xMidiFrequency: Double = 0.0
    private var xMidiNote: UInt8 = 0
    private var xMidiVelocity: UInt8 = 100
    private var xMidiPitchBend: UInt16 = 0
    
    private var yMidiFrequency: Double = 0.0
    private var yMidiNote: UInt8 = 0
    private var yMidiVelocity: UInt8 = 100
    private var yMidiPitchBend: UInt16 = 0
    
    private var pitchBendRange: UInt8 = 1 // 1 = one semi up and one down, for a full range of 1 tone
    
    // CoreMIDI values
    private var midiClient: MIDIClientRef = 0;
    private var outPort:MIDIPortRef = 0;
    
    // list of possible midi notes
    var noteList = NoteList()
    
    // possible midi destinations
    struct midiEndpoint{
        var midiEndpoint: MIDIEndpointRef = 0
        var index: Int = 0
        var Name: String = ""
    }
    
    //midi destinations
    var midiDestinations:[midiEndpoint] = []
    var destNum = 0
    
    func initMidi(){
        MIDIClientCreate("Glass Bead Game" as CFString, nil, nil, &midiClient);
        MIDIOutputPortCreate(midiClient, "Glass Bead Game" as CFString, &outPort);
        initMidiSources()
        initMidiDestinations()
    }
    
    func setMidiDestination(destination: Int){
        destNum = destination
        print("Destination set to \(destination)")
    }
    
    // midi sources
    var midiSources:[midiEndpoint] = []
    var sourceNum = 0
    
    func initMidiSources(){
        let numSources = MIDIGetNumberOfSources()
        print("number of Sources: \(numSources)")
        for i in 0...numSources-1{
            let device = MIDIGetSource(i)
            
            var param: Unmanaged<CFString>?
            //let err: OSStatus =
            MIDIObjectGetStringProperty(device, kMIDIPropertyDisplayName, &param)
            let name =  param!.takeRetainedValue() as String
            //print ("Source name: \(String(describing: param))")
            print ("Source \(i) name: \(name)")
            
            midiSources.append(midiEndpoint(midiEndpoint: device, index: i, Name: name))
        }
    }
    
    func initMidiDestinations(){
        let numDestinations = MIDIGetNumberOfDestinations()
        print("number of destinations: \(numDestinations)")
        for i in 0...numDestinations-1{
            
            let device = MIDIGetDestination(i)
            var param: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(device, kMIDIPropertyDisplayName, &param)
            let name =  param!.takeRetainedValue() as String
            midiDestinations.append(midiEndpoint(midiEndpoint: device, index: i, Name: name))
            print ("Destination \(i) name: \(name)")
        }
    }
    
    func startMidi(){
        // Root note on channel 1
        print ("startMidi: Root")
        // Send note off to quiet glitch when changing PB
        sendMidiNoteOff(channel: 1, note: RootMidiNote)
        //get midi data for root frequency
        var nAndPb = freqToNoteAndPB(frequency: RootMidiFrequency)
        RootMidiNote = UInt8(nAndPb.MIDINote)
        //sendPitchBend(channel:0, value:0) // root note has no pitchbend
        sendMidiNoteOn(channel: 1, note: RootMidiNote, velocity: RootMidiVelocity)
        print("SetRootPitch: RootMidiNote = \(RootMidiNote)")
        
        // X note on channel 2
        print ("startMidi: X")
        // Send note off to quiet glitch when changing PB, also to clear channel for new midi note
        sendMidiNoteOff(channel: 2, note: xMidiNote)
        // get midi data for x
        nAndPb = freqToNoteAndPB(frequency: xMidiFrequency)
        xMidiNote = UInt8(nAndPb.MIDINote)
        xMidiPitchBend = UInt16(nAndPb.PitchBend)
        print("SetXPitch: xMidiNote = \(xMidiNote)")
        
        sendMidiPitchBend(channel: 2, value: xMidiPitchBend)
        sendMidiNoteOn(channel: 2, note: xMidiNote, velocity: xMidiVelocity)
        
        // Y note on channel 3
        print ("startMidi: Y")
        // Send note off to quiet glitch when changing PB and to clear channel for new note if needed
        sendMidiNoteOff(channel: 3, note: yMidiNote)
        // get midi data for y
        nAndPb = freqToNoteAndPB(frequency: yMidiFrequency)
        yMidiNote = UInt8(nAndPb.MIDINote)
        yMidiPitchBend = UInt16(nAndPb.PitchBend)
        print("SetYPitch: yMidiNote = \(yMidiNote)")
        
        sendMidiPitchBend(channel: 3, value: yMidiPitchBend) // root note has no pitchbend
        sendMidiNoteOn(channel: 3, note: yMidiNote, velocity: yMidiVelocity)
    }
    
    func stopMidi(){
        print ("stopMidi: Root")
        sendMidiNoteOff(channel: 1, note: RootMidiNote)
        
        print ("stopMidi: X")
        sendMidiNoteOff(channel: 2, note: xMidiNote)
        
        print ("stopMidi: Y")
        sendMidiNoteOff(channel: 3, note: yMidiNote)
    }
    
    
    func setMidiRootPitch(frequency: Double){
        RootMidiFrequency = frequency
        print("SetXMidiPitch: xMidiFrequency = \(xMidiFrequency)")
    }
    
    func setMidiXPitch(frequency: Double){
        xMidiFrequency = frequency
        print("SetXMidiPitch: xMidiFrequency = \(xMidiFrequency)")
    }
    
    func setMidiYPitch(frequency: Double){
        yMidiFrequency = frequency
        print("SetXMidiPitch: yMidiFrequency = \(yMidiFrequency)")
    }
    
    func setMidiPitchBendRange(PitchBendRange:UInt8){
        pitchBendRange = PitchBendRange
    }
    
    func sendMidiNoteOn(channel:UInt8, note:UInt8, velocity:UInt8){
        print ("SendNoteOn: channel = \(channel), note = \(note), velocity = \(velocity)")
        
        // create packet
        var packet1 = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.length = 3;
        packet1.data.0 = channelVoiceMessage.NoteOn | (channel - 1) //(0x90 + (channel-1))
        packet1.data.1 = note
        packet1.data.2 = velocity
        //Add oacket to packet list and send it to destNum
        var packetList = MIDIPacketList(numPackets: 1, packet: packet1);
        MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);
    }
    
    func sendMidiNoteOff(channel:UInt8, note:UInt8){
        print ("SendNoteOff: channel = \(channel), note = \(note)")

        // create packet
        var packet1 = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.length = 3;
        packet1.data.0 = channelVoiceMessage.noteOff | (channel - 1) //UInt8(0x80 + (channel-1))
        packet1.data.1 = note
        packet1.data.2 = 0
        //Add oacket to packet list and send it to destNum
        var packetList:MIDIPacketList = MIDIPacketList(numPackets: 1, packet: packet1);
        MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);
    }
    
    func sendMidiPitchBend(channel:UInt8, value:UInt16){
        print ("SendPitchBend: channel = \(channel), value = \(value)")

        // put bottom 7 bits in lsb
        let lsb16:UInt16 = value & 0b000000001111111
        // put next 7 bits in msb
        var msb16:UInt16 = value & 0b0011111110000000
        msb16 = msb16 >> 7
        // trim 16 bit to 8 bit (this should only trim empty bits
        let lsb8 = UInt8(lsb16)
        let msb8 = UInt8(msb16)
        
        // create packet
        var packet1 = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.length = 3;
        packet1.data.0 = 0xE0 + (channel - 1)//UInt8(channelVoiceMessage.PitchBendChange + (channel - 1))
        packet1.data.1 = lsb8
        packet1.data.2 = msb8
        
        //Add oacket to packet list and send it to destNum
        var packetList:MIDIPacketList = MIDIPacketList(numPackets: 1, packet: packet1);
        MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);
    }
        func sendNote(packetList:MIDIPacketList){
        //var packet1:MIDIPacket = MIDIPacket();
        //packet1.timeStamp = 0;
        //packet1.length = 3;
        //packet1.data.0 = 0x90 + 0; // Value of 0 = channel 1. Why make it simple when you can make it more confusing? Note On event channel 1
        //packet1.data.1 = 0x3C; // Note C3
        //packet1.data.2 = 100; // Velocity
        
        print("SendNote Using destination #\(destNum)")
        var myPacketList = packetList // can't be a let value as passed in
        MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &myPacketList);
    }
    
    struct noteAndPitchbend{
        var MIDINote: UInt8 = 0
        var PitchBend: UInt16 = 8192  // 0 of pitchbend range
    }
    
    //Given a frequency, return the nearest semitone from the noteList and the pitchbend value to tune that note value to match the frequency. This will vary depending on pitchbend range.
    // take in frequency, return note value and pitch bend value
    func freqToNoteAndPB(frequency: Double) -> noteAndPitchbend {
        var ret = noteAndPitchbend()
        let match = noteList.searchList(frequency: frequency)
        
        // if match is an exact hit:
        if match.lowerNote.noteFreq == match.higherNote.noteFreq {
            ret.MIDINote = match.lowerNote.noteMIDI
            ret.PitchBend = 8192 // 0 of pitchbend range
            return ret
        }
        // otherwise it is good: calculate pb
        // nc  =  1200*log2(fn/440 Hz)
        let numHigherCents:Double = 1200 * log2(match.higherNote.noteFreq / frequency)
        let numLowerCents:Double = 1200 * log2(match.lowerNote.noteFreq / frequency)
        
        // if freq is closer to lower note:
        if numLowerCents < abs(numHigherCents){
            ret.MIDINote = match.lowerNote.noteMIDI
            ret.PitchBend = centsToPitchBend(pitchBendRange: pitchBendRange, cents: numLowerCents)
        }
        // else freq is closer to higher note
        else {
            ret.MIDINote = match.higherNote.noteMIDI
            ret.PitchBend = centsToPitchBend(pitchBendRange: pitchBendRange, cents: numHigherCents)
        }
        return ret
    }
    
    func centsToPitchBend(pitchBendRange: UInt8, cents: Double) -> UInt16{
        let pbRangeInCents = Double(pitchBendRange * 100)
        if cents >= pbRangeInCents {
            print (" AudioGeneric: centsToPitchBend: Error- cents above pbRangeInCents.  range = \(pitchBendRange), pbRangeInCents = \(pbRangeInCents), cents = \(cents),")
            return 16383
        }
        
        if cents < ( 0 - pbRangeInCents) {
            print (" AudioGeneric: centsToPitchBend: Error- cents below pbRangeInCents.  range = \(pitchBendRange), pbRangeInCents = \(pbRangeInCents), cents = \(cents),")
            return 0
        }
        
        let centsTemp:Double = Double(cents) / (100.00 * Double(pitchBendRange))
        let retPB: Double = (centsTemp * 8192) + 8192
        
        //print (" AudioGeneric: centsToPitchBend: Success, range = \(pitchBendRange), pbRangeInCents = \(pbRangeInCents), cents = \(cents), centsTemp = \(centsTemp), pitchbend = \(retPB)")
        return UInt16(retPB)
    }
    
    // returns number of octaves between freq1 and freq2
    func numOctaves(freq1: Double, freq2:Double)->Int{
        //no = log2(f2/f1)
        let numOct = log2(freq1/freq2)
        return Int(numOct)
    }
    
    func test(){
        //sendNoteOn(channel: 1, note: 0x3C, velocity: 100)
        var packet1:MIDIPacket = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.length = 3;
        packet1.data.0 = 0x90 + 0; // Value of 0 = channel 1. Why make it simple when you can make it more confusing? Note On event channel 1
        packet1.data.1 = 0x3C; // Note C3
        packet1.data.2 = 100; // Velocity
        var packetList:MIDIPacketList = MIDIPacketList(numPackets: 1, packet: packet1);
        sendNote(packetList:packetList)
        
        print("Playing note for 1 second on channel 1 (1-16)")
        sleep(1);
        
        //sendNoteOff(channel: 1, note: 0x3C, velocity: 0)
        packet1.data.0 = 0x80 + 0; // Note Off event channel 1
        packet1.data.2 = 0; // Velocity
        packetList = MIDIPacketList(numPackets: 1, packet: packet1);
        sendNote(packetList:packetList)
        print("Note off sent")
    }
    
    func testCentsToPitchBend(){
        for pbRange in 1...12 {
            for cents in -1200...1200 {
                _ = centsToPitchBend(pitchBendRange: UInt8(pbRange), cents: Double(cents))
            }
        }
    }
    
    func makeStatusByte (command:Int8, channel: Int8)->Int8 {
        let ret:Int8 = command + channel-1
        return ret
    }
    struct ChannelVoiceMessage{
        let noteOff:UInt8 = 0b10000000
        let NoteOn:UInt8 =  0b10010000
        let PolyphonicKeyPressure:UInt8 = 0b10100000
        let ControlChange:UInt8 = 0b10110000
        let ProgramChange:UInt8 = 0b11000000
        let ChannelPressure:UInt8 = 0b11010000
        let PitchBendChange:UInt8 = 0b11100000
        let ChannelModeMessages:UInt8 = 0b10110000
    }
    let channelVoiceMessage = ChannelVoiceMessage()
}
