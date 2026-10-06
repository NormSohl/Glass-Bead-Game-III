import XCTest
import CoreMIDI
@testable import GBGSound

/// Real-CoreMIDI checks that SeqMidiOut notices endpoints appearing/disappearing after launch
/// (Graph started after Seq) and keeps its chosen destination by endpoint, not list index.
final class SeqMidiOutSetupChangeTests: XCTestCase {
    private var client: MIDIClientRef = 0

    override func setUp() {
        MIDIClientCreate("SetupChangeTestClient" as CFString, nil, nil, &client)
    }

    override func tearDown() {
        MIDIClientDispose(client)
    }

    private func makeDestination(_ name: String) -> MIDIEndpointRef {
        var endpoint: MIDIEndpointRef = 0
        MIDIDestinationCreateWithProtocol(client, name as CFString, ._1_0, &endpoint) { _, _ in }
        return endpoint
    }

    func testDestinationCreatedLaterIsNoticedAndFound() {
        let out = SeqMidiOut()
        out.initMidi()
        let name = "LateDest-\(UUID().uuidString.prefix(8))"
        XCTAssertFalse(out.midiDestinations.contains { $0.name == name })

        let changed = expectation(description: "setup change reported")
        changed.assertForOverFulfill = false
        out.onSetupChanged = {
            out.refreshMidiDestinations()
            if out.midiDestinations.contains(where: { $0.name == name }) { changed.fulfill() }
        }
        let endpoint = makeDestination(name)
        defer { MIDIEndpointDispose(endpoint) }
        wait(for: [changed], timeout: 3)
    }

    func testSelectionFollowsEndpointAndClearsWhenRemoved() {
        let first = makeDestination("SelA-\(UUID().uuidString.prefix(8))")
        let secondName = "SelB-\(UUID().uuidString.prefix(8))"
        let second = makeDestination(secondName)
        defer { MIDIEndpointDispose(second) }

        let out = SeqMidiOut()
        out.initMidi()
        let index = out.midiDestinations.firstIndex { $0.name == secondName }!
        out.setMidiDestination(destination: index)

        // Removing an endpoint listed before it shifts indices; the choice must still be B.
        MIDIEndpointDispose(first)
        XCTAssertTrue(out.refreshMidiDestinations())
        XCTAssertEqual(out.midiDestinations[out.selectedDestinationIndex!].name, secondName)

        // Removing the chosen endpoint itself clears the choice.
        MIDIEndpointDispose(second)
        XCTAssertFalse(out.refreshMidiDestinations())
        XCTAssertNil(out.selectedDestinationIndex)
    }
}

final class SeqMidiOutSourceTests: XCTestCase {
    private var client: MIDIClientRef = 0

    override func setUp() { MIDIClientCreate("SourceTestClient" as CFString, nil, nil, &client) }
    override func tearDown() { MIDIClientDispose(client) }

    private func makeSource(_ name: String) -> MIDIEndpointRef {
        var endpoint: MIDIEndpointRef = 0
        MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &endpoint)
        return endpoint
    }

    private func sendNoteOn(from source: MIDIEndpointRef, channel: UInt8) {
        var packet = MIDIPacket()
        packet.length = 3
        packet.data.0 = 0x90 | (channel - 1); packet.data.1 = 60; packet.data.2 = 100
        var list = MIDIPacketList(numPackets: 1, packet: packet)
        MIDIReceived(source, &list)
    }

    private func expectEvent(_ out: SeqMidiOut, from source: MIDIEndpointRef, _ description: String) {
        let got = expectation(description: description)
        got.assertForOverFulfill = false
        out.onEvent = { event in if event.channel == 3 { got.fulfill() } }
        sendNoteOn(from: source, channel: 3)
        wait(for: [got], timeout: 2)
    }

    func testSourceConnectsAndReconnectsByName() {
        let name = "CapSrc-\(UUID().uuidString.prefix(8))"
        let first = makeSource(name)

        let out = SeqMidiOut()
        out.initMidi()
        out.initMidiInput(name: "CapTest-\(UUID().uuidString.prefix(8))")
        XCTAssertNotNil(out.connectedSourceIndex, "something is connected from the start")
        let index = out.midiSources.firstIndex { $0.name == name }!
        out.setMidiSource(source: index)
        XCTAssertEqual(out.connectedSourceIndex, index)
        expectEvent(out, from: first, "event from the chosen source")

        // The source goes away and comes back as a new endpoint with the same name.
        MIDIEndpointDispose(first)
        let second = makeSource(name)
        defer { MIDIEndpointDispose(second) }
        out.refreshMidiSources()
        XCTAssertEqual(out.midiSources[out.connectedSourceIndex!].name, name)
        expectEvent(out, from: second, "event after reconnecting by name")
    }
}
