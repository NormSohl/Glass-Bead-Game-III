//
//  PitchEntry.swift
//  GBGCore
//
//  Pitch snapping, parsing and display for Seq's note editor. Pitches are frequencies
//  throughout the score model; these helpers translate between that and what a person works
//  with - the just-intonation scale's ratios (snap targets for drags, "5/4"-style text) and
//  plain Hz for anything off the scale.
//

import Foundation

public extension Scale {
    /// The scale element nearest to `frequency` (compared in log/pitch space, not Hz), and the
    /// frequency it lands on relative to `rootFrequency`. Nil only for an empty scale or a
    /// non-positive input.
    func nearestElement(to frequency: Double, rootFrequency: Double) -> (element: ScaleElement, frequency: Double)? {
        guard frequency > 0, rootFrequency > 0 else { return nil }
        let target = log2(frequency / rootFrequency)
        guard let best = scale.min(by: { abs($0.valueNormalized - target) < abs($1.valueNormalized - target) }) else { return nil }
        return (best, rootFrequency * best.value)
    }

    /// `frequency` snapped to the nearest scale element.
    func snappedFrequency(_ frequency: Double, rootFrequency: Double) -> Double {
        nearestElement(to: frequency, rootFrequency: rootFrequency)?.frequency ?? frequency
    }
}

public enum PitchText {
    /// How close (in cents) a frequency must be to a scale element to be shown as that ratio.
    static let ratioToleranceCents = 0.5

    /// Parses what a person types into a pitch field: a ratio against the root ("5/4", "3 / 2",
    /// "1/1"), or a frequency in Hz ("440", "440 Hz", "261.6hz"). Nil if it's neither, or not a
    /// positive pitch.
    public static func parse(_ text: String, rootFrequency: Double) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), n > 0, d > 0 else { return nil }
            return rootFrequency * n / d
        }
        let number = trimmed.hasSuffix("hz") ? String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces) : trimmed
        guard let hz = Double(number), hz > 0 else { return nil }
        return hz
    }

    /// Shows a frequency as its scale ratio ("5/4") when it sits on a scale element, otherwise as
    /// Hz ("441.30 Hz").
    public static func format(_ frequency: Double, rootFrequency: Double, scale: Scale) -> String {
        if let (element, _) = scale.nearestElement(to: frequency, rootFrequency: rootFrequency),
           abs(1200 * log2(frequency / rootFrequency) - element.valueNormalizedCents) < ratioToleranceCents {
            let divisor = gcd(element.numerator, element.denominator)
            return "\(element.numerator / divisor)/\(element.denominator / divisor)"
        }
        return String(format: "%.2f Hz", frequency)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? max(a, 1) : gcd(b, a % b)
    }
}
