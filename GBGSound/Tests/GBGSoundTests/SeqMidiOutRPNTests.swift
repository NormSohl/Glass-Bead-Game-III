import XCTest
import CoreMIDI
@testable import GBGSound

/// Byte-level check of SeqMidiOut's RPN 0 send through real CoreMIDI: a virtual destination
/// collects whatever arrives, the same monitor approach used for this project's other MIDI work.
final class SeqMidiOutRPNTests: XCTestCase {
    func testPitchBendSensitivityBytes() throws {
        let name = "SeqRPNTest-\(UUID().uuidString.prefix(8))"
        var client: MIDIClientRef = 0
        XCTAssertEqual(MIDIClientCreate("SeqRPNTestClient" as CFString, nil, nil, &client), noErr)
        defer { MIDIClientDispose(client) }

        let lock = NSLock()
        var received: [UInt8] = []
        let gotAll = expectation(description: "all RPN bytes received")
        var destination: MIDIEndpointRef = 0
        let status = MIDIDestinationCreateWithProtocol(client, name as CFString, ._1_0, &destination) { eventList, _ in
            // Unpack MIDI 1.0 channel voice UMPs (type 2) back into 3-byte messages.
            for packet in eventList.unsafeSequence() {
                let words = withUnsafeBytes(of: packet.pointee.words) { Array($0.bindMemory(to: UInt32.self).prefix(Int(packet.pointee.wordCount))) }
                for word in words where word >> 28 == 0x2 {
                    lock.lock()
                    received += [UInt8((word >> 16) & 0xFF), UInt8((word >> 8) & 0xFF), UInt8(word & 0xFF)]
                    let done = received.count >= 18
                    lock.unlock()
                    if done { gotAll.fulfill() }
                }
            }
        }
        XCTAssertEqual(status, noErr)
        defer { MIDIEndpointDispose(destination) }

        let out = SeqMidiOut()
        out.initMidi()
        let index = try XCTUnwrap(out.midiDestinations.firstIndex { $0.name == name })
        out.setMidiDestination(destination: index)

        out.pitchBendSensitivity(channel: 3, semitones: 48)

        wait(for: [gotAll], timeout: 2)
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(received, [
            0xB2, 101, 0, 0xB2, 100, 0,     // select RPN 0 on channel 3
            0xB2, 6, 48, 0xB2, 38, 0,       // ±48 semitones, 0 cents
            0xB2, 101, 127, 0xB2, 100, 127, // RPN null
        ])
    }
}
