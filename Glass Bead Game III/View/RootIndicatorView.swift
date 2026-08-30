//
//  RootIndicatorView.swift
//  Glass Bead Game III
//
//  The drone/root has never had any visual representation on the main graph - there's no
//  crosshair for it the way X/Y/Z each get one. This fills that gap for the sequencer: a thin
//  single-axis strip showing the drone's current frequency (during playback/scrub, or while
//  dragging a drone note's handle in the piano roll) as a position relative to the app's fixed
//  reference pitch, using the same log2-ratio mapping the main graph uses for X/Y. Neutral/blank
//  whenever nothing is driving it (idle, or live play - a fixed pitch alone isn't worth
//  animating).
//
//  Built generically (a position + an intensity) rather than narrowly "just a pitch dot" - the
//  intensity channel is fed by the note's own amplitude/envelope today, so future note
//  properties can drive it too without reworking this view.
//

import SwiftUI
import GBGCore

struct RootIndicatorView: View {
    let scale: Scale
    @ObservedObject var settings: AppSettings
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
