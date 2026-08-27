//
//  Diamonds.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/12/22.
//

import Foundation
import CoreGraphics

struct DiamondElement{
    let xElement: ScaleElement
    let yElement: ScaleElement
    let zElement: ScaleElement
    let locationNormalized: CGPoint
    let sizeNormalized: Double
    var mydissonance = 0.0
    
    init (x:ScaleElement, y:ScaleElement, z:ScaleElement, sizeNorm:Double, dissonance:Double, highestRatioNormalized:Double){
        self.yElement = y
        self.xElement = x
        self.zElement = z
        sizeNormalized = sizeNorm
        locationNormalized = CGPoint(x: xElement.valueNormalized / highestRatioNormalized, y: yElement.valueNormalized)
        mydissonance = dissonance
    }
}

struct Diamonds {
    var diamondList:[DiamondElement] = []
    var scale: Scale
    
    init (scale:Scale){
        self.scale = scale
        for x in scale.scale {
            for y in scale.scale {
                let interval = abs(x.valueNormalized - y.valueNormalized)
                for z in scale.scale {
                    // check that moving tones also are consonant
                    let roundedInterval = round(interval*100000)/100000
                    let roundedZNorm = round(z.valueNormalized*100000)/100000
                    if roundedInterval == roundedZNorm {
                        var dissonance = 0.0
                        if x.dissonance == 1.0 {dissonance += 1.0} //interval is 1/1, tag dissonance indicating a 1/1 in the diamond
                        //print("X: ",dissonance, x.dissonance)
                        if y.dissonance == 1.0 {dissonance += 1.0} //interval is 1/1, tag dissonance indicating a 1/1 in the diamond
                        //print("Y: ",dissonance, y.dissonance)
                        if z.dissonance == 1.0 {dissonance += 1.0} //interval is 1/1, tag dissonance indicating a 1/1 in the diamond
                        //print("Z: ",dissonance, z.dissonance)

                        // calculate size based on largest number in ratios
                        // this appears to work for ratios abouve and below 1/1, where numerator is greater than denominator such as 2/1, and where the oppisite is true such as 1/2
                        var sizeRaw = x.numerator
                        if sizeRaw < x.denominator {sizeRaw = x.denominator}
                        
                        if sizeRaw < y.numerator {sizeRaw = y.numerator}
                        if sizeRaw < y.denominator {sizeRaw = y.denominator}
                        
                        if sizeRaw < z.numerator {sizeRaw = z.numerator}
                        if sizeRaw < z.denominator {sizeRaw = z.denominator}
                        
                        // normalize size
                        var sizeNorm = Double(sizeRaw) / Double(scale.limit)
                        
                        // invert size because the higher the element, the less power it has (in a perfect harmonic based musical tone)
                        sizeNorm = 1 - sizeNorm

                        let element = DiamondElement (x: x, y: y, z: z, sizeNorm: Double(sizeNorm), dissonance: dissonance, highestRatioNormalized: scale.highestRatioNormalized)
                        diamondList.append(element)
                       // print ("diamond added: x = ", element.xElement.numerator, "/", element.xElement.denominator,
                       //        " y = ",element.yElement.numerator,"/", element.yElement.denominator,
                       //        " z = ",element.zElement.numerator, "/", element.zElement.denominator,
                       //        " interval = ",interval,
                       //        " size = ", sizeNorm,
                       //        "dissonance = ", dissonance)
                        break
                    }
                }
            }
        }
    }
}
