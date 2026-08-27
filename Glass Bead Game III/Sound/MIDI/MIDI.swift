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
    // control debug trace
    private var MidiTrace = false
    
    // midi MPE
    private var useMPE: Bool = true
    
    // since we change the root frequency during tuning, save this here
    private var ReferenceFrequency = 0.0
    
    // midi working variables
    private var RootMidiFrequency: Double = 0.0
    private var RootMidiNote: Int = 60  // middle c
    private var RootMidiVelocity: Int = 80
    private var RootMidiPitchBend: Int = 8192
    
    private var xMidiFrequency: Double = 0.0
    private var xMidiNote: Int = 60 // middle c
    private var xMidiVelocity: Int = 100
    private var xMidiPitchBend: Int = 8192
    
    private var yMidiFrequency: Double = 0.0
    private var yMidiNote: Int = 60 // middle c
    private var yMidiVelocity: Int = 100
    private var yMidiPitchBend: Int = 8192
    
    private var pitchBendRange: Int = 0
    private var pitchBendRangeMPE: Int = 0
    //private var PitchMidiNote: UInt8 = 60 // middle C
    
    // CoreMIDI values
    private var midiClient: MIDIClientRef = 0;
    private var outPort:MIDIPortRef = 0;
    
    // midi sources
    private var midiSources:[midiEndpoint] = []
    private var sourceNum = 0
    
    //midi destinations
    var midiDestinations:[midiEndpoint] = []
    private var destNum = 0
    
    // midi enable channels
    var rootMidiEnable = true
    var xMidiEnable = true
    var yMidiEnable = true
    
    // midi notes on?
    var rootMidiIsPlaying = false
    var xMidiIsPlaying = false
    var yMidiIsPlaying = false
    
    // midi channels
    var rootMidiChannel = 1
    var xMidiChannel = 2
    var yMidiChannel = 3
    
    // midi MPE channels
    // MPE channel 1 is master channel for zone
    var rootMidiMPEChannel = 2
    var xMidiMPEChannel = 3
    var yMidiMPEChannel = 4
    
    // list of possible midi notes
    var noteList = NoteList()
    
    // possible midi destinations
    struct midiEndpoint{
        var midiEndpoint: MIDIEndpointRef = 0
        var index: Int = 0
        var name: String = ""
    }
    
    func initMidi(){
        MIDIClientCreate("Glass Bead Game" as CFString, nil, nil, &midiClient);
        MIDIOutputPortCreate(midiClient, "Glass Bead Game" as CFString, &outPort);
        initMidiSources()
        initMidiDestinations()
        if useMPE {
            enableMPE()
        }
    }
    
    func setMidiDestination(destination: Int){
        destNum = destination
        if useMPE {
            enableMPE()
        }
    }
    
    private struct MpeChannel{
        let lowerZoneMasterChannel:UInt8 = 1
        let upperZoneMasterChannel:UInt8 = 16  // optional
    }
    
    private let mpeChannel = MpeChannel()
    func enableMPE(){
        //print("\nMIDI: enableMPE")
        // MPE spec says that we have to do several things to enter MPE mode
        // Section 2.2.1 of the MPE spec.
        //    Initialise the MPE mode to zone and number of channels
        //print("\nMIDI: send registeredParameterNumbers.MPEConfiguration")
        let numOfChannelsInLowerZone:UInt8 = 15 // use all channels other than master
        sendMidiRPN(channel: mpeChannel.lowerZoneMasterChannel,
                    rpn: registeredParameterNumbers.MPEConfiguration,
                    msb: numOfChannelsInLowerZone)
    }
    
    func disableMPE(){
        //print("\nMIDI: disableMPE")
        // MPE spec says that we have to do several things to enter MPE mode
        // Section 2.2.1 of the MPE spec.
        //    Initialise the MPE mode to zone and number of channels
        sendMidiRPN(channel: mpeChannel.lowerZoneMasterChannel,
                    rpn: registeredParameterNumbers.MPEConfiguration,
                    msb: 0)
    }

    func startMidi(){
        // note values and pitchbend have already been stored in shared variables
        if MidiTrace {print("\nMidi: startMidi: useMPE = \(useMPE), rootMidiNote = \(RootMidiNote), xMidiNote = \(xMidiNote), yMidiNote = \(yMidiNote), rootMidiFrequency = \(RootMidiFrequency)")}
        if useMPE{
            if rootMidiEnable {
                rootMidiIsPlaying = true
                // Root note on channel 1
                RootMidiPitchBend = freqToPB(frequency: RootMidiFrequency, referenceFrequency: ReferenceFrequency, pitchBendRange: pitchBendRangeMPE)
                sendMidiNoteOn(channel: rootMidiMPEChannel, note: RootMidiNote, velocity:RootMidiVelocity)
                sendMidiPitchBend(channel: rootMidiMPEChannel, value: RootMidiPitchBend) // root note has centered pitchbend, should be 8192
            }
            
            if xMidiEnable {
                xMidiIsPlaying = true
                // X note on channel 2
                xMidiPitchBend = freqToPB(frequency: xMidiFrequency, referenceFrequency: ReferenceFrequency, pitchBendRange: pitchBendRangeMPE)
                sendMidiNoteOn(channel: xMidiMPEChannel, note: xMidiNote, velocity: xMidiVelocity)
                sendMidiPitchBend(channel: xMidiMPEChannel, value: xMidiPitchBend)
            }
            
            if yMidiEnable {
                yMidiIsPlaying = true
                // Y note on channel 3
                yMidiPitchBend = freqToPB(frequency: yMidiFrequency, referenceFrequency: ReferenceFrequency, pitchBendRange: pitchBendRangeMPE)
                sendMidiNoteOn(channel: yMidiMPEChannel, note: yMidiNote, velocity: yMidiVelocity)
                sendMidiPitchBend(channel: yMidiMPEChannel, value: yMidiPitchBend)
            }
        }
        else { // not MPE
            if rootMidiEnable {
                rootMidiIsPlaying = true
                // Root note on channel 1
                sendMidiNoteOff(channel: rootMidiChannel, note: RootMidiNote)
                sendMidiPitchBend(channel:rootMidiChannel, value: RootMidiPitchBend) // root note has centered pitchbend, should be 8192
                sendMidiNoteOn(channel: rootMidiChannel, note: RootMidiNote, velocity: RootMidiVelocity)
            }
            
            if xMidiEnable {
                xMidiIsPlaying = true
                // X note on channel 2
                sendMidiNoteOff(channel: xMidiChannel, note: xMidiNote)
                xMidiPitchBend = freqToPB(frequency: xMidiFrequency, referenceFrequency: ReferenceFrequency, pitchBendRange: pitchBendRange)
                sendMidiPitchBend(channel: xMidiChannel, value: xMidiPitchBend)
                sendMidiNoteOn(channel: xMidiChannel, note: xMidiNote, velocity: xMidiVelocity)
            }
            
            if yMidiEnable {
                yMidiIsPlaying = true
                // Y note on channel 3
                //print ("\nMidi: startMidi: Y")
                // Send note off to quiet glitch when changing PB and to clear channel for new note if needed
                sendMidiNoteOff(channel: yMidiChannel, note: yMidiNote)
                yMidiPitchBend = freqToPB(frequency: yMidiFrequency, referenceFrequency: ReferenceFrequency, pitchBendRange: pitchBendRange)
                sendMidiPitchBend(channel: yMidiChannel, value: yMidiPitchBend)
                sendMidiNoteOn(channel: yMidiChannel, note: yMidiNote, velocity: yMidiVelocity)
            }
        }
    }
    
    func stopMidi(){
        if MidiTrace {print("\nMidi: stopMidi: useMPE = \(useMPE), rootMidiNote = \(RootMidiNote), xMidiNote = \(xMidiNote), yMidiNote = \(yMidiNote)")}
        rootMidiIsPlaying = false
        xMidiIsPlaying = false
        yMidiIsPlaying = false

        if useMPE{
            //print ("Midi: stopMidi: Root")
            sendMidiNoteOff(channel: 2, note: RootMidiNote)
            
            //print ("Midi: stopMidi: X")
            sendMidiNoteOff(channel: 3, note: xMidiNote)
            
            //print ("Midi: stopMidi: Y")
            sendMidiNoteOff(channel: 4, note: yMidiNote)
        }
        else {
            //print ("Midi: stopMidi: Root")
            sendMidiNoteOff(channel: 1, note: RootMidiNote)
            
            //print ("Midi: stopMidi: X")
            sendMidiNoteOff(channel: 2, note: xMidiNote)
            
            //print ("Midi: stopMidi: Y")
            sendMidiNoteOff(channel: 3, note: yMidiNote)
        }
    }
    
    func setMidiReferencePitch(frequency: Double){
        ReferenceFrequency = frequency
        RootMidiFrequency = ReferenceFrequency
        if MidiTrace { print("Midi: SetMidiReferencePitch: frequency = \(ReferenceFrequency)")}
    }
    
    func setMidiRootPitch(frequency: Double){
        RootMidiFrequency = frequency
        if MidiTrace { print("Midi: SetRootPitch: frequency = \(RootMidiFrequency)")}
    }
    
    func setMidiXPitch(frequency: Double){
        xMidiFrequency = frequency
        if xMidiIsPlaying{
            if useMPE{
                xMidiPitchBend = freqToPB(frequency: xMidiFrequency, referenceFrequency: ReferenceFrequency, pitchBendRange: pitchBendRangeMPE)
                sendMidiPitchBend(channel: xMidiMPEChannel, value: xMidiPitchBend)
            }
            else{
                xMidiPitchBend = freqToPB(frequency: xMidiFrequency, referenceFrequency: ReferenceFrequency, pitchBendRange: pitchBendRange)
                sendMidiPitchBend(channel: xMidiChannel, value: xMidiPitchBend)
            }

        }
        if MidiTrace { print("Midi: SetXMidiPitch: frequency = \(xMidiFrequency)")}
    }
    
    func setMidiYPitch(frequency: Double){
        yMidiFrequency = frequency
        if yMidiIsPlaying{
            if useMPE{
                yMidiPitchBend = freqToPB(frequency: yMidiFrequency, referenceFrequency: ReferenceFrequency, pitchBendRange: pitchBendRangeMPE)
                sendMidiPitchBend(channel: yMidiMPEChannel, value: yMidiPitchBend)
            }
            else{
                yMidiPitchBend = freqToPB(frequency: yMidiFrequency, referenceFrequency: ReferenceFrequency, pitchBendRange: pitchBendRange)
                sendMidiPitchBend(channel: yMidiChannel, value: yMidiPitchBend)
            }
        }
        if MidiTrace { print("Midi: SetYMidiPitch: frequency = \(yMidiFrequency)")}
    }
    
    func setMidiPitchBendRange(PitchBendRange:Int){
        pitchBendRange = PitchBendRange
        //print("\nMidi: SetMidiPitchBendRange: Range = \(pitchBendRange)")
    }
    
    func setMidiPitchBendRangeMPE(PitchBendRange:Int){
        pitchBendRangeMPE = PitchBendRange
        //print("\nMidi: SetMidiPitchBendRangeMPE: Range = \(pitchBendRangeMPE)")
    }
    
    func useMPE(useMpe:Bool){
        useMPE = useMpe
        if useMPE {
            enableMPE()
        }
        else {
            disableMPE()
        }
    }
    
    func setOutputToMPE(PitchBendRange:Int){
        pitchBendRangeMPE = PitchBendRange
    }
        
    func setRootNote(Note: Int){
        RootMidiNote = Note
    }
    
    func setXNote(Note: Int){
        xMidiNote = Note
    }
    
    func setYNote(Note: Int){
        yMidiNote = Note
    }
    
    func tuneStart(){
        // set all frequencies  to A:440
        setMidiRootPitch(frequency: 440)
        setMidiXPitch(frequency: 440)
        setMidiYPitch(frequency: 440)
        if MidiTrace {print("Midi: tuneStart")}
        startMidi()
    }
    
    func tuneStop(){
        if MidiTrace {print("Midi: tuneStop")}
        stopMidi()
        setMidiRootPitch(frequency: ReferenceFrequency)
    }
        
    func test(enable: Bool){
        // send a glissando for entire pitchbend range
        let channel:Int = 2
        let note:Int = 0x3C
        let velocity:Int = 100
        if enable {
            sendMidiNoteOn(channel: channel,
                           note: note,
                           velocity: velocity)
            
            for i in 0 ... 16383 {
                sendMidiPitchBend(channel: channel, value: i)
            }
        }
        else{
            sendMidiNoteOff(channel: channel, note: note)
        }
    }
        
    private func initMidiSources(){
        let numSources = MIDIGetNumberOfSources()
        
        if numSources >= 1{
            for i in 0...numSources-1{  // does this need to be -1?
                let device = MIDIGetSource(i)
                var param: Unmanaged<CFString>?
                //let err: OSStatus =
                MIDIObjectGetStringProperty(device, kMIDIPropertyDisplayName, &param)
                let name =  param!.takeRetainedValue() as String
                //print ("Source name: \(String(describing: param))")
                //print ("Midi: Source \(i) name: \(name)")
                midiSources.append(midiEndpoint(midiEndpoint: device, index: i, name: name))
            }
        }
    }
    
    private func initMidiDestinations(){
        let numDestinations = MIDIGetNumberOfDestinations()
        if numDestinations >= 1{
            for i in 0...numDestinations-1{
                let device = MIDIGetDestination(i)
                var param: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(device, kMIDIPropertyDisplayName, &param)
                let name =  param!.takeRetainedValue() as String
                midiDestinations.append(midiEndpoint(midiEndpoint: device, index: i, name: name))
            }
        }
    }
    
    private struct ChannelVoiceMessages{
        let noteOff:UInt8 = 0b10000000
        let NoteOn:UInt8 =  0b10010000
        let PolyphonicKeyPressure:UInt8 = 0b10100000
        let ControlChange:UInt8 = 0b10110000
        let ProgramChange:UInt8 = 0b11000000
        let ChannelPressure:UInt8 = 0b11010000
        let PitchBendChange:UInt8 = 0b11100000
        let ChannelModeMessages:UInt8 = 0b10110000
    }
    private let channelVoiceMessages = ChannelVoiceMessages()
    
    private struct ControlChangeIDs{
        // there are too many to enter without need. Add them if needed
        // CC messages
        let DataEntryMSB:UInt8 = 0x06
        let DataEntryLSB:UInt8  = 0x26
        let RPN_LSB:UInt8  = 0x64
        let RPN_MSB:UInt8  = 0x65
        
        // Channel Mode Messages
        let MonoModeOn:UInt8 = 0x7E
        let PolyModeOn:UInt8 = 0x7F
    }
    private let controlChangeIDs = ControlChangeIDs()
    
    private struct RegisteredParameterNumbers{
        let PitchBendSensitivity:UInt16  = 0x00
        let ChannelFineTuning:UInt16  = 0x01
        let ChannelCorseTuning:UInt16  = 0x02
        let TuningProgramChange:UInt16  = 0x03
        let TuningBankSelect:UInt16  = 0x04
        let ModulationDepthRange:UInt16  = 0x05
        let MPEConfiguration:UInt16  = 0x06
    }
    private let registeredParameterNumbers = RegisteredParameterNumbers()
    
    private func sendMidiNoteOn(channel:Int, note:Int, velocity:Int){
        if MidiTrace {print ("Midi: SendNoteOn: channel = \(channel), note = \(note), velocity = \(velocity)")}
        
        // create packet
        var packet1 = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.length = 3;
        packet1.data.0 = channelVoiceMessages.NoteOn | (UInt8(channel) - 1) //(0x90 + (channel-1))
        packet1.data.1 = UInt8(note)
        packet1.data.2 = UInt8(velocity)
        //Add oacket to packet list and send it to destNum
        var packetList = MIDIPacketList(numPackets: 1, packet: packet1);
        if !midiDestinations.isEmpty {MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);}
    }
    
    private func sendMidiNoteOff(channel:Int, note:Int){
        if MidiTrace {print ("Midi: SendNoteOff: channel = \(channel), note = \(note)")}
        // create packet
        var packet1 = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.length = 3;
        packet1.data.0 = channelVoiceMessages.noteOff | (UInt8(channel) - 1) //UInt8(0x80 + (channel-1))
        packet1.data.1 = UInt8(note)
        packet1.data.2 = 0
        //Add oacket to packet list and send it to destNum
        var packetList:MIDIPacketList = MIDIPacketList(numPackets: 1, packet: packet1);
        if !midiDestinations.isEmpty {MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);}
    }
    
    private func sendMidiPitchBend(channel: Int, value: Int){
        //if MidiTrace {print ("Midi: SendPitchBend: channel = \(channel), value = \(value)")}
        // put bottom 7 bits in lsb
        let lsb16:UInt16 = UInt16(value) & 0b000000001111111
        // put next 7 bits in msb
        var msb16:UInt16 = UInt16(value) & 0b0011111110000000
        msb16 = msb16 >> 7
        // trim 16 bit to 8 bit (this should only trim empty bits
        let lsb8 = UInt8(lsb16)
        let msb8 = UInt8(msb16)

        // create packet
        var packet1 = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.length = 3;
        packet1.data.0 = 0xE0 + (UInt8(channel) - 1)//UInt8(channelVoiceMessage.PitchBendChange + (channel - 1))
        packet1.data.1 = lsb8
        packet1.data.2 = msb8
        //Add oacket to packet list and send it to destNum
        var packetList:MIDIPacketList = MIDIPacketList(numPackets: 1, packet: packet1);
        
        if !midiDestinations.isEmpty{
            MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);
            if MidiTrace {
                print("Midi: SendPitchBend: value = \(value)")
                print ("Midi: SendPitchBend: lsb8 = \(lsb8)")
                print ("Midi: SendPitchBend: msb8 = \(msb8)")
            }
        }
    }

    private func sendMidiRPN(channel:UInt8, rpn:UInt16, msb: UInt8, lsb: UInt8? = nil){

        //     Registered Parameter Values are set by the MIDI specification.
        //     lsb is optional. Some values use it some do not.
        //
        
        //     The RPN ID is a 14 bit value split into a MSB and LSB
        //     send 3 RPN messages. the first two set the high and low bytes of the
        //     Registered parameter number (RPN)
        //     then send the data for the RPN (value)
        //
        // 1.      Command byte: Bn
        //             B = CC ID (Means this is an CC Message)
        //             n = Channel:
        //         Data byte 1: 0x65, CC ID indicating that the following byte is the
        //         MSB of an RPN
        //         Data byte 2: MSB of the rpn
        //
        // 2.      Command byte: Bn (same as in first message)
        //         Data byte 1: 0x64, CC ID indicating that the following byte is the
        //         LSB of an RPN
        //         Data byte 2: value low byte
        //
        // 3.      Command byte: Bn (same as in first message)
        //         Data byte 1: 0x06, the following byte is the data value to be applied
        //         to the RPN
        //         Data byte 2: value
        //
        assert(channel <= 16)
        assert(rpn <= 6)
        if MidiTrace { print("Midi: SendRPN: channel = \(channel), RPN = \(rpn), value msb = \(msb), value lsb = \(String(describing: lsb ?? nil))")}
        
        //calculate msb and lsb of the RPN.
        // put bottom 7 bits in lsb
        let rpnLsb16:UInt16 = rpn & 0b000000001111111
        // put next 7 bits in msb
        var rpnMsb16:UInt16 = UInt16(rpn) & 0b0011111110000000
        rpnMsb16 = rpnMsb16 >> 7
        // trim 16 bit to 8 bit (this should only trim empty bits
        let rpnLsb8 = UInt8(rpnLsb16)
        //print ("Midi: SendMidiRPN rpnLsb8 = \(rpnLsb8)")
        let rpnMsb8 = UInt8(rpnMsb16)
        // print ("Midi: SendMidiRPN rpnMsb8 = \(rpnMsb8)")
        
        // set the RPN ID to value
        sendMidiCC(channel: channel, cc: controlChangeIDs.RPN_LSB, value: rpnLsb8)
        sendMidiCC(channel: channel, cc: controlChangeIDs.RPN_MSB, value: rpnMsb8)
        sendMidiCC(channel: channel, cc: controlChangeIDs.DataEntryMSB, value: msb)
        
        if lsb != nil { // send optional data field
            sendMidiCC(channel: channel, cc: controlChangeIDs.DataEntryLSB, value: lsb!)
        }
    }
    
    private func sendMidiCC(channel:UInt8, cc:UInt8, value: UInt8? = nil){
        // control change (CC) messages are 2 byte midi messages that allow 128 bit values to be sent to one of
        // 128 preset destinations representing things like the Modulation wheel and breath controllers.
        //
        // Command byte: Bn
        //     B = CC ID (Means this is an CC Message)
        //     n = Channel:
        //     Data byte 1: CC ID
        //     Data byte 2: value of the CC
        //
        // CC messages are also used for RPNs. See the sendMidiRPN function for more details
        var length:UInt8 = 0
        if value == nil {
            length = 1
        }
        else {
            length = 2
        }
        
        // create packet
        var packet1 = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.length = UInt16(length);
        packet1.data.0 = channelVoiceMessages.ControlChange | (UInt8(channel) - 1) //(0x90 + (channel-1))
        if value != nil {packet1.data.1 = value!}
        //packet1.data.1 = UInt8(value!)

        //Add oacket to packet list and send it to destNum
        var packetList = MIDIPacketList(numPackets: 1, packet: packet1);
        if destNum >= 1 {MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);}
        
        //print ("Midi: sendMidiCC: channel = \(channel), cc = \(cc), value = \(String(describing: value ?? nil))")
    }
    
    private struct noteAndPitchbend{
        var MIDINote: UInt8 = 0
        var PitchBend: UInt16 = 8192  // 0 of pitchbend range
    }
    
    private func freqToPB(frequency: Double, referenceFrequency: Double, pitchBendRange: Int) -> Int {
        var ret: Int = 8192
        var cents:Double = 0
        // get cents from root frequency compared to frequency
        cents = 1200 * log2(frequency / referenceFrequency)
        ret = centsToPitchBend(pitchBendRange: pitchBendRange, cents: cents)
        return ret
    }
    
    private func centsToPitchBend(pitchBendRange: Int, cents: Double) -> Int{
        let pbRangeInCents = Double(pitchBendRange * 100)
        if cents >= pbRangeInCents {
            return 16383
        }
        
        if cents < ( 0 - pbRangeInCents) {
            return 0
        }
        
        let centsTemp:Double = Double(cents) / (100.00 * Double(pitchBendRange))
        let retPB: Double = (centsTemp * 8192) + 8192
        return Int(retPB)
    }
    
    // returns number of octaves between freq1 and freq2
    private func numOctaves(freq1: Double, freq2:Double)->Int{
        //no = log2(f2/f1)
        let numOct = log2(freq1/freq2)
        return Int(numOct)
    }
    
    private func testCentsToPitchBend(){
        for pbRange in 1...12 {
            for cents in -1200...1200 {
                _ = centsToPitchBend(pitchBendRange: pbRange, cents: Double(cents))
            }
        }
    }
    
    private func makeStatusByte (command:Int8, channel: Int8)->Int8 {
        let ret:Int8 = command + channel-1
        return ret
    }
}
