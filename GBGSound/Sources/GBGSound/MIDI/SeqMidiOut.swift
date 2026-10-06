//
//  SeqMidiOut.swift
//  GBGSound
//
//  A generic, channel-parameterized MIDI-out primitive for Seq - deliberately not a reuse of
//  Midi (which bundles a lot of Graph-specific surface: fixed root/X/Y/Z naming, MPE zone
//  declaration tuned to Graph's own defaults, tuning UI). Voice-naming is an app-level concern,
//  same "generic package, app does interpretation" principle Graph's own MIDI-input path
//  already established - this class only knows about channels and raw values. The one RPN it
//  sends is Pitch Bend Sensitivity (RPN 0), for Seq's Synth Out connection so a real synth
//  can adopt Seq's bend range; Graph's receive-side parser only decodes note-on/off/pitch-bend
//  and ignores it. MPE zone declaration (RPN 6) is still not built here.
//
//  See the standalone-sequencer plan, phase 2, step 3b.
//

import Foundation
import CoreMIDI

public class SeqMidiOut {
    private var midiClient: MIDIClientRef = 0
    private var outPort: MIDIPortRef = 0
    // The chosen destination, held by endpoint rather than list index so it survives the list
    // being rebuilt when devices/apps come and go (indices shift; endpoints don't). nil = the
    // chosen destination went away - sends are dropped rather than landing on whatever now
    // occupies its old index.
    private var selectedDestination: MIDIEndpointRef?

    public struct MidiEndpointInfo {
        var midiEndpoint: MIDIEndpointRef = 0
        var index: Int = 0
        public var name: String = ""
    }

    public var midiDestinations: [MidiEndpointInfo] = []

    public init() {}

    /// Fires on the main queue whenever CoreMIDI's set of devices/endpoints changes - another
    /// app (Graph) launching or quitting, a USB device plugged in, a Network MIDI session
    /// opening. Callers refresh their lists from here instead of only ever seeing what existed
    /// at launch.
    public var onSetupChanged: (() -> Void)?

    public func initMidi() {
        MIDIClientCreateWithBlock("Seq" as CFString, &midiClient) { [weak self] notification in
            // Property changes too, not just setup changes: a newly created virtual endpoint can
            // get its display name a moment after it's added, and Graph is found by name.
            switch notification.pointee.messageID {
            case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
                self?.scheduleSetupChanged()
            default:
                break
            }
        }
        MIDIOutputPortCreate(midiClient, "Seq" as CFString, &outPort)
        initMidiDestinations()
        selectedDestination = midiDestinations.first?.midiEndpoint
    }

    // CoreMIDI sends several notifications for one change (added, property, setup changed);
    // coalesce them into a single onSetupChanged per burst.
    private var setupChangePending = false

    private func scheduleSetupChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.setupChangePending else { return }
            self.setupChangePending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupChangePending = false
                self?.onSetupChanged?()
            }
        }
    }

    /// Index of the chosen destination in `midiDestinations`, or nil if it's gone.
    public var selectedDestinationIndex: Int? {
        guard let selectedDestination else { return nil }
        return midiDestinations.firstIndex { $0.midiEndpoint == selectedDestination }
    }

    /// Re-scans CoreMIDI's destinations, keeping the current choice (by endpoint) if it still
    /// exists. Returns false if the chosen destination has disappeared.
    @discardableResult
    public func refreshMidiDestinations() -> Bool {
        initMidiDestinations()
        if selectedDestinationIndex == nil { selectedDestination = nil }
        return selectedDestination != nil
    }

    private func send(_ packetList: inout MIDIPacketList) {
        guard let selectedDestination else { return }
        MIDISend(outPort, selectedDestination, &packetList)
    }

    // MARK: - Input (receiving a live performance, e.g. from Graph)
    //
    // Two independent paths feed the same decode/onEvent pipeline below, mirroring Midi.swift's
    // own identical two-path design (see its header comment on virtualDestination/initMidiInput
    // there) for the same reason: a same-Mac app can target a named virtual destination
    // directly (picking "Seq" from its own MIDI Destination picker), but a Network MIDI
    // connection or a USB-connected device shows up as a plain MIDI SOURCE instead, with no
    // "Seq"-named destination of its own to target - only the connect-to-a-source path can
    // reach that. This class has no transport-specific code either way; CoreMIDI already
    // abstracts same-Mac/USB/Network MIDI away identically. Opt-in (a separate call, not part
    // of initMidi()) since not every SeqMidiOut instance should advertise/listen - Seq's own
    // "Synth Out" connection has no reason to receive anything.
    private var virtualDestination: MIDIEndpointRef = 0
    private var inPort: MIDIPortRef = 0
    private var sourceNum = 0
    private var sourceConnected = false
    public var midiSources: [MidiEndpointInfo] = []

    // Reuses Midi.MidiInputEvent (GBGSound) rather than declaring a second, identical event
    // type - both classes live in this same module, and the shape (raw channel + note/velocity/
    // pitch-bend/CC, no built-in "channel N means X" interpretation) is exactly what this needs
    // too. Fires on the main queue, same as Midi's own onEvent - see handleIncomingPacketList
    // below.
    public var onEvent: ((Midi.MidiInputEvent) -> Void)?

    public func initMidiInput(name: String) {
        guard midiClient != 0 else { return } // initMidi() must run first - same client the output side uses
        MIDIDestinationCreateWithBlock(midiClient, name as CFString, &virtualDestination) { [weak self] packetListPointer, _ in
            self?.handleIncomingPacketList(packetListPointer)
        }
        MIDIInputPortCreateWithBlock(midiClient, "\(name) In" as CFString, &inPort) { [weak self] packetListPointer, _ in
            self?.handleIncomingPacketList(packetListPointer)
        }
        initMidiSources()
    }

    // Mirrors Midi.setMidiSource exactly (disconnect whatever was previously connected first,
    // so switching sources at runtime doesn't leave the old one still delivering packets too).
    public func setMidiSource(source: Int) {
        guard source >= 0, source < midiSources.count else { return }
        if sourceConnected, sourceNum < midiSources.count {
            MIDIPortDisconnectSource(inPort, midiSources[sourceNum].midiEndpoint)
        }
        sourceNum = source
        MIDIPortConnectSource(inPort, midiSources[sourceNum].midiEndpoint, nil)
        sourceConnected = true
    }

    // Re-scans CoreMIDI's current source list - see Midi.refreshMidiPorts's own comment for why
    // this needs to exist at all (initMidiSources only ever runs once, at initMidiInput). Also
    // re-resolves the currently connected source by name across the rebuild, same reasoning as
    // Midi.refreshMidiPorts.
    public func refreshMidiSources() {
        let previousSourceName = sourceNum < midiSources.count ? midiSources[sourceNum].name : nil
        initMidiSources()
        if let previousSourceName, let newIndex = midiSources.firstIndex(where: { $0.name == previousSourceName }) {
            sourceNum = newIndex
        }
    }

    private func initMidiSources() {
        midiSources = []
        let numSources = MIDIGetNumberOfSources()
        guard numSources >= 1 else { return }
        for i in 0..<numSources {
            let device = MIDIGetSource(i)
            var param: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(device, kMIDIPropertyDisplayName, &param)
            let name = (param?.takeRetainedValue() as String?) ?? "Unknown MIDI Source \(i)"
            midiSources.append(MidiEndpointInfo(midiEndpoint: device, index: i, name: name))
        }
    }

    private struct InputChannelVoiceMessages {
        let noteOff: UInt8 = 0b10000000
        let noteOn: UInt8 = 0b10010000
        let pitchBendChange: UInt8 = 0b11100000
    }
    private let inputChannelVoiceMessages = InputChannelVoiceMessages()

    // Decodes note-on/off and pitch-bend only (not the full message set Midi.swift's own
    // receive path handles - control change/etc. aren't needed for this class's one purpose,
    // capturing a live pitch performance). Mirrors that decode exactly for the messages both
    // handle, so behavior stays identical regardless of which class received the bytes.
    private func handleIncomingPacketList(_ packetListPointer: UnsafePointer<MIDIPacketList>) {
        var packet = packetListPointer.pointee.packet
        let numPackets = packetListPointer.pointee.numPackets
        for _ in 0..<numPackets {
            let status = packet.data.0
            let messageType = status & 0xF0
            let channel = Int(status & 0x0F) + 1
            let event: Midi.MidiInputEvent?
            switch messageType {
            case inputChannelVoiceMessages.noteOn:
                let velocity = Int(packet.data.2)
                event = velocity == 0
                    ? Midi.MidiInputEvent(channel: channel, kind: .noteOff(note: Int(packet.data.1)))
                    : Midi.MidiInputEvent(channel: channel, kind: .noteOn(note: Int(packet.data.1), velocity: velocity))
            case inputChannelVoiceMessages.noteOff:
                event = Midi.MidiInputEvent(channel: channel, kind: .noteOff(note: Int(packet.data.1)))
            case inputChannelVoiceMessages.pitchBendChange:
                let value = Int(packet.data.2) << 7 | Int(packet.data.1)
                event = Midi.MidiInputEvent(channel: channel, kind: .pitchBend(value: value))
            default:
                event = nil
            }
            if let event {
                DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    public func setMidiDestination(destination: Int) {
        guard destination >= 0, destination < midiDestinations.count else { return }
        selectedDestination = midiDestinations[destination].midiEndpoint
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
        send(&packetList)
    }

    public func noteOff(channel: Int, note: Int) {
        var packet1 = MIDIPacket()
        packet1.timeStamp = 0
        packet1.length = 3
        packet1.data.0 = channelVoiceMessages.noteOff | (UInt8(channel) - 1)
        packet1.data.1 = UInt8(note)
        packet1.data.2 = 0
        var packetList = MIDIPacketList(numPackets: 1, packet: packet1)
        send(&packetList)
    }

    /// Sets the receiver's pitch bend range on `channel` to `semitones` (RPN 0, Pitch Bend
    /// Sensitivity): select RPN 0 (CC 101/100 = 0/0), Data Entry MSB = semitones, LSB = 0 cents,
    /// then deselect (RPN null, 127/127) so a stray later Data Entry can't change it again.
    public func pitchBendSensitivity(channel: Int, semitones: Int) {
        let semitones = UInt8(max(0, min(127, semitones)))
        for (cc, value) in [(101, 0), (100, 0), (6, Int(semitones)), (38, 0), (101, 127), (100, 127)] {
            controlChange(channel: channel, controller: UInt8(cc), value: UInt8(value))
        }
    }

    private func controlChange(channel: Int, controller: UInt8, value: UInt8) {
        var packet1 = MIDIPacket()
        packet1.timeStamp = 0
        packet1.length = 3
        packet1.data.0 = 0xB0 + (UInt8(channel) - 1)
        packet1.data.1 = controller
        packet1.data.2 = value
        var packetList = MIDIPacketList(numPackets: 1, packet: packet1)
        send(&packetList)
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
        send(&packetList)
    }
}
