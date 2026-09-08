//
//  GraphView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 6/10/22.
//

import SwiftUI
import GBGCore

struct GraphView: View {
    let scale: Scale
    let tetradLayers: TetradLayers
    @ObservedObject var settings: AppSettings
    @ObservedObject var recordingState: RecordingState
    // false for a display-only audience view (AudienceGraphView) - omits HitTestView entirely,
    // so a second screen showing this never intercepts/reacts to touches meant for the
    // performer's own window.
    var interactive: Bool = true

    var body: some View {
        // Same Z-filtered subset of scale degrees Graph's own grid lines are drawn from (see
        // visibleScaleElements's own comment) - computed once here so all four border Ticks show
        // ratio labels only for degrees that actually have a visible line right now, instead of
        // always labelling the full scale regardless of "Filter Grid to Z".
        let visibleElements = visibleScaleElements(scale: scale, tetradLayers: tetradLayers, settings: settings)

        // Ratios mode's leading/trailing columns need real room for a horizontal "135/128"-style
        // string; top/bottom only stack a short vertical near/far pair, which the modest default
        // border already fits - widening both together (2026-09-07, since reverted) shrank the
        // graph square itself, since the same border value ate into height on both the top and
        // bottom edges for no benefit up there, visibly mismatching the Z-slider's own height.
        // Letters mode is unaffected either way - same settings.border on all four sides, as
        // before this mode existed. Shared with idealWindowSize() (Glass_Bead_Game_IIIApp.swift)
        // so the two can't drift apart - that function's own window-aspect-lock math has to
        // compensate for horizontal != vertical border here, or the graph square stops being
        // square and every grid line/diamond/label position (all computed assuming a square)
        // reads as visibly "off" (confirmed live 2026-09-07).
        let (tickBorderH, tickBorderV) = tickBorderSizes(settings: settings)

        VStack(alignment: .leading, spacing:0){// group of all graph elements

            HStack(alignment: .top, spacing:0){  // top border
                // top left corner
                Corner(width: tickBorderH, height: tickBorderV)
                // top tick marks
                Ticks(border: tickBorderV, alignment: .top, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, scale: scale, elements: visibleElements, labelStyle: settings.tickLabelStyle)
                    .frame(height: tickBorderV)
                // top right corner
                Corner(width: tickBorderH, height: tickBorderV)
            }

            HStack(alignment: .center, spacing:0){  // middle including left border, graph and right border
                // left border
                Ticks(border: tickBorderH, alignment: .leading, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, scale: scale, elements: visibleElements, labelStyle: settings.tickLabelStyle)
                    .frame(width: tickBorderH)
                ZStack(){
                    // dissonance field, drawn first so it sits behind the grid/diamonds -
                    // .equatable() (see DissonanceView's own header comment) so this doesn't
                    // re-render on every unrelated AppSettings change elsewhere in the app -
                    // only on an actual change to the values passed in below.
                    DissonanceView(
                        scale: scale,
                        rootFrequency: settings.rootFrequency,
                        zFrequency: settings.zFrequency,
                        zDragActive: settings.zDragActive,
                        selectedLimit: settings.selectedLimit,
                        showDissonance: settings.showDissonance
                    )
                    .equatable()
                    // graph
                    Graph(scale: scale, tetradLayers: tetradLayers, settings: settings)
                    TetradView(tetradLayers: tetradLayers,
                               scale: scale,
                               settings: settings,
                               showDiamonds: settings.showDiamonds)

                    if interactive {
                        HitTestView(scale:scale, settings: settings, recordingState: recordingState)
                    }
                }
                // Squareness here isn't just cosmetic - Graph.body's own drawLine deliberately
                // cross-uses size.width for the horizontal line's position and size.height for
                // the vertical line's, a shortcut that is only correct when width == height
                // exactly. idealWindowSize()'s arithmetic aims for that, but depends on a
                // successful, precisely-timed window resize (async, subject to title bar/toolbar
                // height assumptions) - a real mismatch there desynced the grid from the diamonds
                // visibly (confirmed live 2026-09-07: "look at the 1/1 diamond... look where the
                // 1/1 grid lines are - nowhere near each other"). This makes it a hard SwiftUI
                // layout guarantee instead of something that depends on that arithmetic landing
                // exactly right - .fit picks min(available width, available height), so this is
                // always a true square regardless of any window-sizing imprecision.
                .aspectRatio(1, contentMode: .fit)
                .border(.white)

                // right border
                Ticks(border: tickBorderH, alignment: .trailing, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, scale: scale, elements: visibleElements, labelStyle: settings.tickLabelStyle)
                    .frame(width: tickBorderH)
            }

            HStack(alignment: .bottom, spacing:0){  // bottom border
                // bottom left corner
                Corner(width: tickBorderH, height: tickBorderV)
                // bottom tick marks
                Ticks(border: tickBorderV, alignment: .bottom, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, scale: scale, elements: visibleElements, labelStyle: settings.tickLabelStyle)
                    .frame(height: tickBorderV)
                // bottom right corner
                Corner(width: tickBorderH, height: tickBorderV)
            }
        }
        // Ratios mode's fixed 12-EDO reference dots, drawn as its own Canvas over the whole
        // layout - see ReferenceDotsOverlay's own comment for why this needs to happen out here
        // rather than inside any one border Ticks strip. A no-op (empty Canvas) in Letters mode.
        // The ratio-fraction LABELS overlay used to live here too, but GraphSquareView's own
        // outer .clipped() (needed to contain its greedy black background) was cutting off that
        // overlay's deliberate bleed padding, clipping the outer label column - confirmed live
        // 2026-09-07 ("the outer column of ratios are now clipped"). It's now a sibling of the
        // clipped square in GraphSquareView.swift itself, outside the clip entirely, rather than
        // nested in here where it can never escape whatever clip GraphSquareView applies above
        // it. Dots stay here since they don't bleed past this composite's own bounds.
        .overlay(
            ReferenceDotsOverlay(rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, tickBorderH: tickBorderH, tickBorderV: tickBorderV, showDots: settings.tickLabelStyle == .ratios)
        )
    }
}

// Exposed (not private) so GraphSquareView.swift can compute the same Z-filtered elements and
// border sizes for its own top-level RatioLabelsOverlay placement - see that file's own comment.
func graphRatioLabelInputs(scale: Scale, tetradLayers: TetradLayers, settings: AppSettings) -> (elements: [ScaleElement], tickBorderH: Double, tickBorderV: Double) {
    let visibleElements = visibleScaleElements(scale: scale, tetradLayers: tetradLayers, settings: settings)
    let (tickBorderH, tickBorderV) = tickBorderSizes(settings: settings)
    return (visibleElements, tickBorderH, tickBorderV)
}

// How far past the graph square's own edge the ratio-fraction labels' bleed extends (see
// RatioLabelsOverlay's own comment) - shared by ContentView (reserves real HStack spacing of
// this width between the square and the Z-slider/ControlColumn so the bled label text has its
// own dead space to live in, rather than painting over those neighbors' own content - confirmed
// live 2026-09-07, "the ratios now overlay the z slider") and Glass_Bead_Game_IIIApp.swift's own
// idealWindowSize (so the window is wide enough to actually show that reserved space). Zero in
// Letters mode, which has no bleed at all.
func ratioLabelGap(settings: AppSettings) -> Double {
    settings.tickLabelStyle == .ratios ? 40.0 : 0.0
}

// Draws the fixed 12-EDO reference dots (Ratios mode) as a single Canvas sized to the ENTIRE
// graph+border+corner layout, positioned in absolute coordinates derived from the same
// tickBorderH/tickBorderV GraphView's own layout uses, rather than inside any individual border
// Ticks strip. A Ticks strip's own Canvas can never draw above the border line or the graph's own
// content (a Diamond marker at the edge of the range, or the border stroke itself) since those
// are separate sibling/cousin views with no shared stacking context - confirmed live 2026-09-07
// ("hard to see and obscured by the white border, and perhaps the graph"). Applied via .overlay()
// on the whole VStack above, so it composites strictly last/on top of everything, without
// restructuring the existing border/graph layout into one shared ZStack (Norm avoided that
// originally over alignment issues, and this sidesteps needing it). See RatioLabelsOverlay below
// for the same idea applied to the ratio-fraction labels - kept as two separate small Canvases
// rather than one doing both, per Norm's own preference.
private struct ReferenceDotsOverlay: View {
    let rangeBelow: Double
    let rangeAbove: Double
    let tickBorderH: Double
    let tickBorderV: Double
    let showDots: Bool

    var body: some View {
        Canvas { context, size in
            guard showDots else { return }
            let dotRadius = 4.0 // 20% smaller than the original 5.0, per Norm's ask 2026-09-07
            let mcolor: Color = .blue
            let graphWidth = size.width - 2 * tickBorderH
            let graphHeight = size.height - 2 * tickBorderV

            let range = abs(rangeBelow) + rangeAbove
            let numTicks = 12 * range

            for tick in 0...Int(numTicks) {
                var nudge = 0.0
                if tick == 0 { nudge = 1.0 }
                if tick == Int(numTicks) { nudge = -1.0 }

                // Top/bottom position along the graph's width; leading/trailing along its height
                // (inverted - y increasing downward on screen but scale value increasing upward).
                let alongWidth = tickBorderH + (graphWidth / numTicks) * Double(tick) + nudge
                let alongHeight = tickBorderV + graphHeight - (graphHeight / numTicks) * Double(tick) - nudge

                for point in [
                    CGPoint(x: alongWidth, y: tickBorderV),                    // top
                    CGPoint(x: alongWidth, y: size.height - tickBorderV),      // bottom
                    CGPoint(x: tickBorderH, y: alongHeight),                   // leading
                    CGPoint(x: size.width - tickBorderH, y: alongHeight),      // trailing
                ] {
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)),
                        with: .color(mcolor)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// Draws the ratio-fraction labels (Ratios mode), one per scale degree, positioned at the
// element's real just-intonation value (via scale.convertScaleValueToScreenUnits, the same
// conversion the grid lines themselves use) so a label sits level with the line it names - same
// whole-layout-Canvas approach as ReferenceDotsOverlay above, and for the same underlying reason:
// a label near the very edge of the visible range needs to render into where the (separate,
// unrelated) Corner view sits, which no per-strip Ticks Canvas could ever do without clipping it
// (confirmed live 2026-09-07). Kept as its own overlay/Canvas rather than combined with the dots
// - Norm's own preference, 2026-09-07 - even though both need the same tickBorderH/V and are
// applied the same way.
// Not private - GraphSquareView.swift places this as a top-level sibling of the clipped square,
// outside GraphSquareView's own .clipped() (see that file's comment for why).
struct RatioLabelsOverlay: View {
    let scale: Scale
    let elements: [ScaleElement]
    let rangeBelow: Double
    let rangeAbove: Double
    let tickBorderH: Double
    let tickBorderV: Double
    // How much wider/taller this view's own Canvas is than the graph+border composite it's
    // layered over (see the .overlay() call site's own comment) - every coordinate below is
    // computed in trueSize's terms (the composite's real size) and then shifted by this amount,
    // since this Canvas's local (0,0) is actually trueSize's own (-labelBleed, -labelBleed).
    let labelBleed: Double
    let trueSize: CGSize
    let showLabels: Bool

    // `elements` (GraphView.visibleScaleElements) is only ever Z-filtered - it was never also
    // restricted to the graph's own visible axis range (rangeBelow...rangeAbove), so a scale
    // degree that's a real member of the current limit's scale but falls outside what the axes
    // actually span was still getting a label, positioned wherever convertScaleValueToScreenUnits
    // happened to place it (often right at/past a corner) - confirmed live 2026-09-07 ("10/3 and
    // 7/2 are outside of the scale... they may be scale members but not used on the axes").
    private var visibleOnAxis: [ScaleElement] {
        elements.filter { $0.valueNormalized >= rangeBelow && $0.valueNormalized <= rangeAbove }
    }

    var body: some View {
        Canvas { context, size in
            let onAxis = visibleOnAxis
            guard showLabels, !onAxis.isEmpty else { return }
            // trueSize, not this Canvas's own (deliberately oversized) size - see labelBleed's
            // own comment. graphWidth/graphHeight are the real graph square's dimensions either
            // way, unaffected by the bleed.
            let graphWidth = trueSize.width - 2 * tickBorderH
            let graphHeight = trueSize.height - 2 * tickBorderV

            for alignment in [TickAlignment.top, .bottom, .leading, .trailing] {
                drawRatioLabels(context: context, alignment: alignment, elements: onAxis, graphWidth: graphWidth, graphHeight: graphHeight)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawRatioLabels(context: GraphicsContext, alignment: TickAlignment, elements: [ScaleElement], graphWidth: Double, graphHeight: Double) {
        let referenceSize = (alignment == .top || alignment == .bottom) ? graphWidth : graphHeight
        let fontSize = 10.0 // one notch up from 9.0, per Norm's ask 2026-09-07
        let mcolor: Color = .white

        // Both back up to their original, generous values now that label width no longer has to
        // fit inside tickBorderH at all (see labelBleed) - free to use as much of the bleed space
        // as looks right, independent of the graph's own (now small, fixed) border.
        let isHorizontalBorder = alignment == .top || alignment == .bottom
        let nearLabelOffset = 3.0 + fontSize * 0.7
        let farLabelOffset = 3.0 + fontSize * (isHorizontalBorder ? 2.0 : 3.2)

        for (index, element) in elements.enumerated() {
            var nudge = 0.0
            if index == 0 { nudge = 1.0 }
            if index == elements.count - 1 { nudge = -1.0 }
            let labelOffset = index % 2 == 0 ? nearLabelOffset : farLabelOffset

            let screenPosition = scale.convertScaleValueToScreenUnits(
                normalizedValue: element.valueNormalized,
                screenSize: referenceSize
            )

            // Every coordinate below is in trueSize's own coordinate space, then shifted by
            // +labelBleed at the very end (this Canvas's local (0,0) is trueSize's own
            // (-labelBleed, -labelBleed) - see that property's own comment).
            var textLocation = CGPoint(x: 0, y: 0)
            var textAnchor: UnitPoint = .center

            switch alignment {
            case .leading:
                let alongHeight = tickBorderV + graphHeight - screenPosition - nudge
                textLocation = CGPoint(x: tickBorderH - labelOffset, y: alongHeight)
                textAnchor = .trailing

            case .trailing:
                let alongHeight = tickBorderV + graphHeight - screenPosition - nudge
                textLocation = CGPoint(x: tickBorderH + graphWidth + labelOffset, y: alongHeight)
                textAnchor = .leading

            case .top:
                let alongWidth = tickBorderH + screenPosition + nudge
                textLocation = CGPoint(x: alongWidth, y: tickBorderV - labelOffset)
                textAnchor = .bottom

            case .bottom:
                let alongWidth = tickBorderH + screenPosition + nudge
                textLocation = CGPoint(x: alongWidth, y: tickBorderV + graphHeight + labelOffset)
                textAnchor = .top
            }

            textLocation.x += labelBleed
            textLocation.y += labelBleed

            let label = Text("\(element.numerator)/\(element.denominator)")
                .font(.custom("SFPro", size: fontSize))
                .foregroundStyle(mcolor)
            context.draw(label, at: textLocation, anchor: textAnchor)
        }
    }
}

// The same "which scale degrees are visible right now" filter as Graph's own grid-line drawing
// below (Tetrads.elementsPairing bracketed/snapped around the current Z) - factored out as a
// plain function so Ticks (border ratio labels) can honor "Filter Grid to Z" too, without also
// duplicating Graph's per-line fade-weight logic, which a border label doesn't need (a label is
// either shown or not, no fading). Elements are deduped by valueNormalized since a degree valid
// at both bracketing Z keys would otherwise appear (and be labelled) twice.
// The graph square's leading/trailing (horizontal) vs top/bottom (vertical) border thickness -
// shared between GraphView's own layout and idealWindowSize()'s window-aspect-lock math
// (Glass_Bead_Game_IIIApp.swift), which has to widen the window by exactly the horizontal/
// vertical difference or the graph square stops being square. Never compute either border value
// independently in a second place - route through here instead.
func tickBorderSizes(settings: AppSettings) -> (horizontal: Double, vertical: Double) {
    // Deliberately always symmetric now, in both modes - Norm's own call 2026-09-07 ("break the
    // relationship between slider space and the ratio columns... they should not be connected at
    // all"). Widening this to fit the far-row ratio label (84, then 62) always came at the direct
    // cost of pushing the Z-slider that much further from the graph, since the Z-slider sits
    // immediately adjacent to this same strip - the two were never separable as long as label
    // room had to come from here. RatioLabelsOverlay below now draws into its own deliberately
    // oversized Canvas frame that extends past the graph's actual bounds instead, so label width
    // no longer needs to borrow space from this border at all.
    let horizontal = settings.border
    let vertical = settings.border
    return (horizontal, vertical)
}

func visibleScaleElements(scale: Scale, tetradLayers: TetradLayers, settings: AppSettings) -> [ScaleElement] {
    guard settings.filterGraphLines else { return scale.scale }

    let zValueNormalized = Tetrads.rounded(log2(settings.zFrequency / settings.rootFrequency))
    let zKeys: [Double] = settings.snap
        ? (tetradLayers.nearestZKey(to: zValueNormalized).map { [$0] } ?? [])
        : tetradLayers.bracketingZKeys(around: zValueNormalized).map { $0.key }

    var seen = Set<Double>()
    var result: [ScaleElement] = []
    for key in zKeys {
        for interval in Tetrads.elementsPairing(withNormalizedValue: key, in: scale) {
            if seen.insert(interval.valueNormalized).inserted {
                result.append(interval)
            }
        }
    }
    return result
}

// filler for the corners of the border of the graph
struct Corner: View {
    var width: Double
    var height: Double

    init(border: Double) {
        self.width = border
        self.height = border
    }

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    var body: some View {

        Rectangle()
            .fill(.clear)
            .frame(width: width, height: height)
    }
}

struct Graph: View {
    var scale: Scale
    var tetradLayers: TetradLayers
    @ObservedObject var settings: AppSettings

    var body: some View {
        Canvas(){context, size in
            func drawLine(for interval: ScaleElement, weight: Double) {
                // Horizontal line
                var yIntervalInScreenUnits = scale.convertScaleValueToScreenUnits(
                    normalizedValue: interval.valueNormalized,
                    screenSize: size.width)
                // y screen values are inverted
                yIntervalInScreenUnits = size.width - yIntervalInScreenUnits

                var path = Path()
                path.move(to: CGPoint(x: 0, y: yIntervalInScreenUnits))
                path.addLine(to: CGPoint(x: size.width, y: yIntervalInScreenUnits))

                // Vertical line
                let xIntervalInScreenUnits = scale.convertScaleValueToScreenUnits(
                    normalizedValue: interval.valueNormalized,
                    screenSize: size.height)
                path.move(to: CGPoint(x: xIntervalInScreenUnits, y: 0))
                path.addLine(to: CGPoint(x: xIntervalInScreenUnits, y: size.height))

                context.stroke(path, with: .color(.gray.opacity(weight)))
            }

            // Filter the grid down to just the scale degrees that actually pair with the
            // current Z (Tetrads.elementsPairing) instead of showing every scale degree
            // regardless of Z - matches the diamonds themselves thinning out at off-root Z
            // layers. At Z=unison this is always the full scale unfiltered (see
            // elementsPairing's own doc comment), so the default view is untouched either way.
            //
            // Weighted by the same bracketing-Z-keys TetradView's diamonds cross-fade between
            // (or the single nearest key when snapped), not just one hard-cutoff Z value - a
            // line valid at one bracketing key but not the other is drawn at that key's own
            // weight, so it fades in/out through a slide exactly like the diamonds do, rather
            // than snapping on/off abruptly. A line valid at both keys is drawn twice, once per
            // key's weight - alpha stacks, same as two overlapping diamonds would.
            if settings.filterGraphLines {
                let zValueNormalized = Tetrads.rounded(log2(settings.zFrequency / settings.rootFrequency))
                let zKeys: [(key: Double, weight: Double)] = settings.snap
                    ? tetradLayers.nearestZKey(to: zValueNormalized).map { [(key: $0, weight: 1.0)] } ?? []
                    : tetradLayers.bracketingZKeys(around: zValueNormalized)

                for (key, weight) in zKeys {
                    for interval in Tetrads.elementsPairing(withNormalizedValue: key, in: scale) {
                        drawLine(for: interval, weight: weight)
                    }
                }
            } else {
                for interval in scale.scale {
                    drawLine(for: interval, weight: 1.0)
                }
            }
        }
    }
}
