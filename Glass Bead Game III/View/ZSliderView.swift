//
//  ZSliderView.swift
//  Glass Bead Game III
//
//  The vertical slider for Z, the depth-slider feature's third moving tone (see the
//  glass_bead_game_iii_depth_slider_design memory notes). Z is a genuinely audible 4th voice,
//  with its pitch published to `sound` every frame this is touched - but unlike X/Y, touching
//  this slider can no longer start or stop sound on its own; only the graph's own touch (or the
//  pedal) can do that. See the gesture below and Sound.applyZVoiceEnables.
//
//  Reuses the same Ticks view the graph's own borders use for gradations, and the same
//  pitchHitTest function HitTestView uses for X/Y - Z is "one more axis, one more touch" on the
//  same scale, not a new mechanism.

import SwiftUI
import GBGCore

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
              HangProfiler.shared.measure("ZSliderView.body.Canvas") {
                zSliderHeight = size.height

                // Cursor drawn first, diamonds after (and gridlines after that too, in the loop
                // below) - Norm wants the diamonds sitting fully on top of the cursor bar rather
                // than the bar cutting a visible line across whichever diamond it currently
                // overlaps, e.g. the central/unison one when Z sits at the root.
                //
                // Same driven-vs-touch split as HitTestView's x/y - see
                // AppSettings.externallyDrivenVoices. When incoming MIDI (Seq, or any other
                // controller) owns Z - see Sound.handleIncomingMidi - the marker is drawn from
                // whatever was already written into settings.zFrequency instead of from touch.
                //
                // Gated on settings.zDragActive, not hasTouched (used to be the latter, which
                // only ever asked "has Z EVER been touched this session," not "is it being
                // touched RIGHT NOW") - confirmed live 2026-09-08: with hasTouched once true,
                // this branch recomputed from the same frozen hoverLocation on EVERY render
                // regardless of whether a drag was active, so an unrelated global settings.snap
                // change elsewhere (Portamento engaging via the graph's own right-click, nothing
                // to do with Z at all) silently re-derived Z's position from snapped to
                // continuous at that same frozen location, audible as a small unwanted "bump."
                // zDragActive starts false and is only ever true during a real drag, so it also
                // still covers the original "before the first touch" case hasTouched existed for
                // - hasTouched itself removed as fully redundant once this replaced it.
                let markerY: Double
                if settings.externallyDrivenVoices.contains(.z) || !settings.zDragActive {
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

                // White - Norm's own choice, distinct from the diamond-list's own colors (now
                // that those match DiamondView's, gray/yellow/red, none of which would stand out
                // as a cursor the way the old red - actually TetradView.unisonColor, the X=Y=Z
                // tetrad-alignment color, a different "unison" than this diamond list's own -
                // did by coincidence).
                context.fill(
                    Path(CGRect(x: 0, y: markerY - 2, width: size.width, height: 4)),
                    with: .color(.white)
                )

                // Scale-degree gridlines and diamonds, drawn after the cursor above so the
                // diamonds stay on top of it - Norm: the slider should read like a compressed
                // copy of the graph's own axis, not a bare touch strip. Same
                // convertScaleValueToScreenUnits mapping (and,
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
                    // much narrower canvas width - a scale degree's diamond used to be the same
                    // size here as on the graph itself. Norm: the larger diamonds in this
                    // narrower strip read as oversized relative to it - the extra 0.8 factor
                    // (applied before the floor below, not to it) shrinks anything already well
                    // above the 4pt floor by 20%, while whatever was already hitting that floor
                    // stays clamped there exactly as before, unaffected - it can't go smaller
                    // regardless. This is a deliberate size break from DiamondView's own
                    // unchanged formula, scoped to this slider alone.
                    let graphContentSize = Double(graphSquareSize) - 2 * settings.border
                    var diamondSize = (graphContentSize / 35) * sizeNormalized * 0.85 * 0.8
                    if diamondSize < 4 { diamondSize = 4 }

                    // Yellow gradient by size, matching DiamondView's own formula - but red, not
                    // DiamondView's gray, for the central/unison diamond: what actually reads as
                    // "the graph's own color" at that position in the running app is the X=Y=Z
                    // tetrad marker (TetradView.unisonColor) drawn over it, not DiamondView's own
                    // gray diamond underneath - Norm confirmed live. DiamondView's dissonance==3.0
                    // case already uses this identical red (0.8/0.3/0.3, same values as
                    // TetradView.unisonColor), so both map to the same color here too.
                    var shade = sizeNormalized
                    if shade > 0.6 { shade = 1.0 }
                    if shade <= 0.6 { shade = shade * 1.5 }
                    var color = Color(red: shade, green: shade, blue: 0.0)
                    if interval.dissonance == 1.0 || interval.dissonance == 3.0 {
                        color = Color(red: 0.8, green: 0.3, blue: 0.3)
                    }

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
                        // DiamondView strokes every diamond in gray too - unstroked, this
                        // slider's fills read brighter/more saturated by contrast, with no
                        // muting border softening the edge the way the graph's own diamonds have.
                        context.stroke(diamondPath, with: .color(.gray))
                    }
                }
              }
            }
            .background(.white.opacity(0.08))
            // See GraphView's own matching .accessibilityHidden(true) comment - same reasoning,
            // same diagnostic hypothesis (2026-09-10).
            .accessibilityHidden(true)
            // macOS: a plain SwiftUI DragGesture, same as always - the mouse IS the legitimate
            // touch-equivalent input there, nothing to filter out.
            //
            // iOS: FingerAndPencilDragCatcher (FingerAndPencilOnly.swift) instead, same as
            // HitTestView's own graph drag - NOT a DragGesture at all on iOS, so there's no
            // separate SwiftUI gesture recognizer left to race against. Finger, Pencil, and mouse
            // drag all move Z, matching the Mac.
            #if os(macOS)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in handleZDragChanged(location: value.location) }
                    .onEnded { _ in handleZDragEnded() }
            )
            #else
            .overlay(
                FingerAndPencilDragCatcher(
                    onChanged: { location in handleZDragChanged(location: location) },
                    onEnded: { handleZDragEnded() }
                )
            )
            #endif

            Color.clear.frame(height: settings.border)
        }
        .background(Color.black)
#if os(iOS)
        .defersSystemGestures(on: .all)
#endif
    }

    // Shared by the drag gesture/catcher above, on both platforms.
    private func handleZDragChanged(location: CGPoint) {
      HangProfiler.shared.measure("ZSliderView.handleZDragChanged") {
        settings.zDragActive = true
        hoverLocation = location
        hoverLocation.y = zSliderHeight - hoverLocation.y
        // No sound.beginZTouch(amp:) here - Norm: after practicing with it, the Z-slider must
        // never start a note on its own (so levels can be changed silently); only the pen
        // (HitTestView's graph touch) may trigger sound.
      }
    }

    private func handleZDragEnded() {
        settings.zDragActive = false
    }
}
