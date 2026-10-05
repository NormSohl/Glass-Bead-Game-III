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

// One beat period, in samples, for a detected tempo - shared by the bar-line overlay (drawing)
// and the handle-drag snap check (step 4 of the live-record plan), so both agree on exactly
// where the grid lines actually are.
func pianoRollBeatPeriodSamples(tempo: TempoInfo, sampleRate: Double) -> Double {
    60.0 / tempo.bpm * sampleRate
}

// The nearest beat-grid sample to `sample`, given a detected tempo - `tempo.downbeatOffset` plus
// the nearest whole multiple of the beat period. Pure rounding, no threshold check - callers
// decide separately (PianoRollView's own snap-window logic) whether `sample` was actually close
// enough to this to snap to it.
func pianoRollNearestBeatSample(to sample: Int, tempo: TempoInfo, sampleRate: Double) -> Int {
    let periodSamples = pianoRollBeatPeriodSamples(tempo: tempo, sampleRate: sampleRate)
    guard periodSamples > 0 else { return sample }
    let beatIndex = ((Double(sample) - Double(tempo.downbeatOffset)) / periodSamples).rounded()
    return tempo.downbeatOffset + Int((beatIndex * periodSamples).rounded())
}

// A time position as people read it: "bar.beat.division" (all 1-based) with a beat grid, plain
// seconds without one. Off-grid positions (an Option-drag) floor to the division they fall in.
func pianoRollTimeLabel(sample: Int, sampleRate: Double, tempo: TempoInfo?, beatsPerBar: Int, subdivision: Int) -> String {
    guard let tempo else { return String(format: "%.3fs", Double(sample) / sampleRate) }
    let period = pianoRollBeatPeriodSamples(tempo: tempo, sampleRate: sampleRate)
    guard period > 0 else { return String(format: "%.3fs", Double(sample) / sampleRate) }
    let divisions = max(1, subdivision)
    let totalDivisions = Int((Double(sample - tempo.downbeatOffset) / period * Double(divisions) + 1e-6).rounded(.down))
    let perBar = max(1, beatsPerBar) * divisions
    // Floor-division, so positions before the downbeat count down into bar 0, -1, ...
    let bar = Int((Double(totalDivisions) / Double(perBar)).rounded(.down))
    let withinBar = totalDivisions - bar * perBar
    let beat = withinBar / divisions + 1
    let division = withinBar % divisions + 1
    return divisions > 1 ? "\(bar + 1).\(beat).\(division)" : "\(bar + 1).\(beat)"
}
