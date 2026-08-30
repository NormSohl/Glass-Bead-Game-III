//
//  SequencerCapture.swift
//  Glass Bead Game III
//
//  The sequencer's "Add Note" entry point: captures whatever chord is currently live on the
//  graph into the score at the playhead. Thin wrapper around the existing ScoreCapture.captureChord
//  - the one thing this adds is keeping each voice's Part contiguous even when a voice has been
//  disabled for one or more earlier captures.
//

import Foundation
import GBGCore

enum SequencerCapture {
    /// Captures the graph's current chord (per sound.enableDrone/enableX/enableY/enableZ and
    /// settings.rootFrequency/xFrequency/yFrequency/zFrequency, exactly as ScoreCapture.captureChord
    /// already does) into each enabled voice's Part at the playhead, then advances the playhead
    /// by the current note duration so repeated presses lay down a sequence in time order.
    ///
    /// Backfills silence into any voice's Part that's fallen behind the playhead first - Part
    /// requires its notes to tile contiguously with no gaps, and ScoreCapture.captureChord only
    /// ever fills [atTime, atTime+duration): a voice that was disabled for an earlier capture (so
    /// its Part didn't get a note then) would otherwise be left with a gap between its last note
    /// and the new one. That gap is not just visually wrong - Part.getCurrentNote starting inside
    /// it during playback returns nil and that voice goes silent for the rest of the piece, since
    /// getNextNote is only ever reached from a non-nil currentNote.
    static func captureChordAtPlayhead(sequencer: SequencerState, settings: AppSettings, sound: Sound) {
        let atTime = sequencer.playheadSample
        let duration = sequencer.noteDurationSamples

        for part in [sequencer.dronePart, sequencer.xPart, sequencer.yPart, sequencer.zPart] {
            let existingEnd = part.getLengthInSamples()
            if atTime > existingEnd {
                part.insertNote(startTime: existingEnd, endTime: atTime, startFrequency: 0, endFrequency: 0, amplitude: 0)
            }
        }

        ScoreCapture.captureChord(
            settings: settings, sound: sound,
            dronePart: sequencer.dronePart, xPart: sequencer.xPart, yPart: sequencer.yPart, zPart: sequencer.zPart,
            atTime: atTime, duration: duration)

        sequencer.advancePlayhead(by: duration)
        sequencer.scoreRevision += 1
    }
}
