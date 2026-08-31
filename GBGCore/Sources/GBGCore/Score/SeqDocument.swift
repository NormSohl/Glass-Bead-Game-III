//
//  SeqDocument.swift
//  GBGCore
//
//  Basic save/load for a Seq piece - pure data, no audio/MIDI concern, so it lives in GBGCore
//  alongside Score/Part/Note rather than in GBGSound or the Seq app target. A DTO layer rather
//  than making Part/Note themselves Codable: Part's own tiling invariants (contiguous notes,
//  silence as a zero-amplitude Note) are enforced by its own insertNote/clearRange logic, not
//  by its stored representation, so loading goes back through insertNote rather than direct
//  property mutation - the same path live editing already uses.
//

import Foundation

public struct NoteDTO: Codable {
    public let startTime: Int
    public let endTime: Int
    public let startFrequency: Double
    public let endFrequency: Double
    public let amplitude: Double
    public let transitionKind: TransitionKind
    public let envelopeKind: EnvelopeKind
    // Independent of transitionKind above - the persistent recorded buffer survives a switch
    // to a different active transition, so this can be populated even when transitionKind
    // isn't .recordedContour (see Note.recordedPitchBend's own doc comment for why).
    public let recordedPitchBend: [Double]?

    public init(startTime: Int, endTime: Int, startFrequency: Double, endFrequency: Double, amplitude: Double, transitionKind: TransitionKind, envelopeKind: EnvelopeKind, recordedPitchBend: [Double]? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.startFrequency = startFrequency
        self.endFrequency = endFrequency
        self.amplitude = amplitude
        self.transitionKind = transitionKind
        self.envelopeKind = envelopeKind
        self.recordedPitchBend = recordedPitchBend
    }

    init(note: Note) {
        self.startTime = note.startTime
        self.endTime = note.endTime
        self.startFrequency = note.startFrequency
        self.endFrequency = note.endFrequency
        self.amplitude = note.amplitude
        self.transitionKind = note.transitionKind
        self.envelopeKind = note.envelopeKind
        self.recordedPitchBend = note.recordedPitchBend
    }
}

public struct PartDTO: Codable {
    public let notes: [NoteDTO]

    public init(notes: [NoteDTO]) {
        self.notes = notes
    }

    init(part: Part) {
        self.notes = part.notes.map { NoteDTO(note: $0) }
    }

    /// Rebuilds `part`'s contents from this DTO's notes, via Part's own public insertNote -
    /// never direct property mutation - so Part's own tiling invariants ("silence is a
    /// zero-amplitude Note, never an absence") are respected exactly the way live editing
    /// respects them. Clears whatever the Part currently holds first.
    func apply(to part: Part) {
        part.notes.removeAll()
        for noteDTO in notes {
            // .recordedContour needs the real sample data, which TransitionKind.makeTransition()
            // can't supply on its own (see its own doc comment) - construct it directly from
            // this note's buffer when that's the active kind.
            let transition: Transition
            if noteDTO.transitionKind == .recordedContour, let buffer = noteDTO.recordedPitchBend {
                transition = TransRecordedContour(samples: buffer)
            } else {
                transition = noteDTO.transitionKind.makeTransition()
            }
            let newNote = part.insertNote(
                startTime: noteDTO.startTime, endTime: noteDTO.endTime,
                startFrequency: noteDTO.startFrequency, endFrequency: noteDTO.endFrequency,
                amplitude: noteDTO.amplitude,
                transition: transition,
                envelope: noteDTO.envelopeKind.makeEnvelope())
            // Independent of which transition ended up active above - the buffer survives
            // regardless (see NoteDTO.recordedPitchBend's own comment).
            newNote.recordedPitchBend = noteDTO.recordedPitchBend
        }
    }
}

public struct SeqDocument: Codable {
    public let dronePart: PartDTO
    public let xPart: PartDTO
    public let yPart: PartDTO
    public let zPart: PartDTO
    // Metadata only, from a live recording's onset times (see TempoDetection.swift) - nil for a
    // document with no detected tempo (never recorded, or recorded but unmetered/melismatic,
    // which is the expected result for that material, not a gap). Never drives note placement;
    // future UI (grid display, opt-in snap-on-drag) is the only consumer.
    public let tempoInfo: TempoInfo?

    public init(dronePart: Part, xPart: Part, yPart: Part, zPart: Part, tempoInfo: TempoInfo? = nil) {
        self.dronePart = PartDTO(part: dronePart)
        self.xPart = PartDTO(part: xPart)
        self.yPart = PartDTO(part: yPart)
        self.zPart = PartDTO(part: zPart)
        self.tempoInfo = tempoInfo
    }

    /// Applies this document onto Seq's own existing Part instances (SequencerState's
    /// dronePart/xPart/yPart/zPart) rather than constructing new ones - Seq's ScorePlayer and
    /// UI already hold references to those specific four objects.
    public func apply(toDronePart dronePart: Part, xPart: Part, yPart: Part, zPart: Part) {
        self.dronePart.apply(to: dronePart)
        self.xPart.apply(to: xPart)
        self.yPart.apply(to: yPart)
        self.zPart.apply(to: zPart)
    }
}
