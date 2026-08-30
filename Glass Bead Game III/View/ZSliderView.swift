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
    // The graph's own full square size (ContentView's graphSquareHeight) - used, alongside
    // settings.border, to size this view's diamonds by the exact same formula DiamondView/
    // TetradView use for theirs, rather than a formula rescaled to this view's own much
    // narrower canvas width. Norm: the diamonds should match the rest of the graph, in size as
    // well as color.
    let graphSquareSize: CGFloat

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

            // No leading Ticks column here - the graph's own right-border ticks (GraphView's
            // trailing Ticks, immediately to this view's left) already label every row at the
            // same height now that the two are aligned; a second copy of the same letters right
            // next to it was redundant. The canvas takes the full width freed up by removing it.
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
                // second axis here to pair it against. Diamond fill itself respects
                // settings.showDiamonds, same as the graph's; the gridlines don't.
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

                    // DiamondView's exact size formula, based on the graph's own content width
                    // (graphSquareSize minus its two 40pt borders) rather than this view's own
                    // much narrower canvas width - a scale degree's diamond is the same size
                    // here as it is on the graph itself.
                    let graphContentSize = Double(graphSquareSize) - 2 * settings.border
                    var diamondSize = (graphContentSize / 35) * sizeNormalized * 0.85
                    if diamondSize < 4 { diamondSize = 4 }

                    // DiamondView's exact color formula too - yellow gradient by size, red for
                    // the root (matching TetradView.unisonColor, same as this slider's own
                    // cursor) instead of DiamondView's gray, since red is what marks unison
                    // everywhere else in the tetrad view this slider actually drives.
                    var shade = sizeNormalized
                    if shade > 0.6 { shade = 1.0 }
                    if shade <= 0.6 { shade = shade * 1.5 }
                    let color: Color = interval.dissonance == 1.0
                        ? TetradView.unisonColor
                        : Color(red: shade, green: shade, blue: 0.0)

                    if settings.showDiamonds {
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
                    // hit.frequency is a pure function of hoverLocation/rootFrequency/snap, so
                    // it only actually differs from settings.zFrequency when one of those truly
                    // changed since the last render - guards against resending the exact same Z
                    // pitch (to both the synth and any live MIDI destination) on every unrelated
                    // view update this Canvas happens to re-run for. Same bug, same fix, as
                    // HitTestView's X/Y.
                    if hit.frequency != settings.zFrequency {
                        settings.zFrequency = hit.frequency
                        sound.setZPitch(frequency: hit.frequency)
                    }
                    // hit.crosshair is in the same bottom-up convention as X/Y; flip back to draw
                    markerY = size.height - hit.crosshair
                }

                // Red, matching TetradView.unisonColor - the red unison diamond (X = Y = Z)
                // tracks wherever this marker currently sits, so the cursor is colored to match
                // what it drives.
                context.fill(
                    Path(CGRect(x: 0, y: markerY - 2, width: size.width, height: 4)),
                    with: .color(TetradView.unisonColor)
                )
            }
            .background(.white.opacity(0.08))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        hasTouched = true
                        settings.zDragActive = true
                        hoverLocation = value.location
                        hoverLocation.y = zSliderHeight - hoverLocation.y
                        if isSound == false {
                            sound.beginZTouch(amp: 1)
                            isSound = true
                        }
                    }
                    .onEnded { _ in
                        settings.zDragActive = false
                        sound.endZTouch(pedal: settings.pedal)
                        if !settings.pedal {
                            isSound = false
                        }
                    }
            )

            Color.clear.frame(height: settings.border)
        }
        .background(Color.black)
#if os(iOS)
        .defersSystemGestures(on: .all)
#endif
    }
}
