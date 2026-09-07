//
//  TickView.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 2/24/24.
//

import SwiftUI
import GBGCore

// Named distinctly from SwiftUI's own Alignment type, which this file also uses
// implicitly via HStack/VStack elsewhere in the app - same name, different type,
// would otherwise be a trap for whichever Alignment is actually in scope.
enum TickAlignment {
    case top
    case bottom
    case leading
    case trailing
}

// tick marks
struct Ticks: View {
    let border:Double
    let alignment: TickAlignment
    let rangeBelow: Double
    let rangeAbove: Double
    // Only needed for .ratios (the actual ScaleElements to label); .letters ignores it
    // entirely and keeps drawing the fixed 12-EDO grid exactly as before.
    let scale: Scale
    let labelStyle: TickLabelStyle

    var body: some View {
        Canvas(){
            context, size in
            switch labelStyle {
            case .letters:
                drawLetters(context: context, size: size)
            case .ratios:
                drawRatios(context: context, size: size)
            }
        }
    }

    private func drawLetters(context: GraphicsContext, size: CGSize) {
        var tickLocation = 0.0
        var startLocation = CGPoint(x:0.0,y:0.0)
        var endLocation = CGPoint(x:0.0,y:0.0)
        var textLocation = CGPoint(x:0.0,y:0.0)

        // rangeBelow is negative, -1 to 0 for the octave, may be lower or higher. rangeAbove is positive, 0 to 1 for octave, may be lower or higher.
        let range = abs(rangeBelow) + rangeAbove
        let numTicks = 12 * range
        let centerTick = 12 * abs(rangeBelow)

        // Label size tracks the actual space between ticks (the graph's rendered size
        // divided across the same numTicks used for layout above), not a fixed point size -
        // otherwise labels stay tiny on a large window and would overlap on a small one.
        // Capped so it doesn't balloon at extreme zoom; floored so it never disappears.
        let referenceSize = (alignment == .top || alignment == .bottom) ? size.width : size.height
        let tickSpacing = numTicks > 0 ? referenceSize / numTicks : 15
        let fontSize = min(18, max(8, tickSpacing * 0.55))

        for tick in 0...Int(numTicks){
            //deal with edges of view by nudging text and ticks into viewable area
            var nudge = 0.0
            if tick == 0 {nudge = 1.0}
            if tick == Int(numTicks) {nudge = -1.0}
            switch alignment {

            case .leading:
                tickLocation = size.height - (((size.height) / numTicks) * Double(tick))
                startLocation = CGPoint(x: border - 1.0, y: tickLocation-nudge)
                endLocation = CGPoint(x: border - 10.0, y: tickLocation-nudge)
                textLocation = CGPoint(x: endLocation.x-10, y: tickLocation-(nudge*10))

            case .trailing:
                tickLocation = size.height - (((size.height) / numTicks) * Double(tick))
                startLocation = CGPoint(x: 1.0, y: tickLocation-nudge)
                endLocation = CGPoint(x: 10.0, y: tickLocation-nudge)
                textLocation = CGPoint(x: endLocation.x+10, y: endLocation.y-(nudge*10))

            case .top:
                tickLocation = (size.width / numTicks) * Double(tick)
                startLocation = CGPoint(x: tickLocation+nudge, y: border - 1.0)
                endLocation = CGPoint(x: tickLocation+nudge, y: border - 10.0)
                textLocation = CGPoint(x: endLocation.x+(nudge*10), y: endLocation.y - 10)

            case .bottom:
                tickLocation = ((size.width) / numTicks) * Double(tick)
                startLocation = CGPoint(x: tickLocation+nudge, y: 1.0)
                endLocation = CGPoint(x: tickLocation+nudge, y: 10.0)
                textLocation = CGPoint(x: endLocation.x+(nudge*10), y: endLocation.y + 10)
            }

            // draw tick
            let mcolor: Color = .white
            context.stroke(
                Path { path in
                    path.move(to: startLocation)
                    path.addLine(to: endLocation)
                },
                with: .color(mcolor),
                lineWidth: 2
            )

            //Draw Note Name
            let noteNames = ["C","","D","","E","F","","G","","A","","B","C"]
            var myTick = tick - Int(centerTick)
            while myTick < 0 {myTick = myTick + 12}
            while myTick > 12 {myTick = myTick - 12}

            let _ = context.draw(Text(noteNames[myTick]).font(.custom("SFPro", size: fontSize)).foregroundStyle(.white),at: textLocation)
        }
    }

    // One dot + ratio label per scale degree (Scale.scale's own ScaleElements - the exact same
    // ratios Graph draws its grid lines from), positioned by the element's real just-intonation
    // value rather than a fixed 12-EDO spacing, so a label sits level with the line it names.
    // Dots/labels can end up close together wherever the scale itself is dense (high limit,
    // near unison) - kept deliberately small rather than thinned out, per Norm's ask.
    private func drawRatios(context: GraphicsContext, size: CGSize) {
        let elements = scale.scale
        guard !elements.isEmpty else { return }
        let referenceSize = (alignment == .top || alignment == .bottom) ? size.width : size.height
        let fontSize = 9.0
        let dotRadius = 2.0
        let mcolor: Color = .white

        for (index, element) in elements.enumerated() {
            var nudge = 0.0
            if index == 0 { nudge = 1.0 }
            if index == elements.count - 1 { nudge = -1.0 }

            let screenPosition = scale.convertScaleValueToScreenUnits(
                normalizedValue: element.valueNormalized,
                screenSize: referenceSize
            )

            var dotLocation = CGPoint(x: 0, y: 0)
            var textLocation = CGPoint(x: 0, y: 0)
            var textAnchor: UnitPoint = .center

            switch alignment {
            case .leading:
                let tickLocation = size.height - screenPosition
                dotLocation = CGPoint(x: border - 6.0, y: tickLocation - nudge)
                textLocation = CGPoint(x: dotLocation.x - 6, y: dotLocation.y)
                textAnchor = .trailing

            case .trailing:
                let tickLocation = size.height - screenPosition
                dotLocation = CGPoint(x: 6.0, y: tickLocation - nudge)
                textLocation = CGPoint(x: dotLocation.x + 6, y: dotLocation.y)
                textAnchor = .leading

            case .top:
                let tickLocation = screenPosition
                dotLocation = CGPoint(x: tickLocation + nudge, y: border - 6.0)
                textLocation = CGPoint(x: dotLocation.x, y: dotLocation.y - 8)
                textAnchor = .bottom

            case .bottom:
                let tickLocation = screenPosition
                dotLocation = CGPoint(x: tickLocation + nudge, y: 6.0)
                textLocation = CGPoint(x: dotLocation.x, y: dotLocation.y + 8)
                textAnchor = .top
            }

            context.fill(
                Path(ellipseIn: CGRect(
                    x: dotLocation.x - dotRadius, y: dotLocation.y - dotRadius,
                    width: dotRadius * 2, height: dotRadius * 2
                )),
                with: .color(mcolor)
            )

            let label = ratioText(numerator: element.numerator, denominator: element.denominator, fontSize: fontSize, color: mcolor)
            context.draw(label, at: textLocation, anchor: textAnchor)
        }
    }

    // Superscript numerator / slash / subscript denominator, built as one concatenated Text so
    // Canvas can draw it in a single context.draw call - each segment carries its own font size
    // and baseline offset, which SwiftUI's Text concatenation (+) preserves per-segment.
    private func ratioText(numerator: Int, denominator: Int, fontSize: Double, color: Color) -> Text {
        let digitFontSize = fontSize * 0.78
        return Text("\(numerator)")
            .font(.custom("SFPro", size: digitFontSize))
            .baselineOffset(fontSize * 0.32)
            .foregroundStyle(color)
        + Text("/")
            .font(.custom("SFPro", size: fontSize))
            .foregroundStyle(color)
        + Text("\(denominator)")
            .font(.custom("SFPro", size: digitFontSize))
            .baselineOffset(-fontSize * 0.12)
            .foregroundStyle(color)
    }
}
