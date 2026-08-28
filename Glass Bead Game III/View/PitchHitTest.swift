//
//  PitchHitTest.swift
//  Glass Bead Game III
//
//  Shared by every touch-controlled pitch axis (X, Y, and now Z): given a touch location along
//  one axis of a `scale`, find the resulting frequency and the screen position to draw a
//  crosshair/marker at. Extracted from HitTestView, which used this same logic twice (once per
//  axis) before Z needed a third caller.
//

import Foundation

func pitchHitTest(
    scale: Scale,
    screenLocation: Double,
    graphSize: Double,
    rootFrequency: Double,
    snapped: Bool
) -> (frequency: Double, crosshair: Double) {
    for scaleElement in scale.scale {
        let lowerBounds = scale.convertScaleValueToScreenUnits(
            normalizedValue: scaleElement.lowerBounds,
            screenSize: graphSize)
        let upperBounds = scale.convertScaleValueToScreenUnits(
            normalizedValue: scaleElement.upperBounds,
            screenSize: graphSize)

        if screenLocation >= lowerBounds && screenLocation <= upperBounds {
            return pitchHitTestCore(
                scale: scale,
                screenLocation: screenLocation,
                graphSize: graphSize,
                scaleElement: scaleElement,
                rootFrequency: rootFrequency,
                snapped: snapped)
        }
    }
    return (frequency: 0.0, crosshair: 0.0)
}

func pitchHitTestCore(
    scale: Scale,
    screenLocation: Double,
    graphSize: Double,
    scaleElement: ScaleElement,
    rootFrequency: Double,
    snapped: Bool
) -> (frequency: Double, crosshair: Double) {
    if !snapped {
        // unsnapped: play the raw continuous pitch under the touch, don't snap the crosshair either
        let screenRatio = screenLocation / graphSize
        var value = scale.rangeNormalized * screenRatio
        value = value + scale.lowestRatioNormalized

        let frequencyRatio = pow(2, value)
        let frequency = rootFrequency * frequencyRatio
        let crosshair = scale.convertScaleValueToScreenUnits(normalizedValue: value, screenSize: graphSize)
        return (frequency, crosshair)
    } else {
        // snapped: play the scale element's exact value, snap the crosshair to it too
        let frequency = rootFrequency * scaleElement.value
        let crosshair = scale.convertScaleValueToScreenUnits(normalizedValue: scaleElement.valueNormalized, screenSize: graphSize)
        return (frequency, crosshair)
    }
}
