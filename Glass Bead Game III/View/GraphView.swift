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

        VStack(alignment: .leading, spacing:0){// group of all graph elements

            HStack(alignment: .top, spacing:0){  // top border
                // top left corner
                Corner(border: settings.border)
                // top tick marks
                Ticks(border: settings.border, alignment: .top, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, scale: scale, elements: visibleElements, labelStyle: settings.tickLabelStyle)
                    .frame(height: settings.border)
                // top right corner
                Corner(border: settings.border)
            }

            HStack(alignment: .center, spacing:0){  // middle including left border, graph and right border
                // left border
                Ticks(border: settings.border, alignment: .leading, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, scale: scale, elements: visibleElements, labelStyle: settings.tickLabelStyle)
                    .frame(width: settings.border)
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
                }.border(.white)

                // right border
                Ticks(border: settings.border, alignment: .trailing, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, scale: scale, elements: visibleElements, labelStyle: settings.tickLabelStyle)
                    .frame(width: settings.border)
            }

            HStack(alignment: .bottom, spacing:0){  // bottom border
                // bottom left corner
                Corner(border: settings.border)
                // bottom tick marks
                Ticks(border: settings.border, alignment: .bottom, rangeBelow: scale.lowestRatioNormalized, rangeAbove: scale.highestRatioNormalized, scale: scale, elements: visibleElements, labelStyle: settings.tickLabelStyle)
                    .frame(height: settings.border)
                // bottom right corner
                Corner(border: settings.border)
            }
        }
    }
}

// The same "which scale degrees are visible right now" filter as Graph's own grid-line drawing
// below (Tetrads.elementsPairing bracketed/snapped around the current Z) - factored out as a
// plain function so Ticks (border ratio labels) can honor "Filter Grid to Z" too, without also
// duplicating Graph's per-line fade-weight logic, which a border label doesn't need (a label is
// either shown or not, no fading). Elements are deduped by valueNormalized since a degree valid
// at both bracketing Z keys would otherwise appear (and be labelled) twice.
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
    var border:Double
    
    var body: some View {
        
        Rectangle()
            .fill(.clear)
            .frame(width:border, height: border)
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
