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
