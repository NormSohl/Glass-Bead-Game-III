//
//  TransitionKind.swift
//  GBGCore
//
//  A public classification of which concrete Transition subclass a Note holds, without making
//  the subclasses themselves public. Note.transition stays a non-public stored property (its
//  type, Transition, is a public base class, but TransLinear/TransEaseIn/TransEaseOut/
//  TransEaseInEaseOut are plain internal classes - only TransFlat is public, since it's used as
//  Part.insertNote's public default parameter value). This enum lives inside GBGCore, so it can
//  freely `is`-check and construct any of the seven concrete subclasses internally; only the
//  enum and its cases need to be public, for the persistence DTO layer (SeqDocument.swift) to
//  round-trip a Note's shape from outside the module.
//

public enum TransitionKind: String, Codable, CaseIterable {
    case flat, linear, easeIn, easeOut, easeInEaseOut, recordedContour

    static func kind(of transition: Transition) -> TransitionKind {
        switch transition {
        case is TransLinear: return .linear
        case is TransEaseIn: return .easeIn
        case is TransEaseOut: return .easeOut
        case is TransEaseInEaseOut: return .easeInEaseOut
        case is TransRecordedContour: return .recordedContour
        default: return .flat
        }
    }

    // .recordedContour is special: a real reconstruction needs the actual sample data, which
    // lives on Note.recordedPitchBend, not in this dataless enum (see this file's own header
    // comment, and Note.swift's recordedPitchBend doc comment, for why they're kept
    // independent rather than folding the samples into this case). Callers that have the real
    // buffer (PartDTO.apply, the piano-roll transition picker) should construct
    // TransRecordedContour(samples:) directly instead of going through this function for that
    // case. This fallback returns an inert, sample-less contour (centsOffset always 0) so a
    // generic caller that doesn't know about the special case degrades safely rather than
    // crashing - not meant to be the normal path.
    func makeTransition() -> Transition {
        switch self {
        case .flat: return TransFlat()
        case .linear: return TransLinear()
        case .easeIn: return TransEaseIn()
        case .easeOut: return TransEaseOut()
        case .easeInEaseOut: return TransEaseInEaseOut()
        case .recordedContour: return TransRecordedContour(samples: [])
        }
    }
}
