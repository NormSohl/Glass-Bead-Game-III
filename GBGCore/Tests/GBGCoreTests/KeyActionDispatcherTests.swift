import XCTest
@testable import GBGCore

// Minimal stand-in for the app target's AppSettings - conforming to exactly the protocol
// KeyActionDispatcher actually depends on, the same way the real class does via its own
// `extension AppSettings: KeyActionPerforming {}` (ControlData.swift).
private final class MockSettings: KeyActionPerforming {
    var pedal = false
    var snap = true
    var playDrone = false
    var keyMapping = KeyMapping.defaultMapping
    var pendingKeyBindingAction: KeyAction?
    var isCapturingKeyBinding = false
}

final class KeyActionDispatcherTests: XCTestCase {
    private var settings: MockSettings!
    private var dispatcher: KeyActionDispatcher!

    override func setUp() {
        super.setUp()
        settings = MockSettings()
        dispatcher = KeyActionDispatcher(settings: settings)
    }

    func testPedalKeyDownAndKeyUp() {
        dispatcher.applyKeyDown(.pedal, isARepeat: false)
        XCTAssertTrue(settings.pedal)
        dispatcher.applyKeyUp(.pedal)
        XCTAssertFalse(settings.pedal)
    }

    func testDroneTogglesOnKeyDownOnlyWhenNotARepeat() {
        dispatcher.applyKeyDown(.drone, isARepeat: false)
        XCTAssertTrue(settings.playDrone)
        dispatcher.applyKeyDown(.drone, isARepeat: true)
        // a held key's repeat events shouldn't flip a toggle action again
        XCTAssertTrue(settings.playDrone)
        dispatcher.applyKeyDown(.drone, isARepeat: false)
        XCTAssertFalse(settings.playDrone)
    }

    func testPortamentoToggleFlipsSnapOnKeyDownOnly() {
        XCTAssertTrue(settings.snap)
        dispatcher.applyKeyDown(.portamentoToggle, isARepeat: false)
        XCTAssertFalse(settings.snap)
        dispatcher.applyKeyUp(.portamentoToggle)
        // toggle actions don't care about release at all
        XCTAssertFalse(settings.snap)
    }

    func testPortamentoMomentaryOverridesThenRestoresWhateverSnapWasBefore() {
        settings.snap = true
        dispatcher.applyKeyDown(.portamentoMomentary, isARepeat: false)
        XCTAssertFalse(settings.snap)
        dispatcher.applyKeyUp(.portamentoMomentary)
        XCTAssertTrue(settings.snap)

        // If Portamento was already toggled on (snap == false) before the momentary press,
        // releasing must restore that - not force it back to true.
        settings.snap = false
        dispatcher.applyKeyDown(.portamentoMomentary, isARepeat: false)
        XCTAssertFalse(settings.snap)
        dispatcher.applyKeyUp(.portamentoMomentary)
        XCTAssertFalse(settings.snap)
    }

    // Two tokens bound to portamentoMomentary (e.g. Shift and a mouse button) both held at
    // once: the second press must not overwrite the already-saved "restore to" value, and a
    // spurious extra release must not misbehave once the real one already cleared it.
    func testPortamentoMomentaryIgnoresANestedPressWhileAlreadyHeld() {
        settings.snap = true
        dispatcher.applyKeyDown(.portamentoMomentary, isARepeat: false) // first token pressed
        settings.snap = false // simulate something else changing snap while held, as a probe
        dispatcher.applyKeyDown(.portamentoMomentary, isARepeat: false) // second token pressed
        dispatcher.applyKeyUp(.portamentoMomentary) // one release
        // Restores to the value captured at the FIRST press (true), not re-captured mid-hold.
        XCTAssertTrue(settings.snap)

        settings.snap = false
        dispatcher.applyKeyUp(.portamentoMomentary) // a redundant extra release - must no-op
        XCTAssertFalse(settings.snap)
    }

    // The exact path every physical input - keyboard, and a mouse button bound the same way
    // (see KeyMapping's mouseLeft/mouseRight/mouseMiddle tokens) - goes through. Mouse buttons
    // aren't a separate code path from keyboard keys; they're just another KeyToken string,
    // so this one test covers both.
    func testHandlePhysicalInputDispatchesTheBoundActionRegardlessOfTokenKind() {
        dispatcher.handlePhysicalInput(token: "mouseLeft", pressed: true) // default: Pedal
        XCTAssertTrue(settings.pedal)
        dispatcher.handlePhysicalInput(token: "mouseLeft", pressed: false)
        XCTAssertFalse(settings.pedal)

        dispatcher.handlePhysicalInput(token: "d", pressed: true) // default: Drone (toggle)
        XCTAssertTrue(settings.playDrone)
    }

    func testHandlePhysicalInputIgnoresATokenBoundToNothing() {
        dispatcher.handlePhysicalInput(token: "q", pressed: true)
        XCTAssertFalse(settings.pedal)
        XCTAssertFalse(settings.playDrone)
    }

    func testHandlePhysicalInputOnlyAppliesReleaseForMomentaryActions() {
        // "d" is bound to Drone, a toggle - a release event for it must not un-toggle anything
        // (drone has no release behavior at all).
        dispatcher.handlePhysicalInput(token: "d", pressed: true)
        XCTAssertTrue(settings.playDrone)
        dispatcher.handlePhysicalInput(token: "d", pressed: false)
        XCTAssertTrue(settings.playDrone) // unchanged by the release
    }

    func testHandlePhysicalInputIsSuppressedWhileCapturingANewBinding() {
        settings.isCapturingKeyBinding = true
        dispatcher.handlePhysicalInput(token: "mouseLeft", pressed: true)
        XCTAssertFalse(settings.pedal) // the live monitor must stand down during capture
    }

    // KeyMappingView's "+" button flow (settings.pendingKeyBindingAction) - the next physical
    // input of any kind completes the binding instead of being dispatched as an action.
    func testHandlePhysicalInputCompletesAPendingBindingCaptureInsteadOfDispatching() {
        settings.pendingKeyBindingAction = .drone
        dispatcher.handlePhysicalInput(token: "x", pressed: true)

        XCTAssertEqual(settings.keyMapping.action(for: "x"), .drone)
        XCTAssertNil(settings.pendingKeyBindingAction)
        XCTAssertFalse(settings.isCapturingKeyBinding)
        XCTAssertFalse(settings.playDrone) // the capturing keypress itself must not also fire the action
    }
}
