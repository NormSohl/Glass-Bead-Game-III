//
//  GraphView.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/10/22.
//

import SwiftUI

struct GraphView: View {
    //@ObservedObject var settings: AppSettings
    var scale: Scale
    //var geo:GeometryProxy
    var border:Double

    var body: some View {        
        // graph is the size of the view less the left and right border
        //let graphWidth = geo.size.width - border - border
        //let graphHeight = geo.size.height - border - border
        
        VStack(alignment: .leading, spacing:0){// group of all graph elements
            
            HStack(alignment: .top, spacing:0){  // top border
                // top left corner
                Rectangle()
                    .fill(.clear)
                    .frame(width:border, height: border)
                
                // top border
                Rectangle()
                    .fill(.clear)
                    .frame(height: border)
    
                // top right corner
                Rectangle()
                    .fill(.clear)
                    .frame(width:border, height: border)
            }
            
            HStack(alignment: .center, spacing:0){  // middle including left border, graph and right border
                // left border
                Rectangle()
                    .fill(.clear)
                    .frame(width:border)
                
                // graph
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

                // right border
                Rectangle()
                    .fill(.clear)
                    .frame(width:border)
            }
            
            HStack(alignment: .bottom, spacing:0){  // bottom border
                // bottom left corner
                Rectangle()
                    .fill(.clear)
                    .frame(width:border, height: border)
                
                // bottom border
                Rectangle()
                    .fill(.clear)
                    .frame(height: border)
    
                // bottom right corner
                Rectangle()
                    .fill(.clear)
                    .frame(width:border, height: border)
            }
        }
        // draw graph
        /*
        Path { path in
            for interval in scale.scale {
                
                // Horizontal lines
                let tempHeight = geo.size.height - ((graphHeight * interval.valueNormalized) + border)
                path.move(to: CGPoint (x: border, y: tempHeight))
                path.addLine(to: CGPoint(x: graphWidth + border, y: tempHeight))
                
                //vertical lines
                let tempWidth = graphWidth * interval.valueNormalized
                path.move(to: CGPoint (x:tempWidth + border, y: border))
                path.addLine(to: CGPoint(x:tempWidth + border, y: graphHeight + border ))
            }
        }
        .stroke(.white, lineWidth: 1)
         */
    }
}
