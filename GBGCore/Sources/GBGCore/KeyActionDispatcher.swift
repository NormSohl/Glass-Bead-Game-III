//
//  KeyActionDispatcher.swift
//  GBGCore
//
//  Platform-independent bridge from a recognized KeyAction to actual settings changes -
//  shared by macOS's NSEvent-driven KeyCommandMonitor, iOS's GameController-driven
//  KeyboardMonitor, and iOS's GCMouse-driven MouseMonitor (all in the app target's
//  ContentView.swift), so the momentary-Portamento restore behavior can't drift between
//  input sources.
//
//  Lives in GBGCore (moved from the app target 2026-09-05), same reasoning as KeyMapping.swift
//  alongside it - testable via `swift test` with no live hardware. Unlike KeyMapping, this DID
//  depend directly on the app target's own AppSettings/RecordingState classes, so moving it
//  needed the two small protocols below instead - AppSettings/RecordingState now conform to
//  them via a plain extension in the app target (ControlData.swift/RecordingState.swift), with
//  no change to either class itself.
//

import Foundation

/// The subset of the app target's AppSettings that KeyActionDispatcher actually reads and
/// writes - lets this dispatch logic live here in GBGCore, fully unaware of AppSettings itself
/// or the SwiftUI/ObservableObject machinery around it. AppSettings conforms via a plain
/// `extension AppSettings: KeyActionPerforming {}` (ControlData.swift) - no other change to
/// that class was needed, since it already had every one of these properties.
public protocol KeyActionPerforming: AnyObject {
    var pedal: Bool { get set }
    var snap: Bool { get set }
    var playDrone: Bool { get set }
    var keyMapping: KeyMapping { get set }
    var pendingKeyBindingAction: KeyAction? { get set }
    var isCapturingKeyBinding: Bool { get set }
}

/// The subset of the app target's RecordingState KeyActionDispatcher needs - see
/// KeyActionPerforming's own comment for why this exists. RecordingState conforms via a plain
/// `extension RecordingState: RecordingActionPerforming {}` (RecordingState.swift).
public protocol RecordingActionPerforming: AnyObject {
    func toggleRecording()
    func requestSave()
}

public final class KeyActionDispatcher {
    public var settings: any KeyActionPerforming
    // Live-recording start/stop and save also go through here (recordToggle/save below) - same
    // single dispatch point Drone/Portamento/Pedal already use, so a physical/Bluetooth keyboard
    // (or a cheap footswitch/keypad emulating one) can drive recording exactly like it drives
    // everything else, remappable through the same Keyboard Mapping UI.
    public var recordingState: any RecordingActionPerforming

    // portamentoMomentary's own "before" value - settings.snap right before some token bound
    // to it was pressed, nil whenever nothing bound to it is currently held. Restored on
    // release rather than just forcing snap back to true, so a portamentoToggle press that
    // already happened before this press survives it. See the app target's original
    // KeyCommandMonitor for the fuller history of this behavior.
    private var snapBeforeMomentaryPortamento: Bool?

    public init(settings: any KeyActionPerforming, recordingState: any RecordingActionPerforming) {
        self.settings = settings
        self.recordingState = recordingState
    }

    // Momentary actions get pressed; toggle actions get toggled - except portamentoMomentary,
    // whose "press" temporarily overrides the toggle-backed settings.snap rather than just
    // setting a boolean, so it can restore whatever value was there before once released.
    public func applyKeyDown(_ action: KeyAction, isARepeat: Bool) {
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

    public func applyKeyUp(_ action: KeyAction) {
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

    /// Shared by every physical-input monitor (KeyboardMonitor, MouseMonitor, and macOS's
    /// KeyCommandMonitor's own right-mouse-button case - all in ContentView.swift) - resolves
    /// `token` against the current KeyMapping and either completes a pending remap capture
    /// (KeyMappingView's "+" button, via settings.pendingKeyBindingAction) or dispatches the
    /// bound action's key-down/up, exactly the same regardless of which physical device the
    /// token actually came from.
    public func handlePhysicalInput(token: KeyToken, pressed: Bool) {
        if pressed, let pendingAction = settings.pendingKeyBindingAction {
            settings.keyMapping.bind(token, to: pendingAction)
            settings.pendingKeyBindingAction = nil
            settings.isCapturingKeyBinding = false
            return
        }
        guard !settings.isCapturingKeyBinding, let action = settings.keyMapping.action(for: token) else { return }
        if pressed {
            applyKeyDown(action, isARepeat: false)
        } else if action.isMomentary {
            applyKeyUp(action)
        }
    }
}
