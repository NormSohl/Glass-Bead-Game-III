//
//  Part.swift
//  GBGCore
//
//  Created by Norman Sohl on 7/15/22.
//

import Foundation

public enum NoteEdge {
    case start
    case end
}

// Parts hold melodic lines of Notes. Each Part is monophonic - its notes always tile the
// timeline contiguously with no gaps (silence is a zero-amplitude Note, never an absence), so
// playback and editing never have to reason about "no note here" as a separate case.
public class Part: HasLength {
    public var notes: [Note] = []

    // support for audio rendering
    var currentNoteIndex:Int = 0

    var name: String?

    public init (name:String){
        self.name = name
    }

    public func getLengthInSamples()->Int{
        return notes.last?.endTime ?? 0
    }

    // find the note that contains timeSlice. This is a brute force search that should only be called to start.
    public func getCurrentNote (timeSlice:Int)->Note?{
        for index:Int in 0..<notes.count{
            let note = notes[index]
            if timeSlice >= note.startTime && timeSlice <= note.endTime {
                currentNoteIndex = index
                return note
            }
        }
        print("ERROR: getCurrentNote called with invalid timeSlice")
        return nil // timeslice is not represented in any note. Before or after the sequence?
    }

    // this needs to be fast as it is called from the audio render loop. Can it be optimized?
    public func getNextNote()->Note?{
        currentNoteIndex += 1
        if currentNoteIndex < notes.count{
            return notes[currentNoteIndex]
        }
        else{
            return nil
        }
    }

    /// Carves [startTime, endTime) out of whatever currently occupies it and inserts a new note
    /// there - the normal way a chord is entered: once per active Part, all sharing the same
    /// startTime/endTime, with no linking object tying them together afterward. A note fully
    /// inside the new span is replaced outright; a note straddling one edge is trimmed to it; a
    /// note that fully contains the new span is split into two surviving remainders. Deleting a
    /// note (leaving a block of silence, its neighbors' own boundaries untouched) is this same
    /// operation with amplitude 0 - nothing else about it is special-cased.
    @discardableResult
    public func insertNote(
        startTime: Int, endTime: Int,
        startFrequency: Double, endFrequency: Double,
        amplitude: Double,
        transition: Transition = TransFlat(),
        envelope: Envelope = EnvFlat()
    ) -> Note {
        clearRange(from: startTime, to: endTime)

        let newNote = Note(startTime: startTime, endTime: endTime, startFrequency: startFrequency, endFrequency: endFrequency, amplitude: amplitude)
        newNote.transition = transition
        newNote.envelope = envelope

        let insertAt = notes.firstIndex { $0.startTime >= endTime } ?? notes.count
        notes.insert(newNote, at: insertAt)
        return newNote
    }

    /// Convenience for inserting a note whose transition is a recorded pitch-bend contour -
    /// couples the two things a caller has to set together (the active TransRecordedContour,
    /// for playback, and Note.recordedPitchBend, the persistent buffer that survives switching
    /// to a different transition and back - see that property's own doc comment) so callers
    /// (live recording capture, segmentation) can't set one and forget the other, which
    /// otherwise means the buffer silently doesn't survive a save/load round trip even though
    /// the note plays correctly in the same session.
    @discardableResult
    public func insertRecordedNote(
        startTime: Int, endTime: Int,
        startFrequency: Double, endFrequency: Double,
        amplitude: Double,
        recordedPitchBend: [Double]
    ) -> Note {
        let note = insertNote(
            startTime: startTime, endTime: endTime,
            startFrequency: startFrequency, endFrequency: endFrequency,
            amplitude: amplitude,
            transition: TransRecordedContour(samples: recordedPitchBend))
        note.recordedPitchBend = recordedPitchBend
        return note
    }

    /// Ripple-inserts a span of time at `at`, shifting every note starting at or after it
    /// forward by `duration`. Unlike insertNote, this never discards material: a note whose
    /// span straddles `at` is split into two surviving pieces first, continuous at the cut (the
    /// split point's pitch is evaluated via the note's own transition, so neither half jumps).
    /// This can't reuse clearRange below even though the "does a note straddle this point"
    /// check looks similar - clearRange's whole job is to discard what's inside a cleared range,
    /// while a split has to keep everything.
    func insertTime(at: Int, duration: Int) {
        if let straddlingIndex = notes.firstIndex(where: { $0.startTime < at && $0.endTime > at }) {
            let straddling = notes[straddlingIndex]
            let boundaryFrequency = straddling.getCurrentFrequency(percentComplete: straddling.percentComplete(at: at))

            let leftPiece = Note(startTime: straddling.startTime, endTime: at, startFrequency: straddling.startFrequency, endFrequency: boundaryFrequency, amplitude: straddling.amplitude)
            leftPiece.transition = straddling.transition
            leftPiece.envelope = straddling.envelope

            let rightPiece = Note(startTime: at, endTime: straddling.endTime, startFrequency: boundaryFrequency, endFrequency: straddling.endFrequency, amplitude: straddling.amplitude)
            rightPiece.transition = straddling.transition
            rightPiece.envelope = straddling.envelope

            notes.remove(at: straddlingIndex)
            notes.insert(contentsOf: [leftPiece, rightPiece], at: straddlingIndex)
        }

        for note in notes where note.startTime >= at {
            note.startTime += duration
            note.endTime += duration
        }
    }

    /// Ripple-deletes [from, from+duration), closing the gap by shifting everything after it
    /// back. Clearing the range reuses insertNote's own carve rule (a note straddling an edge
    /// is trimmed, one that fully contains the range is split) - deleteTime just skips
    /// inserting a replacement note afterward, since the gap is meant to close, not stay open
    /// as silence the way a plain note deletion does.
    func deleteTime(from: Int, duration: Int) {
        let to = from + duration
        clearRange(from: from, to: to)
        for note in notes where note.startTime >= to {
            note.startTime -= duration
            note.endTime -= duration
        }
    }

    /// Discards whatever occupies [from, to), trimming or splitting boundary notes so the
    /// remaining notes still tile the timeline contiguously, with a gap left at exactly
    /// [from, to). Shared by insertNote (which fills the gap with a new note right after) and
    /// deleteTime (which shifts everything after it back to close the gap instead).
    private func clearRange(from: Int, to: Int) {
        if let containingIndex = notes.firstIndex(where: { $0.startTime < from && $0.endTime > to }) {
            let containing = notes[containingIndex]
            let leftRemainder = Note(
                startTime: containing.startTime, endTime: from,
                startFrequency: containing.startFrequency,
                endFrequency: containing.getCurrentFrequency(percentComplete: containing.percentComplete(at: from)),
                amplitude: containing.amplitude)
            leftRemainder.transition = containing.transition
            leftRemainder.envelope = containing.envelope

            let rightRemainder = Note(
                startTime: to, endTime: containing.endTime,
                startFrequency: containing.getCurrentFrequency(percentComplete: containing.percentComplete(at: to)),
                endFrequency: containing.endFrequency,
                amplitude: containing.amplitude)
            rightRemainder.transition = containing.transition
            rightRemainder.envelope = containing.envelope

            notes.remove(at: containingIndex)
            notes.insert(contentsOf: [leftRemainder, rightRemainder], at: containingIndex)
            return
        }

        notes.removeAll { existing in
            if existing.endTime <= from || existing.startTime >= to { return false } // no overlap
            if existing.startTime < from { existing.endTime = from; return false }   // straddles left edge - trim, keep
            if existing.endTime > to { existing.startTime = to; return false }       // straddles right edge - trim, keep
            return true // fully inside - remove
        }
    }

    /// Moves the shared time boundary between `note` and its immediate neighbor on `edge` to
    /// `newTime`: one grows, the other shrinks by the same amount, keeping every note tiling the
    /// timeline with no gap. This is deliberately not built on `insertNote` - that always carves
    /// a brand-new span and discards/replaces whatever occupied it, which would lose the
    /// neighbor's own pitch/transition/envelope; here the neighbor must survive untouched with
    /// just a new time extent.
    ///
    /// Clamped so neither `note` nor its neighbor is ever pushed below `minimumNoteLength`
    /// samples - a boundary drag can shrink a neighbor down to that floor but can never fully
    /// consume/delete it. (Deleting a note is still done the existing way: insertNote with
    /// amplitude 0 over its span.)
    ///
    /// No-op (returns false) if `note` isn't in this Part, if there's no room to satisfy both
    /// minimums, or if the clamped position doesn't actually move anything. If there's no
    /// neighbor on the `.end` edge (`note` is last in the Part), only `note`'s own boundary
    /// moves - nothing follows it, so there's nothing to leave a gap in. If there's no neighbor
    /// on the `.start` edge (`note` is first in the Part), the vacated `[0, newTime)` is
    /// backfilled with a silent rest rather than left uncovered - see the no-neighbor branch
    /// below for why that matters.
    @discardableResult
    public func moveNoteBoundary(of note: Note, edge: NoteEdge, to newTime: Int, minimumNoteLength: Int = 1) -> Bool {
        guard let index = notes.firstIndex(where: { $0 === note }) else { return false }

        switch edge {
        case .start:
            let previous = index > 0 ? notes[index - 1] : nil
            let lowerBound = (previous?.startTime ?? 0) + minimumNoteLength
            let upperBound = note.endTime - minimumNoteLength
            guard lowerBound <= upperBound else { return false }
            let clamped = min(max(newTime, lowerBound), upperBound)
            guard clamped != note.startTime else { return false }
            if let previous {
                previous.endTime = clamped
            } else {
                // No neighbor to shrink - back when this always just moved note.startTime with
                // nothing else, dragging the Part's very first note's start away from 0 left
                // [0, clamped) covered by no Note at all. Part.getCurrentNote/getNextNote's
                // cursor-based traversal (what ScorePlayer's real-time render loop uses) has no
                // way to recover once it lands in a gap like that - currentXNote (etc.) goes
                // nil and stays nil, since getNextNote is only ever called from inside the "while
                // let current = currentXNote" loop in advance() - silencing that voice for the
                // rest of playback even though real notes exist later. Same class of bug
                // SequencerState.placeNote was once fixed against, just reachable through this
                // different code path instead - so it gets the same fix, a backfilled rest.
                let rest = Note(startTime: 0, endTime: clamped, startFrequency: note.startFrequency, endFrequency: note.startFrequency, amplitude: 0)
                notes.insert(rest, at: index)
            }
            note.startTime = clamped
            return true

        case .end:
            let next = index < notes.count - 1 ? notes[index + 1] : nil
            let upperBound = (next?.endTime ?? Int.max) - minimumNoteLength
            let lowerBound = note.startTime + minimumNoteLength
            guard lowerBound <= upperBound else { return false }
            let clamped = min(max(newTime, lowerBound), upperBound)
            guard clamped != note.endTime else { return false }
            next?.startTime = clamped
            note.endTime = clamped
            return true
        }
    }
}
