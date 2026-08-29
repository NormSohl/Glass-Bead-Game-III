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
    @ObservedObject var settings: AppSettings

    @State private var hoverLocation: CGPoint = .zero
    @State private var isSound = false
    // Guards against the canvas overwriting settings.zFrequency on its very first render, before
    // any real touch - hoverLocation starts at .zero (screenLocation 0, the low end of the
    // slider), so without this the untouched slider would silently drag zFrequency down to the
    // scale's lowest ratio the instant it mounts, undoing ControlView's "reset to unison when
    // the 3rd moving tone toggles on" behavior before the user ever touches it.
    @State private var hasTouched = false

    var body: some View {
        // Mirrors GraphView's own 3-row structure (top border spacer, middle Ticks+content,
        // bottom border spacer) so the canvas below ends up the same height *and* the same
        // vertical position within the row as the graph's own inner content area - not just the
        // same overall height. Without top/bottom spacers matching the graph's own 40pt top/
        // bottom border rows, sizing this view to the graph's full outer square height (its
        // aspectRatio square includes those borders) would still leave the canvas spanning the
        // *entire* square top-to-bottom while the graph's real content sits inset within it,
        // which is what caused the original "line up" bug Norm flagged - close but not exact.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: settings.border)

            HStack(spacing: 0) {
                Ticks(border: settings.border,
                      alignment: .leading,
                      rangeBelow: scale.lowestRatioNormalized,
                      rangeAbove: scale.highestRatioNormalized)
                    .frame(width: settings.border)

                Canvas { context, size in
                    zSliderHeight = size.height

                // Scale-degree gridlines and diamonds, drawn first so the touch marker stays on
                // top - Norm: the slider should read like a compressed copy of the graph's own
                // axis, not a bare touch strip. Same convertScaleValueToScreenUnits mapping (and,
                // as of ContentView's graphSquareHeight, the same pixel height) the graph itself
                // uses for its gridlines, so a given scale degree lines up row-for-row between
                // the two. Diamonds centered horizontally in the narrow canvas, sized by each
                // element's own numerator/denominator complexity - DiamondView's same inverted-
                // power formula, applied to one ratio instead of an X:Y pair since there's no
                // second axis here to pair it against.
                for interval in scale.scale {
                    var y = scale.convertScaleValueToScreenUnits(
                        normalizedValue: interval.valueNormalized, screenSize: size.height)
                    y = size.height - y

                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        },
                        with: .color(.gray)
                    )

                    var sizeNormalized = Double(max(interval.numerator, interval.denominator)) / Double(scale.limit)
                    sizeNormalized = 1 - sizeNormalized
                    var diamondSize = (Double(size.width) / 2 - 1) * sizeNormalized
                    if diamondSize < 2 { diamondSize = 2 }

                    var shade = sizeNormalized
                    if shade > 0.6 { shade = 1.0 }
                    if shade <= 0.6 { shade = shade * 1.5 }
                    let color: Color = interval.dissonance == 1.0
                        ? Color(red: 0.75, green: 0.75, blue: 0.78) // 1/1 - the drone's own pitch
                        : Color(red: shade, green: shade, blue: 0.0)

                    let x = Double(size.width) / 2
                    let diamondPath = Path { path in
                        path.move(to: CGPoint(x: x - diamondSize, y: y))
                        path.addLine(to: CGPoint(x: x, y: y + diamondSize))
                        path.addLine(to: CGPoint(x: x + diamondSize, y: y))
                        path.addLine(to: CGPoint(x: x, y: y - diamondSize))
                        path.closeSubpath()
                    }
                    context.fill(diamondPath, with: .color(color))
                }

                // Same driven-vs-touch split as HitTestView's x/y - see AppSettings.
                // sequencerDrivenVoices. When the sequencer owns Z (playback, scrub, or a
                // piano-roll handle drag on a Z note), the marker is drawn from whatever it
                // already wrote into settings.zFrequency instead of from touch. Same read-only
                // treatment applies before the first real touch (see hasTouched above).
                let markerY: Double
                if settings.sequencerDrivenVoices.contains(.z) || !hasTouched {
                    let zNormalized = log2(settings.zFrequency / settings.rootFrequency)
                    let crosshair = scale.convertScaleValueToScreenUnits(normalizedValue: zNormalized, screenSize: size.height)
                    markerY = size.height - crosshair
                } else {
                    let hit = pitchHitTest(
                        scale: scale,
                        screenLocation: hoverLocation.y,
                        graphSize: size.height,
                        rootFrequency: settings.rootFrequency,
                        snapped: settings.snap)
                    settings.zFrequency = hit.frequency
                    sound.setZPitch(frequency: hit.frequency)
                    // hit.crosshair is in the same bottom-up convention as X/Y; flip back to draw
                    markerY = size.height - hit.crosshair
                }

                context.fill(
                    Path(CGRect(x: 0, y: markerY - 2, width: size.width, height: 4)),
                    with: .color(.white)
                )
            }
            .background(.white.opacity(0.08))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        hasTouched = true
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

            Color.clear.frame(height: settings.border)
        }
        .background(Color.black)
#if os(iOS)
        .defersSystemGestures(on: .all)
#endif
    }
}
