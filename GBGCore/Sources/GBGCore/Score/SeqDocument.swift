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

    public init(startTime: Int, endTime: Int, startFrequency: Double, endFrequency: Double, amplitude: Double, transitionKind: TransitionKind, envelopeKind: EnvelopeKind) {
        self.startTime = startTime
        self.endTime = endTime
        self.startFrequency = startFrequency
        self.endFrequency = endFrequency
        self.amplitude = amplitude
        self.transitionKind = transitionKind
        self.envelopeKind = envelopeKind
    }

    init(note: Note) {
        self.startTime = note.startTime
        self.endTime = note.endTime
        self.startFrequency = note.startFrequency
        self.endFrequency = note.endFrequency
        self.amplitude = note.amplitude
        self.transitionKind = note.transitionKind
        self.envelopeKind = note.envelopeKind
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
            part.insertNote(
                startTime: noteDTO.startTime, endTime: noteDTO.endTime,
                startFrequency: noteDTO.startFrequency, endFrequency: noteDTO.endFrequency,
                amplitude: noteDTO.amplitude,
                transition: noteDTO.transitionKind.makeTransition(),
                envelope: noteDTO.envelopeKind.makeEnvelope())
        }
    }
}

public struct SeqDocument: Codable {
    public let dronePart: PartDTO
    public let xPart: PartDTO
    public let yPart: PartDTO
    public let zPart: PartDTO

    public init(dronePart: Part, xPart: Part, yPart: Part, zPart: Part) {
        self.dronePart = PartDTO(part: dronePart)
        self.xPart = PartDTO(part: xPart)
        self.yPart = PartDTO(part: yPart)
        self.zPart = PartDTO(part: zPart)
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
