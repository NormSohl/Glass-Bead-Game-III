//
//  EnvelopeKind.swift
//  GBGCore
//
//  A public classification of which concrete Envelope subclass a Note holds, without making
//  the subclasses themselves public - see TransitionKind.swift's header comment for the same
//  reasoning, applied to Envelope/EnvFlat/EnvHump instead of Transition/TransFlat/etc.
//

public enum EnvelopeKind: String, Codable, CaseIterable {
    case flat, hump

    static func kind(of envelope: Envelope) -> EnvelopeKind {
        switch envelope {
        case is EnvHump: return .hump
        default: return .flat
        }
    }

    func makeEnvelope() -> Envelope {
        switch self {
        case .flat: return EnvFlat()
        case .hump: return EnvHump()
        }
    }
}
