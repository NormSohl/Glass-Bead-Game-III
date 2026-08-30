//
//  PianoRollCoordinates.swift
//  Seq
//
//  Pure sample<->screen-X and frequency<->screen-Y mapping for the piano-roll editor. Ported
//  verbatim from Graph's own copy - no AppSettings dependency there either, just a plain
//  rootFrequency: Double parameter, so nothing needed adapting.
//

import Foundation
import GBGCore

func pianoRollSampleToScreenX(sample: Int, offsetSamples: Int, pixelsPerSecond: Double, sampleRate: Double) -> Double {
    Double(sample - offsetSamples) / sampleRate * pixelsPerSecond
}

func pianoRollScreenXToSample(x: Double, offsetSamples: Int, pixelsPerSecond: Double, sampleRate: Double) -> Int {
    offsetSamples + Int((x / pixelsPerSecond * sampleRate).rounded())
}

func pianoRollFrequencyToScreenY(frequency: Double, rootFrequency: Double, scale: Scale, canvasHeight: Double) -> Double {
    let normalizedValue = log2(frequency / rootFrequency)
    let raw = scale.convertScaleValueToScreenUnits(normalizedValue: normalizedValue, screenSize: canvasHeight)
    return canvasHeight - raw // bottom-up: up == higher pitch, matching Graph's own views
}

func pianoRollScreenYToFrequency(y: Double, rootFrequency: Double, scale: Scale, canvasHeight: Double) -> Double {
    let flippedY = canvasHeight - y
    let normalizedValue = scale.convertScreenUnitsToScaleValue(screenLocation: flippedY, screenSize: canvasHeight)
    return rootFrequency * pow(2, normalizedValue)
}

// "Nice" 1-2-5 step snapping for the vertical time-ruler lines, so grid spacing stays legible
// across zoom levels instead of drifting to arbitrary fractions of a second.
func pianoRollNiceTimeStepSeconds(pixelsPerSecond: Double, targetPixelSpacing: Double = 80) -> Double {
    let rawStep = targetPixelSpacing / pixelsPerSecond
    let magnitude = pow(10, floor(log10(rawStep)))
    let residual = rawStep / magnitude
    let niceResidual: Double = residual < 1.5 ? 1 : residual < 3.5 ? 2 : residual < 7.5 ? 5 : 10
    return niceResidual * magnitude
}
