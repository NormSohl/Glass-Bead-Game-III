//
//  GraphView.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/10/22.
//

import SwiftUI

struct GraphView: View {
    let scale: Scale
    let diamonds:Diamonds
    let settings: AppSettings
    
    var body: some View {
        
        VStack(alignment: .leading, spacing:0){// group of all graph elements
            
            HStack(alignment: .top, spacing:0){  // top border
                // top left corner
                Corner(border: settings.border)
                // top tick marks
                Ticks(border: settings.border, alignment: .top).frame(height: settings.border)
                // top right corner
                Corner(border: settings.border)
            }
            
            HStack(alignment: .center, spacing:0){  // middle including left border, graph and right border
                // left border
                Ticks(border: settings.border, alignment: .leading).frame(width: settings.border)
                
                ZStack(){
                    // graph
                    Graph(scale: scale)
                    DiamondView(diamonds: diamonds,
                                settings: settings)
                    
                    HitTestView(scale:scale, settings: settings)
                }.border(.orange)

                // right border
                Ticks(border: settings.border, alignment: .trailing).frame(width: settings.border)
            }
            
            HStack(alignment: .bottom, spacing:0){  // bottom border
                // bottom left corner
                Corner(border: settings.border)
                // bottom tick marks
                Ticks(border: settings.border, alignment: .bottom).frame(height: settings.border)
                // bottom right corner
                Corner(border: settings.border)
            }
        }
    }
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
    
    var body: some View {
        Canvas(){context, size in
            context.stroke(
                Path { path in
                    for interval in scale.scale {
                        
                        // Horizontal lines
                        let tempHeight = size.height - (size.height * (interval.valueNormalized / scale.highestRatioNormalized))
                        path.move(to: CGPoint (x: 0, y: tempHeight))
                        path.addLine(to: CGPoint(x: size.width, y: tempHeight))
                        
                        //vertical lines
                        let tempWidth = size.width * (interval.valueNormalized / scale.highestRatioNormalized)
                        path.move(to: CGPoint (x:tempWidth, y:0))
                        path.addLine(to: CGPoint(x:tempWidth, y: size.height))
                    }
                },
                with: .color(.gray)
            )
        }
    }
}
