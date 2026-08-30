//
//  SeqMidiOut.swift
//  GBGSound
//
//  A generic, channel-parameterized MIDI-out primitive for Seq - deliberately not a reuse of
//  Midi (which bundles a lot of Graph-specific surface: fixed root/X/Y/Z naming, MPE zone
//  declaration tuned to Graph's own defaults, tuning UI). Voice-naming is an app-level concern,
//  same "generic package, app does interpretation" principle Graph's own MIDI-input path
//  already established - this class only knows about channels and raw values. RPN/MPE-zone
//  declaration is deliberately not built here: not needed for driving Graph (its receive-side
//  packet parser only decodes note-on/off/pitch-bend, never RPN), and would only become
//  relevant for a real external synth (a future addition, not this task).
//
//  See the standalone-sequencer plan, phase 2, step 3b.
//

import Foundation
import CoreMIDI

public class SeqMidiOut {
    private var midiClient: MIDIClientRef = 0
    private var outPort: MIDIPortRef = 0
    private var destNum = 0

    public struct MidiEndpointInfo {
        var midiEndpoint: MIDIEndpointRef = 0
        var index: Int = 0
        public var name: String = ""
    }

    public var midiDestinations: [MidiEndpointInfo] = []

    public init() {}

    public func initMidi() {
        MIDIClientCreate("Seq" as CFString, nil, nil, &midiClient)
        MIDIOutputPortCreate(midiClient, "Seq" as CFString, &outPort)
        initMidiDestinations()
    }

    public func setMidiDestination(destination: Int) {
        guard destination >= 0, destination < midiDestinations.count else { return }
        destNum = destination
    }

    private func initMidiDestinations() {
        midiDestinations = []
        let numDestinations = MIDIGetNumberOfDestinations()
        guard numDestinations >= 1 else { return }
        for i in 0..<numDestinations {
            let device = MIDIGetDestination(i)
            var param: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(device, kMIDIPropertyDisplayName, &param)
            let name = (param?.takeRetainedValue() as String?) ?? "Unknown MIDI Destination \(i)"
            midiDestinations.append(MidiEndpointInfo(midiEndpoint: device, index: i, name: name))
        }
    }

    private struct ChannelVoiceMessages {
        let noteOff: UInt8 = 0b10000000
        let noteOn: UInt8 = 0b10010000
    }
    private let channelVoiceMessages = ChannelVoiceMessages()

    public func noteOn(channel: Int, note: Int, velocity: Int) {
        var packet1 = MIDIPacket()
        packet1.timeStamp = 0
        packet1.length = 3
        packet1.data.0 = channelVoiceMessages.noteOn | (UInt8(channel) - 1)
        packet1.data.1 = UInt8(note)
        packet1.data.2 = UInt8(velocity)
        var packetList = MIDIPacketList(numPackets: 1, packet: packet1)
        if !midiDestinations.isEmpty { MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList) }
    }

    public func noteOff(channel: Int, note: Int) {
        var packet1 = MIDIPacket()
        packet1.timeStamp = 0
        packet1.length = 3
        packet1.data.0 = channelVoiceMessages.noteOff | (UInt8(channel) - 1)
        packet1.data.1 = UInt8(note)
        packet1.data.2 = 0
        var packetList = MIDIPacketList(numPackets: 1, packet: packet1)
        if !midiDestinations.isEmpty { MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList) }
    }

    // Raw 14-bit value (0...16383, centered at 8192) - same encoding Midi.sendMidiPitchBend
    // already uses. Callers compute this via GBGCore's public PitchBendMath.freqToPB.
    public func pitchBend(channel: Int, value: Int) {
        let lsb16: UInt16 = UInt16(value) & 0b000000001111111
        var msb16: UInt16 = UInt16(value) & 0b0011111110000000
        msb16 = msb16 >> 7
        let lsb8 = UInt8(lsb16)
        let msb8 = UInt8(msb16)

        var packet1 = MIDIPacket()
        packet1.timeStamp = 0
        packet1.length = 3
        packet1.data.0 = 0xE0 + (UInt8(channel) - 1)
        packet1.data.1 = lsb8
        packet1.data.2 = msb8
        var packetList = MIDIPacketList(numPackets: 1, packet: packet1)
        if !midiDestinations.isEmpty { MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList) }
    }
}
