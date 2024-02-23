//
//  Scale.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/9/22.
//

import Foundation

//object to contain the ratios that make up the scale
struct ScaleElement{
    var numerator = 0
    var denominator = 0
    var value = 0.0                 //Numerator divided by denomonator
    var valueNormalized = 0.00
    var valueNormalizedCents = 0.0
    
    // range for hit test - what is the middle point between this scale element and the one above and below?
    var upperBounds = 0.0
    var lowerBounds = 0.0
    
    
    init(numerator:Int,denominator:Int){
        self.numerator = numerator
        self.denominator = denominator
        
        // calculate ratio decimal value
        self.value = (Double (numerator) / Double(denominator))
        
        // calculate normalized linear scale
        self.valueNormalized = log(value) / log(2)
        
        // calculate ratio value in cents (1200 over 2)
        self.valueNormalizedCents = 1200 * self.valueNormalized
    }
}

struct Scale {
    //empty object to contain calculated scale
    var scale: [ ScaleElement ] = []
    var limit = 0
    
    init (Limit:Int) {
        limit = Limit
        for x in 1...limit {
            for y in 1...x {
                let Element = ScaleElement (numerator: x, denominator: y)
                scale.append(Element)
            }
        }
        // limit scale to the octave
        scale = scale.filter({$0.value <= 2})
        
        // sort the scale
        scale = scale.sorted(by:{ $0.value < $1.value})
        
        // remove duplicates
        // sadly there is no api for this specific task. It is complicated by the fact that we keep changing the index by deleting items. Because of this I used explicit loops where I controlled the incrementing of the indexes.
        var x = 0
        var y = 1
        while (x < scale.count){
            y = x+1
            while (y < scale.count) {
                if scale[x].value == scale[y].value {
                    //print ("scale element ",scale[y].value, " at ", y, " to be removed")
                    scale.remove(at: y)
                }
                else {
                    y += 1
                }
            }
            x += 1
        }
        // calculate the hit test range
        for x in 0...scale.count-1 {
            //print(scale[x])
            if x == 0 {
                // the first scale element does not have a lower bounds beyond its own valueNormalized since there is no element lower than it in the list
                scale[x].lowerBounds = scale[x].valueNormalized
            }else{
                var distance:Double
                distance = scale[x].valueNormalized
                distance = distance - scale[x-1].valueNormalized
                distance = distance / 2
                // top of hit test range for previous scale element
                scale[x-1].upperBounds = scale[x-1].valueNormalized + distance
                // bottom of hit test range for this element
                scale[x].lowerBounds = scale[x].valueNormalized - distance
                //print(scale[x].lowerBounds, "==", scale[x-1].upperBounds)
            }
            //print(scale[x])
            // and do the final upper bounds which is set to the valueNormalized since there is no higher scale element in the list.  Similar to the first scale element
        }
        scale[scale.count-1].upperBounds = scale[scale.count-1].valueNormalized
        //print(scale)
    }
}
