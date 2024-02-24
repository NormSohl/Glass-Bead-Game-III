//
//  GraphView.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/10/22.
//

import SwiftUI

struct GraphView: View {
    var scale: Scale
    var diamonds:Diamonds
    var border:Double

    var body: some View {
        
        VStack(alignment: .leading, spacing:0){// group of all graph elements
            
            HStack(alignment: .top, spacing:0){  // top border
                // top left corner
                Corner(border: border)
                // top tick marks
                Ticks(border: border, alignment: .top).frame(height: border)
                // top right corner
                Corner(border: border)
            }
            
            HStack(alignment: .center, spacing:0){  // middle including left border, graph and right border
                // left border
                Ticks(border: border, alignment: .leading).frame(width: border)
                
                ZStack(){
                    // graph
                    Graph(border: border, scale: scale)
                    DiamondView(showDiamonds: true, diamonds: diamonds, border: border)
                }

                // right border
                Ticks(border: border, alignment: .trailing).frame(width: border)
            }
            
            HStack(alignment: .bottom, spacing:0){  // bottom border
                // bottom left corner
                Corner(border: border)
                // bottom tick marks
                Ticks(border: border, alignment: .bottom).frame(height: border)
                // bottom right corner
                Corner(border: border)
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
    var border:Double
    var scale: Scale
    
    var body: some View {
        Canvas(){context, size in
            context.stroke(
                Path { path in
                    for interval in scale.scale {
                        
                        // Horizontal lines
                        let tempHeight = size.height - ((size.height * interval.valueNormalized))
                        path.move(to: CGPoint (x: 0, y: tempHeight))
                        path.addLine(to: CGPoint(x: size.width, y: tempHeight))
                        
                        //vertical lines
                        let tempWidth = size.width * interval.valueNormalized
                        path.move(to: CGPoint (x:tempWidth, y:0))
                        path.addLine(to: CGPoint(x:tempWidth, y: size.height))
                    }
                },
                with: .color(.white)
            )
        }
    }
}
    
enum Alignment {
    case top
    case bottom
    case leading
    case trailing
}

// tick marks
struct Ticks: View {
    var border:Double
    var alignment: Alignment
    
    var body: some View {
        Canvas(){ context, size in
            let whiteTicks: Set = [0,2,4,5,7,9,11,12] // C, D, E, F, G, A, B, C
            context.stroke(
                Path { path in
                    for tick in 0...12 {
                        if whiteTicks.contains(tick){
                            switch alignment {
                            case .leading:
                                let tickLocation = size.height - (((size.height) / 12) * Double(tick))
                                path.move(to: CGPoint (x: 1, y: tickLocation))
                                path.addLine(to: CGPoint(x: 10, y: tickLocation))
                                
                            case .trailing:
                                let tickLocation = size.height - (((size.height) / 12) * Double(tick))
                                path.move(to: CGPoint (x: border - 10, y: tickLocation))
                                path.addLine(to: CGPoint(x: border - 1, y: tickLocation))
                                
                            case .top:
                                let tickLocation = (size.width / 12) * Double(tick)
                                path.move(to: CGPoint (x: tickLocation, y: 1))
                                path.addLine(to: CGPoint(x: tickLocation, y:10))
                                
                            case .bottom:
                                let tickLocation = ((size.width) / 12) * Double(tick)
                                path.move(to: CGPoint (x: tickLocation, y: border - 1))
                                path.addLine(to: CGPoint(x: tickLocation, y: border - 10))
                            }
                        }
                    }
                },
                with: .color(.white),
                lineWidth: 2
            )
            context.stroke(
                Path { path in
                    for tick in 0...12 {
                        if !whiteTicks.contains(tick)
                        {
                            switch alignment {
                            case .leading:
                                let tickLocation = size.height - (((size.height) / 12) * Double(tick))
                                path.move(to: CGPoint (x: 1, y: tickLocation))
                                path.addLine(to: CGPoint(x: 10, y: tickLocation))
                                
                            case .trailing:
                                let tickLocation = size.height - (((size.height) / 12) * Double(tick))
                                path.move(to: CGPoint (x: border - 10, y: tickLocation))
                                path.addLine(to: CGPoint(x: border - 1, y: tickLocation))
                                
                            case .top:
                                let tickLocation = (size.width / 12) * Double(tick)
                                path.move(to: CGPoint (x: tickLocation, y: 1))
                                path.addLine(to: CGPoint(x: tickLocation, y:10))
                                
                            case .bottom:
                                let tickLocation = (size.width / 12) * Double(tick)
                                path.move(to: CGPoint (x: tickLocation, y: border - 1))
                                path.addLine(to: CGPoint(x: tickLocation, y: border - 10))
                            }
                        }
                    }
                },
                with: .color(.blue),
                lineWidth: 2
            )
        }
    }
}
