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
    var geo:GeometryProxy
    var border:Double

    var body: some View {        
        // graph is the size of the view less the left and right border
        let graphWidth = geo.size.width - border - border
        let graphHeight = geo.size.height - border - border
        
        // draw graph
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
    }
}
