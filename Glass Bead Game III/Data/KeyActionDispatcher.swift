//
//  KeyActionDispatcher.swift
//  Glass Bead Game III
//
//  Platform-independent bridge from a recognized KeyAction to actual settings changes -
//  shared by macOS's NSEvent-driven KeyCommandMonitor (ContentView.swift) and iOS's
//  GameController-driven KeyboardMonitor, so the momentary-Portamento restore behavior
//  can't drift between the two event sources.
//

import Foundation

final class KeyActionDispatcher {
    var settings: AppSettings

    // portamentoMomentary's own "before" value - settings.snap right before some token bound
    // to it was pressed, nil whenever nothing bound to it is currently held. Restored on
    // release rather than just forcing snap back to true, so a portamentoToggle press that
    // already happened before this press survives it. See ContentView's original
    // KeyCommandMonitor for the fuller history of this behavior.
    private var snapBeforeMomentaryPortamento: Bool?

    init(settings: AppSettings) {
        self.settings = settings
    }

    // Momentary actions get pressed; toggle actions get toggled - except portamentoMomentary,
    // whose "press" temporarily overrides the toggle-backed settings.snap rather than just
    // setting a boolean, so it can restore whatever value was there before once released.
    func applyKeyDown(_ action: KeyAction, isARepeat: Bool) {
        switch action {
        case .pedal:
            settings.pedal = true
        case .portamentoMomentary:
            guard snapBeforeMomentaryPortamento == nil else { return }
            snapBeforeMomentaryPortamento = settings.snap
            settings.snap = false
        case .drone:
            if !isARepeat { settings.playDrone.toggle() }
        case .portamentoToggle:
            if !isARepeat { settings.snap.toggle() }
        }
    }

    func applyKeyUp(_ action: KeyAction) {
        switch action {
        case .pedal:
            settings.pedal = false
        case .portamentoMomentary:
            if let previous = snapBeforeMomentaryPortamento {
                settings.snap = previous
                snapBeforeMomentaryPortamento = nil
            }
        case .drone, .portamentoToggle:
            break // discrete toggles don't care about release
        }
    }
}
