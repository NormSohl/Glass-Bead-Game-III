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
        XCTAssertEqual(mapping.tokens(for: .pedal), [" ", "f", "j", "mouseLeft"])
        XCTAssertEqual(mapping.tokens(for: .portamentoMomentary), ["shift", "mouseRight"])
        XCTAssertEqual(mapping.tokens(for: .drone), ["d", "k"])
        XCTAssertEqual(mapping.tokens(for: .portamentoToggle), ["g", "h"])
        XCTAssertEqual(mapping.tokens(for: .recordToggle), ["r"])
        XCTAssertEqual(mapping.tokens(for: .save), ["s"])
    }

    func testActionForReturnsOwningActionOrNil() {
        let mapping = KeyMapping.defaultMapping
        XCTAssertEqual(mapping.action(for: "d"), .drone)
        XCTAssertEqual(mapping.action(for: "mouseLeft"), .pedal)
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
    // Codable/UserDefaults round trip - simulates a mapping saved before `.save` existed (no
    // entry at all for it, not even an empty one).
    func testLoadFromDefaultsFillsInAnActionMissingFromAnOlderSavedMapping() {
        var bindings = KeyMapping.defaultMapping.bindings
        bindings.removeValue(forKey: KeyAction.save.rawValue)
        let legacyMapping = KeyMapping(bindings: bindings)
        guard let data = try? JSONEncoder().encode(legacyMapping) else {
            return XCTFail("failed to encode legacy mapping")
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)

        let reloaded = KeyMapping.loadFromDefaults()
        XCTAssertEqual(reloaded.tokens(for: .save), KeyMapping.defaultMapping.tokens(for: .save))
        XCTAssertEqual(reloaded.tokens(for: .drone), KeyMapping.defaultMapping.tokens(for: .drone))
    }

    // If an older saved mapping had already reassigned .save's own default token ("s") to a
    // different action, filling in .save's default on load must not steal it back.
    func testLoadFromDefaultsNeverStealsADefaultTokenAlreadyUsedElsewhereInTheSavedMapping() {
        var bindings = KeyMapping.defaultMapping.bindings
        bindings.removeValue(forKey: KeyAction.save.rawValue)
        bindings[KeyAction.drone.rawValue, default: []].insert("s")
        let legacyMapping = KeyMapping(bindings: bindings)
        guard let data = try? JSONEncoder().encode(legacyMapping) else {
            return XCTFail("failed to encode legacy mapping")
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)

        let reloaded = KeyMapping.loadFromDefaults()
        XCTAssertTrue(reloaded.tokens(for: .save).isEmpty)
        XCTAssertEqual(reloaded.action(for: "s"), .drone)
    }

    func testDisplayLabelNamesForNonCharacterTokens() {
        XCTAssertEqual(displayLabel(forKeyToken: " "), "Space")
        XCTAssertEqual(displayLabel(forKeyToken: "shift"), "Shift")
        XCTAssertEqual(displayLabel(forKeyToken: "mouseLeft"), "Mouse Left")
        XCTAssertEqual(displayLabel(forKeyToken: "mouseRight"), "Mouse Right")
        XCTAssertEqual(displayLabel(forKeyToken: "mouseMiddle"), "Mouse Middle")
        XCTAssertEqual(displayLabel(forKeyToken: "d"), "D")
    }
}
