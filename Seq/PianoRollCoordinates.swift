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

func pianoRollFrequencyToScreenY(frequency: Double, rootFrequency: Double, scale: Scale, canvasHeight: Double, verticalZoomFactor: Double = 1.0) -> Double {
    let normalizedValue = log2(frequency / rootFrequency)
    // Feeding a taller virtual screenSize (canvasHeight * verticalZoomFactor) into Scale's own
    // auto-fit math is what makes this zoomable at all - Scale itself has no zoom concept, it
    // just maps the whole scale range to whatever screenSize it's given.
    let raw = scale.convertScaleValueToScreenUnits(normalizedValue: normalizedValue, screenSize: canvasHeight * verticalZoomFactor)
    return canvasHeight - raw // bottom-up: up == higher pitch, matching Graph's own views
}

func pianoRollScreenYToFrequency(y: Double, rootFrequency: Double, scale: Scale, canvasHeight: Double, verticalZoomFactor: Double = 1.0) -> Double {
    let flippedY = canvasHeight - y
    let normalizedValue = scale.convertScreenUnitsToScaleValue(screenLocation: flippedY, screenSize: canvasHeight * verticalZoomFactor)
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

// One beat period, in samples - shared by grid drawing, the ruler, grid snapping and beat-based
// note lengths, so they all agree on where the beats are.
func pianoRollBeatPeriodSamples(tempo: TempoInfo, sampleRate: Double) -> Double {
    60.0 / tempo.bpm * sampleRate
}
