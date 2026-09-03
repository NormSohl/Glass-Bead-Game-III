//
//  KeyMapping.swift
//  Glass Bead Game III
//
//  User-remappable bindings for the four keyboard-controllable actions (Drone/Portamento
//  toggle/Portamento hold/Pedal hold) - see KeyCommandMonitor in ContentView.swift, which reads
//  this instead of the hardcoded key checks it used to have. Persisted via UserDefaults (unlike
//  the rest of AppSettings, which is deliberately in-memory-only and resets every launch - a
//  performer's own keyboard remap is a real, deliberate customization worth keeping, not an
//  ephemeral session toggle like Drone/Pedal/Portamento themselves).
//

import Foundation

enum KeyAction: String, CaseIterable, Codable {
    case drone, portamentoToggle, portamentoMomentary, pedal, recordToggle, save

    var displayName: String {
        switch self {
        case .drone: return "Drone"
        case .portamentoToggle: return "Portamento (toggle)"
        case .portamentoMomentary: return "Portamento (hold)"
        case .pedal: return "Pedal (hold)"
        case .recordToggle: return "Live Recording (start/stop)"
        case .save: return "Save Live Recording"
        }
    }

    // Momentary actions care about release (settings flips back on keyUp/modifier-released);
    // toggle actions fire once per press and never care about release at all.
    var isMomentary: Bool {
        self == .portamentoMomentary || self == .pedal
    }
}

// Plain String tokens rather than a wrapper enum - a regular character key is its own single-
// character lowercase token ("f", " " for space); the four modifier keys use their full name
// ("shift"/"option"/"control"/"command") instead, which can never collide with a single-
// character token, so nothing else is needed to tell the two kinds apart.
typealias KeyToken = String
let modifierKeyTokens: Set<KeyToken> = ["shift", "option", "control", "command"]

func displayLabel(forKeyToken token: KeyToken) -> String {
    switch token {
    case " ": return "Space"
    case "shift": return "Shift"
    case "option": return "Option"
    case "control": return "Control"
    case "command": return "Command"
    default: return token.uppercased()
    }
}

struct KeyMapping: Codable, Equatable {
    // KeyAction.rawValue -> the set of tokens bound to it. A dictionary keyed by the enum
    // itself would also work, but String keys keep the persisted JSON legible if anyone ever
    // has to look at defaults(1) output while debugging.
    var bindings: [String: Set<KeyToken>]

    static let defaultMapping = KeyMapping(bindings: [
        KeyAction.drone.rawValue: ["d", "k"],
        KeyAction.portamentoToggle.rawValue: ["g", "h"],
        KeyAction.portamentoMomentary.rawValue: ["shift"],
        KeyAction.pedal.rawValue: [" ", "f", "j"],
        KeyAction.recordToggle.rawValue: ["r"],
        KeyAction.save.rawValue: ["s"],
    ])

    func tokens(for action: KeyAction) -> Set<KeyToken> {
        bindings[action.rawValue] ?? []
    }

    // Which action (if any) currently owns this token - the live key monitor's own lookup, and
    // also what the remap UI uses to find (and evict) wherever a token used to live before
    // binding it somewhere new.
    func action(for token: KeyToken) -> KeyAction? {
        for action in KeyAction.allCases where bindings[action.rawValue]?.contains(token) == true {
            return action
        }
        return nil
    }

    // Moves `token` to `action`, removing it from whatever action (if any) already had it -
    // a token can only ever mean one thing at a time, so rebinding it is always a move, never
    // an additional simultaneous binding.
    mutating func bind(_ token: KeyToken, to action: KeyAction) {
        for key in bindings.keys {
            bindings[key]?.remove(token)
        }
        bindings[action.rawValue, default: []].insert(token)
    }

    mutating func unbind(_ token: KeyToken, from action: KeyAction) {
        bindings[action.rawValue]?.remove(token)
    }
}

extension KeyMapping {
    private static let userDefaultsKey = "GlassBeadGameIII.keyMapping"

    static func loadFromDefaults() -> KeyMapping {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(KeyMapping.self, from: data) else {
            return .defaultMapping
        }
        return decoded.mergingNewDefaults()
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

    func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
