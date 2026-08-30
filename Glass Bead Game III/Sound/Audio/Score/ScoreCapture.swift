//
//  ScoreCapture.swift
//  Glass Bead Game III
//
//  The graph-specific adapter between live touch state and the Score/Part/Note core in
//  GBGCore: reads the graph's current root/X/Y/Z frequencies (published into AppSettings by
//  HitTestView/ZSliderView every touch-move frame) and writes them into a Score as a chord -
//  one Part.insertNote call per enabled voice, all sharing the same time span, per the
//  sequencer design notes. Score/Part/Note themselves know nothing about "drone"/"X"/"Y"/"Z" or
//  the graph; this is the only place that mapping exists, so a future non-graph client of the
//  sequencer core wouldn't need any of this.
//

import Foundation
import GBGCore

enum ScoreCapture {
    /// Captures the graph's current live selection as one chord: one Note per enabled voice
    /// (per `sound.enableDrone`/`enableX`/`enableY`/`enableZ`), written into the matching Part
    /// via `insertNote`, all sharing [atTime, atTime + duration). A muted voice, or one with no
    /// Part supplied for it, is simply skipped - not written as silence, since nothing was
    /// actually selected for it.
    static func captureChord(
        settings: AppSettings,
        sound: Sound,
        dronePart: Part?, xPart: Part?, yPart: Part?, zPart: Part?,
        atTime: Int, duration: Int, amplitude: Double = 1.0
    ) {
        let endTime = atTime + duration

        if sound.enableDrone, let dronePart {
            dronePart.insertNote(startTime: atTime, endTime: endTime, startFrequency: settings.rootFrequency, endFrequency: settings.rootFrequency, amplitude: amplitude)
        }
        if sound.enableX, let xPart {
            xPart.insertNote(startTime: atTime, endTime: endTime, startFrequency: settings.xFrequency, endFrequency: settings.xFrequency, amplitude: amplitude)
        }
        if sound.enableY, let yPart {
            yPart.insertNote(startTime: atTime, endTime: endTime, startFrequency: settings.yFrequency, endFrequency: settings.yFrequency, amplitude: amplitude)
        }
        if sound.enableZ, let zPart {
            zPart.insertNote(startTime: atTime, endTime: endTime, startFrequency: settings.zFrequency, endFrequency: settings.zFrequency, amplitude: amplitude)
        }
    }
}
