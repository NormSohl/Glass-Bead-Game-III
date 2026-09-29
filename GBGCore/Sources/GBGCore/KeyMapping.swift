//
//  KeyMapping.swift
//  GBGCore
//
//  User-remappable bindings for the keyboard-controllable actions (Drone/Portamento toggle/
//  Portamento hold/Pedal hold) - see KeyCommandMonitor/KeyboardMonitor/MouseMonitor
//  in the app target's ContentView.swift, which read this instead of hardcoded key checks.
//  Persisted via UserDefaults (unlike the rest of AppSettings, which is deliberately
//  in-memory-only and resets every launch - a performer's own keyboard remap is a real,
//  deliberate customization worth keeping, not an ephemeral session toggle like Drone/Pedal/
//  Portamento themselves).
//
//  Lives in GBGCore (moved from the app target 2026-09-05) rather than the app itself so it -
//  and KeyActionDispatcher.swift alongside it - can be exercised by GBGCoreTests via a plain
//  `swift test`, without needing a live keyboard/mouse/pencil or a UI test target at all. Norm:
//  "add automated test harnesses... to confirm we don't lose functionality moving forward."
//  This file has zero dependency on the app's AppSettings class to begin with,
//  so it moved over unchanged apart from `public` visibility.
//

import Foundation

public enum KeyAction: String, CaseIterable, Codable {
    case drone, portamentoToggle, portamentoMomentary, pedal

    public var displayName: String {
        switch self {
        case .drone: return "Drone"
        case .portamentoToggle: return "Portamento (toggle)"
        case .portamentoMomentary: return "Portamento (hold)"
        case .pedal: return "Pedal (hold)"
        }
    }

    // Momentary actions care about release (settings flips back on keyUp/modifier-released);
    // toggle actions fire once per press and never care about release at all.
    public var isMomentary: Bool {
        self == .portamentoMomentary || self == .pedal
    }
}

// Plain String tokens rather than a wrapper enum - a regular character key is its own single-
// character lowercase token ("f", " " for space); the four modifier keys use their full name
// ("shift"/"option"/"control"/"command") instead, which can never collide with a single-
// character token, so nothing else is needed to tell the two kinds apart. Mouse button tokens
// follow the same convention - multi-character names that can't collide with a single letter.
// "mouseLeft"/"mouseMiddle" are iOS-only (see MouseMonitor in ContentView.swift - macOS's mouse
// is already spoken for by HitTestView's graph drag). "mouseRight" is the one exception: it's
// unused by graph drag on either platform, so it's live on both - MouseMonitor on iOS,
// KeyCommandMonitor's right-mouse-button case on macOS.
public typealias KeyToken = String
public let modifierKeyTokens: Set<KeyToken> = ["shift", "option", "control", "command"]
public let mouseButtonTokens: Set<KeyToken> = ["mouseLeft", "mouseRight", "mouseMiddle"]

public func displayLabel(forKeyToken token: KeyToken) -> String {
    switch token {
    case " ": return "Space"
    case "shift": return "Shift"
    case "option": return "Option"
    case "control": return "Control"
    case "command": return "Command"
    case "mouseLeft": return "Mouse Left"
    case "mouseRight": return "Mouse Right"
    case "mouseMiddle": return "Mouse Middle"
    default: return token.uppercased()
    }
}

public struct KeyMapping: Codable, Equatable {
    // KeyAction.rawValue -> the set of tokens bound to it. A dictionary keyed by the enum
    // itself would also work, but String keys keep the persisted JSON legible if anyone ever
    // has to look at defaults(1) output while debugging.
    public var bindings: [String: Set<KeyToken>]

    public init(bindings: [String: Set<KeyToken>]) {
        self.bindings = bindings
    }

    // mouseLeft/mouseRight defaults are here specifically for Norm's back-of-case mouse
    // controller idea (squeeze doesn't fire reliably while the pencil is touching the graph -
    // see the memory notes) - immediately testable without a trip to Keyboard Mapping first,
    // same reasoning as every other default here.
    public static let defaultMapping = KeyMapping(bindings: [
        KeyAction.drone.rawValue: ["d", "k"],
        KeyAction.portamentoToggle.rawValue: ["g", "h"],
        KeyAction.portamentoMomentary.rawValue: ["shift", "mouseRight"],
        KeyAction.pedal.rawValue: [" ", "f", "j", "mouseLeft"],
    ])

    public func tokens(for action: KeyAction) -> Set<KeyToken> {
        bindings[action.rawValue] ?? []
    }

    // Which action (if any) currently owns this token - the live key monitor's own lookup, and
    // also what the remap UI uses to find (and evict) wherever a token used to live before
    // binding it somewhere new.
    public func action(for token: KeyToken) -> KeyAction? {
        for action in KeyAction.allCases where bindings[action.rawValue]?.contains(token) == true {
            return action
        }
        return nil
    }

    // Moves `token` to `action`, removing it from whatever action (if any) already had it -
    // a token can only ever mean one thing at a time, so rebinding it is always a move, never
    // an additional simultaneous binding.
    public mutating func bind(_ token: KeyToken, to action: KeyAction) {
        for key in bindings.keys {
            bindings[key]?.remove(token)
        }
        bindings[action.rawValue, default: []].insert(token)
    }

    public mutating func unbind(_ token: KeyToken, from action: KeyAction) {
        bindings[action.rawValue]?.remove(token)
    }
}

extension KeyMapping {
    private static let userDefaultsKey = "GlassBeadGameIII.keyMapping"

    public static func loadFromDefaults() -> KeyMapping {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(KeyMapping.self, from: data) else {
            return .defaultMapping
        }
        return decoded.droppingRemovedActions().mergingNewDefaults()
    }

    /// Drops entries for actions that no longer exist (Live Recording's recordToggle/save,
    /// removed 2026-09-28) - otherwise their tokens stay parked under a dead key, invisible in
    /// the remap UI but still blocking mergingNewDefaults from ever reusing them.
    private func droppingRemovedActions() -> KeyMapping {
        let known = Set(KeyAction.allCases.map(\.rawValue))
        return KeyMapping(bindings: bindings.filter { known.contains($0.key) })
    }

    /// Fills in an action's own default token(s) only when a saved mapping predates that action
    /// entirely (no entry at all, not even an empty one) - lets a KeyAction added after someone
    /// already has a customized, persisted mapping reach them with its default key(s) instead of
    /// silently having none bound until they notice and rebind it by hand. Never touches an
    /// action already present in the saved mapping (including one deliberately emptied out), and
    /// never assigns a default token already bound to something else in the saved mapping - that
    /// would change an existing binding's behavior, which adding an unrelated new action should
    /// never do.
    private func mergingNewDefaults() -> KeyMapping {
        var merged = self
        for action in KeyAction.allCases where bindings[action.rawValue] == nil {
            let defaults = KeyMapping.defaultMapping.tokens(for: action).filter { merged.action(for: $0) == nil }
            if !defaults.isEmpty {
                merged.bindings[action.rawValue] = defaults
            }
        }
        return merged
    }

    public func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
