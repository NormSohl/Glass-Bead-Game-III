//
//  MIDI.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 2/8/24.
//

import Foundation
import GBGCore
import CoreMIDI
import AudioToolbox

public class Midi{
    // control debug trace
    private var midiTrace = false

    // since we change the root frequency during tuning, save this here
    private var referenceFrequency = 0.0

    // midi working variables
    private var rootMidiFrequency: Double = 0.0
    private var rootMidiNote: Int = 60  // middle c
    private var rootMidiVelocity: Int = 80
    private var rootMidiPitchBend: Int = 8192

    private var xMidiFrequency: Double = 0.0
    private var xMidiNote: Int = 60 // middle c
    private var xMidiVelocity: Int = 100
    private var xMidiPitchBend: Int = 8192

    private var yMidiFrequency: Double = 0.0
    private var yMidiNote: Int = 60 // middle c
    private var yMidiVelocity: Int = 100
    private var yMidiPitchBend: Int = 8192

    private var zMidiFrequency: Double = 0.0
    private var zMidiNote: Int = 60 // middle c
    private var zMidiVelocity: Int = 100
    private var zMidiPitchBend: Int = 8192

    private var pitchBendRangeMPE: Int = 0
    //private var PitchMidiNote: UInt8 = 60 // middle C

    // CoreMIDI values
    private var midiClient: MIDIClientRef = 0;
    private var outPort:MIDIPortRef = 0;
    private var inPort: MIDIPortRef = 0;
    // Named virtual destination another app (Seq) can target directly from its own MIDI
    // Destination picker - see initMidi(). Distinct from inPort above, which only receives by
    // connecting out to someone else's source (setMidiSource); this is the reverse direction -
    // Graph as the addressable target. Both feed the same handleIncomingPacketList/onEvent
    // pipeline, so every existing consumer works identically regardless of which path bytes
    // arrived through.
    private var virtualDestination: MIDIEndpointRef = 0;

    // midi sources
    public var midiSources:[midiEndpoint] = []
    private var sourceNum = 0
    private var sourceConnected = false

    //midi destinations
    public var midiDestinations:[midiEndpoint] = []
    private var destNum = 0

    // midi enable channels - false until each one's own zone has actually been touched at
    // least once (Sound.apply{Graph,Z}VoiceEnables/applyDroneVoiceEnable set the real value
    // from then on, but only ever run in response to that zone's own touch begin/end - see
    // Sound.swift's zone-isolation comments). Defaulting true left the untouched zones enabled
    // until their first touch: any startMidi() call before the Z-slider had ever been touched
    // this session, e.g. a plain graph touch, sent a Z note-on too, at whatever garbage pitch
    // zMidiFrequency/zMidiNote happened to default to. Norm remembered defaulting true as
    // possibly intentional (guarding against hung notes from a previous session) but agreed
    // it isn't needed - stopMidi's note-off sweep already unconditionally covers channels 1-4
    // (or 2-5 in MPE) regardless of these flags, so hung-note cleanup was never what this
    // default was doing.
    public var rootMidiEnable = false
    public var xMidiEnable = false
    public var yMidiEnable = false
    public var zMidiEnable = false

    // midi notes on?
    var rootMidiIsPlaying = false
    var xMidiIsPlaying = false
    var yMidiIsPlaying = false
    var zMidiIsPlaying = false

    // midi MPE channels - X/Y/Z first, drone last (not first) since drone is the one optional
    // voice: a receiver only listening for "my three main voices" can just use the first
    // three member channels and never has to care whether drone happens to be on, instead of
    // drone always occupying the first one and shifting what X/Y/Z sit on depending on nothing
    // (their own channels were always fixed either way, but always one slot later than they
    // needed to be). Channel 1 itself is reserved as the MPE zone's master channel - see
    // enableMPE - so member channels start at 2.
    public var xMidiMPEChannel = 2
    public var yMidiMPEChannel = 3
    public var zMidiMPEChannel = 4
    public var rootMidiMPEChannel = 5

    // list of possible midi notes
    var noteList = NoteList()

    // possible midi destinations
    public struct midiEndpoint{
        var midiEndpoint: MIDIEndpointRef = 0
        var index: Int = 0
        public var name: String = ""
    }

    // Parsed incoming MIDI, reported raw - channel + note/velocity/pitch-bend - with no
    // built-in "channel 2 means X" interpretation. That mapping is graph-specific and belongs
    // to whatever owns AppSettings (Sound.handleIncomingMidi in the app target), not this
    // generic package - see the standalone-sequencer foundation plan, step 3.
    public struct MidiInputEvent {
        public enum Kind {
            case noteOn(note: Int, velocity: Int)
            case noteOff(note: Int)
            case pitchBend(value: Int)
            case controlChange(controller: Int, value: Int)
        }
        public let channel: Int // 1...16
        public let kind: Kind
    }

    // Fires on the main queue (CoreMIDI's read block runs on its own high-priority thread,
    // and every plausible consumer of this - AppSettings, Sound's touch/enable state - is
    // main-thread-bound UI state) whenever a note-on/off or pitch-bend arrives on the
    // connected source. nil (the default) until something sets it - there's no source
    // connected at all until setMidiSource is called, so this is inert out of the box.
    public var onEvent: ((MidiInputEvent) -> Void)?

    public init() {}

    public func initMidi(){
        MIDIClientCreate("Glass Bead Game" as CFString, nil, nil, &midiClient);
        MIDIOutputPortCreate(midiClient, "Glass Bead Game" as CFString, &outPort);
        initMidiInput()
        initVirtualDestination()
        initMidiSources()
        initMidiDestinations()
        enableMPE()
    }

    // Creates a named virtual destination ("Glass Bead Game III") so another app can send to
    // Graph directly by picking it from a MIDI Destination picker, rather than Graph always
    // having to be the one connecting out to a source. Decoded through the exact same
    // handleIncomingPacketList used by initMidiInput()'s connected-source path below - see the
    // standalone-sequencer plan's phase 2, step 3b.
    private func initVirtualDestination(){
        MIDIDestinationCreateWithBlock(midiClient, "Glass Bead Game III" as CFString, &virtualDestination) { [weak self] packetListPointer, _ in
            self?.handleIncomingPacketList(packetListPointer)
        }
    }

    public func setMidiDestination(destination: Int){
        destNum = destination
        enableMPE()
        sendPitchBendSensitivity()
    }

    // Mirrors setMidiDestination above, for the input side - connects the input port to the
    // chosen source (disconnecting whatever was previously connected first, if anything), so
    // switching sources at runtime doesn't leave the old one still delivering packets too.
    public func setMidiSource(source: Int){
        guard source >= 0, source < midiSources.count else { return }
        if sourceConnected, sourceNum < midiSources.count {
            MIDIPortDisconnectSource(inPort, midiSources[sourceNum].midiEndpoint)
        }
        sourceNum = source
        MIDIPortConnectSource(inPort, midiSources[sourceNum].midiEndpoint, nil)
        sourceConnected = true
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
        //print("\nMIDI: send registeredParameterNumbers.mpeConfiguration")
        let numOfChannelsInLowerZone:UInt8 = 15 // use all channels other than master
        sendMidiRPN(channel: mpeChannel.lowerZoneMasterChannel,
                    rpn: registeredParameterNumbers.mpeConfiguration,
                    msb: numOfChannelsInLowerZone)
    }

    // RPN 0 (Pitch Bend Sensitivity) tells the receiver what range to interpret this app's
    // outgoing pitch-bend numbers against - without it, a receiver just falls back to its own
    // default (often 2 semitones on plain GM-style gear, or 48 on many MPE-oriented
    // instruments), which won't match pitchBendRangeMPE and renders every bend at the wrong
    // interval. Norm: real devices often ignore this and need manual configuration anyway, but
    // it's still the right thing to send. This is zone-wide - one message on the zone's master
    // channel covers every member channel, same as the MPE Configuration message above - so
    // it's called from the same places that resend that (destination changes). Deliberately
    // NOT called from inside enableMPE() itself: enableMPE's very first call happens from
    // initMidi(), at app launch, before AppSettings has ever pushed a real pitchBendRangeMPE
    // value - sending 0 there would tell a receiver to actually zero out its bend range, worse
    // than not telling it anything. Every call site below runs after a real value is guaranteed
    // to be set.
    private func sendPitchBendSensitivity(){
        sendMidiRPN(channel: mpeChannel.lowerZoneMasterChannel,
                    rpn: registeredParameterNumbers.pitchBendSensitivity,
                    msb: UInt8(pitchBendRangeMPE),
                    lsb: 0)
    }

    public func startMidi(){
        // note values and pitchbend have already been stored in shared variables
        if midiTrace {print("\nMidi: startMidi: rootMidiNote = \(rootMidiNote), xMidiNote = \(xMidiNote), yMidiNote = \(yMidiNote), rootMidiFrequency = \(rootMidiFrequency)")}
        if rootMidiEnable {
            rootMidiIsPlaying = true
            // Root (drone) note - always last of the four MPE channels, see the
            // rootMidiMPEChannel declaration above.
            rootMidiPitchBend = PitchBendMath.freqToPB(frequency: rootMidiFrequency, referenceFrequency: referenceFrequency, pitchBendRange: pitchBendRangeMPE)
            sendMidiNoteOn(channel: rootMidiMPEChannel, note: rootMidiNote, velocity:rootMidiVelocity)
            sendMidiPitchBend(channel: rootMidiMPEChannel, value: rootMidiPitchBend) // root note has centered pitchbend, should be 8192
        }

        if xMidiEnable {
            xMidiIsPlaying = true
            xMidiPitchBend = PitchBendMath.freqToPB(frequency: xMidiFrequency, referenceFrequency: referenceFrequency, pitchBendRange: pitchBendRangeMPE)
            sendMidiNoteOn(channel: xMidiMPEChannel, note: xMidiNote, velocity: xMidiVelocity)
            sendMidiPitchBend(channel: xMidiMPEChannel, value: xMidiPitchBend)
        }

        if yMidiEnable {
            yMidiIsPlaying = true
            yMidiPitchBend = PitchBendMath.freqToPB(frequency: yMidiFrequency, referenceFrequency: referenceFrequency, pitchBendRange: pitchBendRangeMPE)
            sendMidiNoteOn(channel: yMidiMPEChannel, note: yMidiNote, velocity: yMidiVelocity)
            sendMidiPitchBend(channel: yMidiMPEChannel, value: yMidiPitchBend)
        }

        if zMidiEnable {
            zMidiIsPlaying = true
            zMidiPitchBend = PitchBendMath.freqToPB(frequency: zMidiFrequency, referenceFrequency: referenceFrequency, pitchBendRange: pitchBendRangeMPE)
            sendMidiNoteOn(channel: zMidiMPEChannel, note: zMidiNote, velocity: zMidiVelocity)
            sendMidiPitchBend(channel: zMidiMPEChannel, value: zMidiPitchBend)
        }
    }

    public func stopMidi(){
        if midiTrace {print("\nMidi: stopMidi: rootMidiNote = \(rootMidiNote), xMidiNote = \(xMidiNote), yMidiNote = \(yMidiNote)")}
        rootMidiIsPlaying = false
        xMidiIsPlaying = false
        yMidiIsPlaying = false
        zMidiIsPlaying = false

        //print ("Midi: stopMidi: Root")
        sendMidiNoteOff(channel: rootMidiMPEChannel, note: rootMidiNote)

        //print ("Midi: stopMidi: X")
        sendMidiNoteOff(channel: xMidiMPEChannel, note: xMidiNote)

        //print ("Midi: stopMidi: Y")
        sendMidiNoteOff(channel: yMidiMPEChannel, note: yMidiNote)

        //print ("Midi: stopMidi: Z")
        sendMidiNoteOff(channel: zMidiMPEChannel, note: zMidiNote)
    }

    public func setMidiReferencePitch(frequency: Double){
        referenceFrequency = frequency
        rootMidiFrequency = referenceFrequency
        if midiTrace { print("Midi: SetMidiReferencePitch: frequency = \(referenceFrequency)")}
    }

    // Public as of the standalone-sequencer plan's drone-receive extension (Sound.swift's
    // beginExternalDroneDrive/etc.) - moves the drone's own played frequency without touching
    // referenceFrequency, unlike setMidiReferencePitch. Previously internal, called only from
    // tuning/verify-range flows within this file - those always follow up with a full
    // startMidi() (note-on + pitch-bend together), so this never needed its own "already
    // playing, push a live update" branch. External drone drive breaks that assumption (a
    // pitch-bend-only message can arrive on an already-sounding drone note), so this now
    // mirrors setMidiXPitch/etc.'s live-update branch - confirmed missing via a real CoreMIDI
    // monitor: a live pitch-bend update produced no outgoing bytes before this fix.
    public func setMidiRootPitch(frequency: Double){
        rootMidiFrequency = frequency
        if rootMidiIsPlaying{
            rootMidiPitchBend = PitchBendMath.freqToPB(frequency: rootMidiFrequency, referenceFrequency: referenceFrequency, pitchBendRange: pitchBendRangeMPE)
            sendMidiPitchBend(channel: rootMidiMPEChannel, value: rootMidiPitchBend)
        }
        if midiTrace { print("Midi: SetRootPitch: frequency = \(rootMidiFrequency)")}
    }

    public func setMidiXPitch(frequency: Double){
        xMidiFrequency = frequency
        if xMidiIsPlaying{
            xMidiPitchBend = PitchBendMath.freqToPB(frequency: xMidiFrequency, referenceFrequency: referenceFrequency, pitchBendRange: pitchBendRangeMPE)
            sendMidiPitchBend(channel: xMidiMPEChannel, value: xMidiPitchBend)
        }
        if midiTrace { print("Midi: SetXMidiPitch: frequency = \(xMidiFrequency)")}
    }

    public func setMidiYPitch(frequency: Double){
        yMidiFrequency = frequency
        if yMidiIsPlaying{
            yMidiPitchBend = PitchBendMath.freqToPB(frequency: yMidiFrequency, referenceFrequency: referenceFrequency, pitchBendRange: pitchBendRangeMPE)
            sendMidiPitchBend(channel: yMidiMPEChannel, value: yMidiPitchBend)
        }
        if midiTrace { print("Midi: SetYMidiPitch: frequency = \(yMidiFrequency)")}
    }

    public func setMidiZPitch(frequency: Double){
        zMidiFrequency = frequency
        if zMidiIsPlaying{
            zMidiPitchBend = PitchBendMath.freqToPB(frequency: zMidiFrequency, referenceFrequency: referenceFrequency, pitchBendRange: pitchBendRangeMPE)
            sendMidiPitchBend(channel: zMidiMPEChannel, value: zMidiPitchBend)
        }
        if midiTrace { print("Midi: SetZMidiPitch: frequency = \(zMidiFrequency)")}
    }

    public func setMidiPitchBendRangeMPE(pitchBendRange: Int){
        pitchBendRangeMPE = pitchBendRange
        //print("\nMidi: SetMidiPitchBendRangeMPE: Range = \(pitchBendRangeMPE)")
        sendPitchBendSensitivity()
    }

    public func setRootNote(note: Int){
        rootMidiNote = note
    }

    // Saved by tuneStart, restored by tuneStop - see the comment on tuneStart for why.
    private var preTuneRootEnable = false
    private var preTuneXEnable = false
    private var preTuneYEnable = false
    private var preTuneZEnable = false

    public func tuneStart(){
        // Tuning is a deliberate, explicit action independent of whatever's currently
        // touched - it should always sound all four voices, unlike startMidi()'s normal
        // callers which rely on rootMidiEnable/xMidiEnable/yMidiEnable/zMidiEnable already
        // reflecting live touch state (see Sound.apply*VoiceEnables). Forcing them true here
        // without saving/restoring would leave them stuck true after tuning ends, right back
        // to the stale-enable bug fixed by defaulting them false in the first place - so the
        // real prior state is saved here and put back in tuneStop.
        preTuneRootEnable = rootMidiEnable
        preTuneXEnable = xMidiEnable
        preTuneYEnable = yMidiEnable
        preTuneZEnable = zMidiEnable
        rootMidiEnable = true
        xMidiEnable = true
        yMidiEnable = true
        zMidiEnable = true
        // set all frequencies  to A:440
        setMidiRootPitch(frequency: 440)
        setMidiXPitch(frequency: 440)
        setMidiYPitch(frequency: 440)
        setMidiZPitch(frequency: 440)
        if midiTrace {print("Midi: tuneStart")}
        startMidi()
    }

    public func tuneStop(){
        if midiTrace {print("Midi: tuneStop")}
        stopMidi()
        rootMidiEnable = preTuneRootEnable
        xMidiEnable = preTuneXEnable
        yMidiEnable = preTuneYEnable
        zMidiEnable = preTuneZEnable
        setMidiRootPitch(frequency: referenceFrequency)
    }

    // Separate save/restore slots from tuneStart/tuneStop's - this and Tune Midi are two
    // different modal calibration flows in the UI and shouldn't reasonably run at once, but
    // keeping them independent avoids any risk of one clobbering the other's saved state.
    private var preVerifyRootEnable = false
    private var preVerifyXEnable = false
    private var preVerifyYEnable = false
    private var preVerifyZEnable = false
    private var verifyRangeActive = false

    /// Sounds all four voices together at `ratio` relative to the current root (1.0 =
    /// unison, 1.5 = a pure 3/2 fifth, 2.0 = an octave - just-intonation ratios, matching
    /// this app's actual tuning system, not equal-tempered cents) - lets someone confirm the
    /// pitch bend range this app declares (see sendPitchBendSensitivity) is actually what
    /// their receiver is using, by ear, against gear that can't be queried or configured over
    /// MIDI. Callable repeatedly with a different ratio to jump straight to a different
    /// interval without stopping first - each call is a clean note-off/note-on retrigger
    /// (simpler and more robust than trying to glide root's pitch live, which nothing else in
    /// this class currently supports), a small, acceptable click for a calibration tool no one
    /// is performing with.
    public func verifyRangeSet(ratio: Double){
        if verifyRangeActive {
            stopMidi()
        } else {
            preVerifyRootEnable = rootMidiEnable
            preVerifyXEnable = xMidiEnable
            preVerifyYEnable = yMidiEnable
            preVerifyZEnable = zMidiEnable
            rootMidiEnable = true
            xMidiEnable = true
            yMidiEnable = true
            zMidiEnable = true
            verifyRangeActive = true
        }
        let frequency = referenceFrequency * ratio
        setMidiRootPitch(frequency: frequency)
        setMidiXPitch(frequency: frequency)
        setMidiYPitch(frequency: frequency)
        setMidiZPitch(frequency: frequency)
        if midiTrace {print("Midi: verifyRangeSet: ratio = \(ratio)")}
        startMidi()
    }

    public func verifyRangeStop(){
        guard verifyRangeActive else { return }
        if midiTrace {print("Midi: verifyRangeStop")}
        stopMidi()
        rootMidiEnable = preVerifyRootEnable
        xMidiEnable = preVerifyXEnable
        yMidiEnable = preVerifyYEnable
        zMidiEnable = preVerifyZEnable
        setMidiRootPitch(frequency: referenceFrequency)
        verifyRangeActive = false
    }

    private func initMidiInput(){
        MIDIInputPortCreateWithBlock(midiClient, "Glass Bead Game" as CFString, &inPort) { [weak self] packetListPointer, _ in
            self?.handleIncomingPacketList(packetListPointer)
        }
    }

    // Decodes each packet in the list into a MidiInputEvent and dispatches it via onEvent, on
    // the main queue - this block runs on CoreMIDI's own receive thread, not main. Note on/off,
    // pitch bend, and control change are decoded (control change generically - any controller
    // number/value, e.g. CC64 sustain pedal - with no built-in "CC64 means pedal" interpretation,
    // same "report raw, let the app target interpret" split as the rest of this input path);
    // anything else (aftertouch, program change...) is silently ignored.
    private func handleIncomingPacketList(_ packetListPointer: UnsafePointer<MIDIPacketList>){
        var packet = packetListPointer.pointee.packet
        let numPackets = packetListPointer.pointee.numPackets
        for _ in 0..<numPackets {
            let status = packet.data.0
            let messageType = status & 0xF0
            let channel = Int(status & 0x0F) + 1
            let event: MidiInputEvent?
            switch messageType {
            case channelVoiceMessages.noteOn:
                // Velocity 0 is a note-off in disguise, per spec - some sources send it instead
                // of a real 0x80 note-off.
                let velocity = Int(packet.data.2)
                event = velocity == 0
                    ? MidiInputEvent(channel: channel, kind: .noteOff(note: Int(packet.data.1)))
                    : MidiInputEvent(channel: channel, kind: .noteOn(note: Int(packet.data.1), velocity: velocity))
            case channelVoiceMessages.noteOff:
                event = MidiInputEvent(channel: channel, kind: .noteOff(note: Int(packet.data.1)))
            case channelVoiceMessages.pitchBendChange:
                let value = Int(packet.data.2) << 7 | Int(packet.data.1)
                event = MidiInputEvent(channel: channel, kind: .pitchBend(value: value))
            case channelVoiceMessages.controlChange:
                event = MidiInputEvent(channel: channel, kind: .controlChange(controller: Int(packet.data.1), value: Int(packet.data.2)))
            default:
                event = nil
            }
            if midiTrace { print("Midi: handleIncomingPacketList: status=\(String(format: "0x%02X", status)) messageType=\(String(format: "0x%02X", messageType)) channel=\(channel) event=\(String(describing: event))") }
            if let event {
                DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func initMidiSources(){
        let numSources = MIDIGetNumberOfSources()

        if numSources >= 1{
            for i in 0...numSources-1{  // does this need to be -1?
                let device = MIDIGetSource(i)
                var param: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(device, kMIDIPropertyDisplayName, &param)
                let name = (param?.takeRetainedValue() as String?) ?? "Unknown MIDI Source \(i)"
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
                let name = (param?.takeRetainedValue() as String?) ?? "Unknown MIDI Destination \(i)"
                midiDestinations.append(midiEndpoint(midiEndpoint: device, index: i, name: name))
            }
        }
    }

    // MARK: - Network MIDI (RTP-MIDI over Wi-Fi, or over a USB-Ethernet-style link)
    //
    // iPadOS has no system-level "Network MIDI" panel the way macOS's Audio MIDI Setup does -
    // this app-level toggle is what makes an iPad reachable that way at all. macOS doesn't
    // strictly need it (Norm can already do this via Audio MIDI Setup), but the same call works
    // there too rather than gating it in this generic package - ControlView only surfaces the
    // toggle on iOS, where it's actually the only way in.
    //
    // Retained here, not just a local variable in setNetworkMIDIEnabled below -
    // MIDINetworkSession.default() is *not* a system-held singleton the way its name suggests;
    // nothing else keeps it alive, so a purely local reference gets deallocated (tearing the
    // session back down, silently) the moment that function returns, before Bonjour ever gets a
    // chance to advertise anything - the exact, well-known pitfall behind "isEnabled = true does
    // nothing" reports for this API. A stored property here, on an object sound.midi already
    // keeps alive for the app's whole lifetime, is what actually keeps it enabled.
    private var networkSession: MIDINetworkSession?

    // connectionPolicy .anyone accepts any incoming connection on the local network with no
    // manual host/address entry required on either side - reasonable for a local, trusted-
    // network performance tool; revisit if that's ever too permissive for how this gets used.
    // Once enabled, the session's own endpoint shows up in the normal midiSources/
    // midiDestinations lists exactly like any other port - refreshMidiPorts() below is what
    // actually picks it up (or a USB-connected device, or anything else that appeared after
    // initMidi() already ran once at launch).
    public func setNetworkMIDIEnabled(_ enabled: Bool) {
        let session = MIDINetworkSession.default()
        session.isEnabled = enabled
        session.connectionPolicy = enabled ? .anyone : .noOne
        networkSession = enabled ? session : nil
        refreshMidiPorts()
    }

    // Re-scans CoreMIDI's current source/destination lists. initMidiSources/initMidiDestinations
    // above only ever run once, at initMidi() - anything that appears afterward (a cable
    // plugged in, another app's virtual port, Network MIDI toggled on) never shows up without
    // this. Clears both lists first (unlike the one-shot init methods, which just append) so
    // calling this more than once doesn't duplicate entries, and re-resolves the currently
    // selected source/destination by name across the rebuild - the array index a picker binds
    // to isn't stable across a refresh, but the underlying MIDIEndpointRef connection
    // (setMidiSource's own MIDIPortConnectSource) doesn't need to change, just which index
    // means "the same one" for the UI going forward.
    public func refreshMidiPorts() {
        let previousSourceName = sourceNum < midiSources.count ? midiSources[sourceNum].name : nil
        let previousDestName = destNum < midiDestinations.count ? midiDestinations[destNum].name : nil

        midiSources = []
        initMidiSources()
        midiDestinations = []
        initMidiDestinations()

        if let previousSourceName, let newIndex = midiSources.firstIndex(where: { $0.name == previousSourceName }) {
            sourceNum = newIndex
        }
        if let previousDestName, let newIndex = midiDestinations.firstIndex(where: { $0.name == previousDestName }) {
            destNum = newIndex
        }
    }

    private struct ChannelVoiceMessages{
        let noteOff:UInt8 = 0b10000000
        let noteOn:UInt8 =  0b10010000
        let polyphonicKeyPressure:UInt8 = 0b10100000
        let controlChange:UInt8 = 0b10110000
        let programChange:UInt8 = 0b11000000
        let channelPressure:UInt8 = 0b11010000
        let pitchBendChange:UInt8 = 0b11100000
        let channelModeMessages:UInt8 = 0b10110000
    }
    private let channelVoiceMessages = ChannelVoiceMessages()

    private struct ControlChangeIDs{
        // there are too many to enter without need. Add them if needed
        // CC messages
        let dataEntryMSB:UInt8 = 0x06
        let dataEntryLSB:UInt8  = 0x26
        let rpnLSB:UInt8  = 0x64
        let rpnMSB:UInt8  = 0x65

        // Channel Mode Messages
        let monoModeOn:UInt8 = 0x7E
        let polyModeOn:UInt8 = 0x7F
    }
    private let controlChangeIDs = ControlChangeIDs()

    private struct RegisteredParameterNumbers{
        let pitchBendSensitivity:UInt16  = 0x00
        let channelFineTuning:UInt16  = 0x01
        let channelCoarseTuning:UInt16  = 0x02
        let tuningProgramChange:UInt16  = 0x03
        let tuningBankSelect:UInt16  = 0x04
        let modulationDepthRange:UInt16  = 0x05
        let mpeConfiguration:UInt16  = 0x06
    }
    private let registeredParameterNumbers = RegisteredParameterNumbers()

    private func sendMidiNoteOn(channel:Int, note:Int, velocity:Int){
        if midiTrace {print ("Midi: SendNoteOn: channel = \(channel), note = \(note), velocity = \(velocity)")}

        // create packet
        var packet1 = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.length = 3;
        packet1.data.0 = channelVoiceMessages.noteOn | (UInt8(channel) - 1) //(0x90 + (channel-1))
        packet1.data.1 = UInt8(note)
        packet1.data.2 = UInt8(velocity)
        //Add packet to packet list and send it to destNum
        var packetList = MIDIPacketList(numPackets: 1, packet: packet1);
        if !midiDestinations.isEmpty {MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);}
    }

    private func sendMidiNoteOff(channel:Int, note:Int){
        if midiTrace {print ("Midi: SendNoteOff: channel = \(channel), note = \(note)")}
        // create packet
        var packet1 = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.length = 3;
        packet1.data.0 = channelVoiceMessages.noteOff | (UInt8(channel) - 1) //UInt8(0x80 + (channel-1))
        packet1.data.1 = UInt8(note)
        packet1.data.2 = 0
        //Add packet to packet list and send it to destNum
        var packetList:MIDIPacketList = MIDIPacketList(numPackets: 1, packet: packet1);
        if !midiDestinations.isEmpty {MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);}
    }

    private func sendMidiPitchBend(channel: Int, value: Int){
        //if midiTrace {print ("Midi: SendPitchBend: channel = \(channel), value = \(value)")}
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
        packet1.data.0 = 0xE0 + (UInt8(channel) - 1)//UInt8(channelVoiceMessages.pitchBendChange + (channel - 1))
        packet1.data.1 = lsb8
        packet1.data.2 = msb8
        //Add packet to packet list and send it to destNum
        var packetList:MIDIPacketList = MIDIPacketList(numPackets: 1, packet: packet1);

        if !midiDestinations.isEmpty{
            MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);
            if midiTrace {
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
        if midiTrace { print("Midi: SendRPN: channel = \(channel), RPN = \(rpn), value msb = \(msb), value lsb = \(String(describing: lsb ?? nil))")}

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
        sendMidiCC(channel: channel, cc: controlChangeIDs.rpnLSB, value: rpnLsb8)
        sendMidiCC(channel: channel, cc: controlChangeIDs.rpnMSB, value: rpnMsb8)
        sendMidiCC(channel: channel, cc: controlChangeIDs.dataEntryMSB, value: msb)

        if lsb != nil { // send optional data field
            sendMidiCC(channel: channel, cc: controlChangeIDs.dataEntryLSB, value: lsb!)
        }
    }

    private func sendMidiCC(channel:UInt8, cc:UInt8, value: UInt8? = nil){
        // control change (CC) messages are 2 or 3 byte midi messages that allow 128 bit values to be sent to one of
        // 128 preset destinations representing things like the Modulation wheel and breath controllers.
        //
        // Command byte: Bn
        //     B = CC ID (Means this is an CC Message)
        //     n = Channel:
        //     Data byte 1: CC ID
        //     Data byte 2: value of the CC (omitted entirely for a value-less CC, length 2 instead of 3)
        //
        // CC messages are also used for RPNs. See the sendMidiRPN function for more details.
        //
        // Fixed a real bug here (2026-08-29): `cc` was never actually written into the packet
        // at all, and `value` was written into data.1 - the CC-number slot - instead of data.2,
        // the value slot. Every RPN this file has ever sent (MPE Configuration in
        // enableMPE/disableMPE, and Pitch Bend Sensitivity) was going out as a malformed,
        // incomplete packet no receiver could have interpreted correctly - confirmed via the
        // same CoreMIDI virtual-destination monitor used for this session's other MIDI
        // testing: enableMPE's RPN6 produced zero bytes at the receiver before this fix.
        var packet1 = MIDIPacket();
        packet1.timeStamp = 0;
        packet1.data.0 = channelVoiceMessages.controlChange | (UInt8(channel) - 1) //(0x90 + (channel-1))
        packet1.data.1 = cc
        if let value {
            packet1.length = 3
            packet1.data.2 = value
        } else {
            packet1.length = 2
        }

        //Add packet to packet list and send it to destNum
        var packetList = MIDIPacketList(numPackets: 1, packet: packet1);
        if !midiDestinations.isEmpty {MIDISend(outPort, midiDestinations[destNum].midiEndpoint, &packetList);}
    }
}
