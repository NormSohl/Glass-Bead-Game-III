//
//  Scale.swift
//  GBGCore
//
//  Created by Norman Sohl on 6/9/22.
//

import Foundation

//object to contain the ratios that make up the scale
struct ScaleElement{
    var numerator = 0
    var denominator = 0
    var value = 0.0  //Numerator divided by denomonator for decimal ratio, log
    var valueNormalized = 0.00 // linear value
    var valueNormalizedCents = 0.0 // limear value converted to cents
    
    // range for hit test - what is the middle point between this scale element and the one above and below?
    var upperBounds = 0.0
    var lowerBounds = 0.0
    var dissonance = 0.0
    
    init(numerator:Int, denominator:Int, highestRatio: Double){
        // ratio
        self.numerator = numerator
        self.denominator = denominator
        
        // ratio decimal value (log)
        self.value = (Double (numerator) / Double(denominator))
        if self.value == 1 {dissonance = 1.0}  // if scale element is 1/1 then dissonance is 1 to indicate unison

        self.valueNormalized = log(value) / log(2)
        
        // linear value of ratio, in cents
        self.valueNormalizedCents = 1200 * self.valueNormalized
    }
}

struct Scale {
    //empty object to contain calculated scale
    var scale: [ ScaleElement ] = []
    var limit = 0
    
    // highest element in scale
    var highestRatio: Double = 0.0
    var highestRatioNormalized:Double = 0.0  // positive value
    
    // lowest element in scale
    var lowestRatio: Double = 0.0
    var lowestRatioNormalized: Double = 0.0  // negative value
    
    // total range of scale between highest and lowest elements. Needed to properly scale the graph to the view size
    var rangeNormalized: Double = 0.0  // positive value
    
    init (limit:Int, highestRatio: Double, lowestRatio:Double) {
        
        // positive
        self.highestRatio = highestRatio
        self.highestRatioNormalized = log(self.highestRatio) / log(2)
        
        // negative
        self.lowestRatio = lowestRatio
        self.lowestRatioNormalized = log(self.lowestRatio) / log(2)
        
        // combine highest and lowest normalized ratios to give the full range of the graph
        self.rangeNormalized = self.highestRatioNormalized - self.lowestRatioNormalized // positive, need to handle negative value for lowest
        
        self.limit = limit
        for x in 1...self.limit {
            for y in 1...self.limit {
                // above 1/1
                let elementUp = ScaleElement (numerator: x, denominator: y, highestRatio: self.highestRatio)
                scale.append(elementUp)

                // below 1/1 (the upside-down)
                let elementDown = ScaleElement (numerator: y, denominator: x, highestRatio: self.lowestRatio)
                scale.append(elementDown)
            }
        }
        // remove scale elements above highestRatio
        scale = scale.filter({$0.value <= highestRatio + 3})  // this allows some out of range values for the diamonds in the upper left and lower right corners, where the ratio of the moving tone is outside of the scale range
        
        // remove scale elements below lowest ratio
        scale = scale.filter({$0.value >= lowestRatio})
        
        // sort the scale
        scale = scale.sorted(by:{ $0.value < $1.value})
        
        // remove duplicates
        // There is no api for this specific task. It is complicated by the fact that we keep changing the index by deleting items. Because of this use explicit loops where we control the incrementing of the indexes.
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
        for x in 0..<scale.count {
            //print("Scale: \(scale[x])")
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
            }
        }
        // and do the final upper bounds which is set to the valueNormalized since there is no higher scale element in the list.  Similar to the first scale element
        scale[scale.count-1].upperBounds = scale[scale.count-1].valueNormalized
        
        //for element in scale {
        //    print("Scale: element = \(element)")
        //}
    }
    
    func convertScaleValueToScreenUnits(
        normalizedValue: Double,
        screenSize: Double
    )->Double{
        // location is a linear value between scale.LowestRatioNormalized and scale.highestRatioNormalized
        // compensate for negative values of Location. This should result in a 0 to scale.rangeNormalized value
        var location = abs(self.lowestRatioNormalized) + normalizedValue
        // reduce to a positive 0 - 1 range
        location = location / self.rangeNormalized
        // InScreenUnits = intervalLocation translated to screen units
        let locationInScreenUnits = screenSize * location
        return locationInScreenUnits
    }
}
