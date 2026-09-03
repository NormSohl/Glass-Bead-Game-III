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
    // Live-recording start/stop and save also go through here (recordToggle/save below) - same
    // single dispatch point Drone/Portamento/Pedal already use, so a physical/Bluetooth keyboard
    // (or a cheap footswitch/keypad emulating one) can drive recording exactly like it drives
    // everything else, remappable through the same Keyboard Mapping UI.
    var recordingState: RecordingState

    // portamentoMomentary's own "before" value - settings.snap right before some token bound
    // to it was pressed, nil whenever nothing bound to it is currently held. Restored on
    // release rather than just forcing snap back to true, so a portamentoToggle press that
    // already happened before this press survives it. See ContentView's original
    // KeyCommandMonitor for the fuller history of this behavior.
    private var snapBeforeMomentaryPortamento: Bool?

    init(settings: AppSettings, recordingState: RecordingState) {
        self.settings = settings
        self.recordingState = recordingState
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
        case .recordToggle:
            if !isARepeat { recordingState.toggleRecording() }
        case .save:
            if !isARepeat { recordingState.requestSave() }
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
        case .drone, .portamentoToggle, .recordToggle, .save:
            break // discrete toggles/triggers don't care about release
        }
    }
}
