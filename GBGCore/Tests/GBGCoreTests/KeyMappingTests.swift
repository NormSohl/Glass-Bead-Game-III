import XCTest
@testable import GBGCore

final class KeyMappingTests: XCTestCase {
    private let defaultsKey = "GlassBeadGameIII.keyMapping"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        super.tearDown()
    }

    func testDefaultMappingBindsExpectedActions() {
        let mapping = KeyMapping.defaultMapping
        XCTAssertEqual(mapping.tokens(for: .pedal), [" ", "f", "j"])
        XCTAssertEqual(mapping.tokens(for: .portamentoMomentary), ["shift", "mouseRight"])
        XCTAssertEqual(mapping.tokens(for: .drone), ["d", "k"])
        XCTAssertEqual(mapping.tokens(for: .portamentoToggle), ["g", "h"])
    }

    func testActionForReturnsOwningActionOrNil() {
        let mapping = KeyMapping.defaultMapping
        XCTAssertEqual(mapping.action(for: "d"), .drone)
        XCTAssertEqual(mapping.action(for: "mouseRight"), .portamentoMomentary)
        XCTAssertNil(mapping.action(for: "mouseLeft"))
        XCTAssertNil(mapping.action(for: "q"))
    }

    func testBindMovesTokenAwayFromWhicheverActionAlreadyHadIt() {
        var mapping = KeyMapping.defaultMapping
        XCTAssertEqual(mapping.action(for: "d"), .drone)
        mapping.bind("d", to: .pedal)
        XCTAssertEqual(mapping.action(for: "d"), .pedal)
        XCTAssertFalse(mapping.tokens(for: .drone).contains("d"))
    }

    func testUnbindRemovesOnlyTheGivenTokenFromTheGivenAction() {
        var mapping = KeyMapping.defaultMapping
        mapping.unbind("d", from: .drone)
        XCTAssertNil(mapping.action(for: "d"))
        XCTAssertEqual(mapping.tokens(for: .drone), ["k"])
    }

    // Guards the momentary/toggle split that KeyActionDispatcher's applyKeyUp/applyKeyDown
    // branch on - a regression here would silently change which actions respond to key release.
    func testIsMomentaryOnlyForPedalAndPortamentoMomentary() {
        for action in KeyAction.allCases {
            let expected = action == .pedal || action == .portamentoMomentary
            XCTAssertEqual(action.isMomentary, expected, "\(action) momentary flag regressed")
        }
    }

    func testLoadFromDefaultsFallsBackToDefaultMappingWhenNothingSaved() {
        XCTAssertEqual(KeyMapping.loadFromDefaults(), .defaultMapping)
    }

    func testSaveAndLoadRoundTripsACustomBinding() {
        var mapping = KeyMapping.defaultMapping
        mapping.bind("z", to: .drone)
        mapping.saveToDefaults()
        XCTAssertEqual(KeyMapping.loadFromDefaults().action(for: "z"), .drone)
    }

    // Exercises mergingNewDefaults (private, reached only through loadFromDefaults) via the real
    // Codable/UserDefaults round trip - simulates a mapping saved before an action existed (no
    // entry at all for it, not even an empty one). .drone stands in for "the newer action."
    func testLoadFromDefaultsFillsInAnActionMissingFromAnOlderSavedMapping() {
        var bindings = KeyMapping.defaultMapping.bindings
        bindings.removeValue(forKey: KeyAction.drone.rawValue)
        storeLegacy(bindings)

        let reloaded = KeyMapping.loadFromDefaults()
        XCTAssertEqual(reloaded.tokens(for: .drone), KeyMapping.defaultMapping.tokens(for: .drone))
        XCTAssertEqual(reloaded.tokens(for: .pedal), KeyMapping.defaultMapping.tokens(for: .pedal))
    }

    // If an older saved mapping had already reassigned one of the missing action's default
    // tokens ("d") to a different action, filling in the default on load must not steal it back.
    func testLoadFromDefaultsNeverStealsADefaultTokenAlreadyUsedElsewhereInTheSavedMapping() {
        var bindings = KeyMapping.defaultMapping.bindings
        bindings.removeValue(forKey: KeyAction.drone.rawValue)
        bindings[KeyAction.pedal.rawValue, default: []].insert("d")
        storeLegacy(bindings)

        let reloaded = KeyMapping.loadFromDefaults()
        XCTAssertEqual(reloaded.tokens(for: .drone), ["k"])
        XCTAssertEqual(reloaded.action(for: "d"), .pedal)
    }

    // A mapping saved while Live Recording existed still carries "recordToggle"/"save" entries -
    // those must be dropped on load so their keys (R/S) aren't left parked under a dead action.
    func testLoadFromDefaultsDropsEntriesForRemovedActions() {
        var bindings = KeyMapping.defaultMapping.bindings
        bindings["recordToggle"] = ["r"]
        bindings["save"] = ["s"]
        storeLegacy(bindings)

        let reloaded = KeyMapping.loadFromDefaults()
        XCTAssertEqual(reloaded, .defaultMapping)
        XCTAssertNil(reloaded.action(for: "r"))
    }

    // A mapping saved before the left mouse button became the pointer on iPad (2026-09-28) still
    // binds "mouseLeft" to Pedal - that token must be dropped, leaving Pedal's other keys intact.
    func testLoadFromDefaultsDropsTheRetiredMouseLeftToken() {
        var bindings = KeyMapping.defaultMapping.bindings
        bindings[KeyAction.pedal.rawValue, default: []].insert("mouseLeft")
        storeLegacy(bindings)

        let reloaded = KeyMapping.loadFromDefaults()
        XCTAssertNil(reloaded.action(for: "mouseLeft"))
        XCTAssertEqual(reloaded.tokens(for: .pedal), [" ", "f", "j"])
    }

    private func storeLegacy(_ bindings: [String: Set<KeyToken>]) {
        guard let data = try? JSONEncoder().encode(KeyMapping(bindings: bindings)) else {
            return XCTFail("failed to encode legacy mapping")
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    func testDisplayLabelNamesForNonCharacterTokens() {
        XCTAssertEqual(displayLabel(forKeyToken: " "), "Space")
        XCTAssertEqual(displayLabel(forKeyToken: "shift"), "Shift")
        XCTAssertEqual(displayLabel(forKeyToken: "mouseRight"), "Mouse Right")
        XCTAssertEqual(displayLabel(forKeyToken: "mouseMiddle"), "Mouse Middle")
        XCTAssertEqual(displayLabel(forKeyToken: "d"), "D")
    }
}
