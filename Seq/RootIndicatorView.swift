//
//  RootIndicatorView.swift
//  Seq
//
//  Drone has no crosshair of its own (unlike X/Y/Z), so this fills that gap: a thin single-axis
//  strip showing the drone's current frequency (during playback/scrub, or while dragging a
//  drone note's handle) as a position relative to the app's fixed reference pitch. Ported
//  verbatim from Graph's own copy except for the settings type.
//

import SwiftUI
import GBGCore

struct RootIndicatorView: View {
    let scale: Scale
    @ObservedObject var settings: SeqSettings
    @ObservedObject var sequencer: SequencerState

    var body: some View {
        Canvas { context, size in
            context.stroke(
                Path(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1)),
                with: .color(.white.opacity(0.15))
            )

            guard let frequency = sequencer.drivenDroneFrequency else { return }
            let intensity = min(max(sequencer.drivenDroneAmplitude ?? 1, 0), 1)

            let normalizedValue = log2(frequency / settings.rootFrequency)
            let x = scale.convertScaleValueToScreenUnits(normalizedValue: normalizedValue, screenSize: size.width)
            let clampedX = min(max(x, 0), size.width)

            let diameter = 4 + 10 * intensity
            context.fill(
                Path(ellipseIn: CGRect(x: clampedX - diameter / 2, y: size.height / 2 - diameter / 2, width: diameter, height: diameter)),
                with: .color(.gray.opacity(0.4 + 0.6 * intensity))
            )
        }
        .frame(height: 12)
        .background(Color.black)
    }
}
