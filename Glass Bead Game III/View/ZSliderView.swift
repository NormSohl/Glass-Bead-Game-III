//
//  ZSliderView.swift
//  Glass Bead Game III
//
//  The vertical slider for Z, the depth-slider feature's third moving tone (see the
//  glass_bead_game_iii_depth_slider_design memory notes). Z is now a genuinely audible 4th
//  voice, wired the same way X/Y already are: pitch published to `sound` every frame this is
//  touched, and its own touch-begin/touch-end pair gating the shared audio engine alongside the
//  graph's.
//
//  Reuses the same Ticks view the graph's own borders use for gradations, and the same
//  pitchHitTest function HitTestView uses for X/Y - Z is "one more axis, one more touch" on the
//  same scale, not a new mechanism.

import SwiftUI

// Same reasoning as HitTestView's module-scope `height`: mutating this from inside the Canvas
// closure as @State caused inconsistent behavior there, so this follows the same workaround.
var zSliderHeight = 0.0

struct ZSliderView: View {
    let scale: Scale
    let settings: AppSettings

    @State private var hoverLocation: CGPoint = .zero
    @State private var isSound = false

    var body: some View {
        HStack(spacing: 0) {
            Ticks(border: settings.border,
                  alignment: .leading,
                  rangeBelow: scale.lowestRatioNormalized,
                  rangeAbove: scale.highestRatioNormalized)
                .frame(width: settings.border)

            Canvas { context, size in
                zSliderHeight = size.height

                let hit = pitchHitTest(
                    scale: scale,
                    screenLocation: hoverLocation.y,
                    graphSize: size.height,
                    rootFrequency: sound.audio.triad.getTriadRootPitch(),
                    snapped: settings.snap)
                settings.zFrequency = hit.frequency
                sound.setZPitch(frequency: hit.frequency)

                // hit.crosshair is in the same bottom-up convention as X/Y; flip back to draw
                let markerY = size.height - hit.crosshair
                context.fill(
                    Path(CGRect(x: 0, y: markerY - 2, width: size.width, height: 4)),
                    with: .color(.white)
                )
            }
            .background(.white.opacity(0.08))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        hoverLocation = value.location
                        hoverLocation.y = zSliderHeight - hoverLocation.y
                        if isSound == false {
                            sound.beginTouch(amp: 1)
                            isSound = true
                        }
                    }
                    .onEnded { _ in
                        sound.endTouch(pedal: settings.pedal)
                        if !settings.pedal {
                            isSound = false
                        }
                    }
            )
        }
        .background(Color.black)
#if os(iOS)
        .defersSystemGestures(on: .all)
#endif
    }
}
