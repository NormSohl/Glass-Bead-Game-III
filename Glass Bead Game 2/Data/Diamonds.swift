//
//  Diamonds.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 6/12/22.
//

import Foundation

struct DiamondElement{
    let xElement: ScaleElement
    let yElement: ScaleElement
    let locationNormalized: CGPoint
    let sizeNormalized: Double
    
    init (x:ScaleElement, y:ScaleElement, sizeNorm:Double){
        yElement = y
        xElement = x
        sizeNormalized = sizeNorm
        locationNormalized = CGPoint(x: xElement.valueNormalized, y: yElement.valueNormalized)
    }
}

struct Diamonds {
    var DiamondList:[DiamondElement] = []
    init (scale:Scale){
        for x in scale.scale {
            for y in scale.scale {
                let interval = abs(x.valueNormalized - y.valueNormalized)
                for z in scale.scale {
                    // does interval between moving tones match a scale element?
                    // first round the values because there are tiny differences
                    let roundedInterval = round(interval*100000)/100000
                    let roundedZNorm = round(z.valueNormalized*100000)/100000
                    
                    //print (x.numerator, "/", x.denominator, "to", y.numerator, "/", y.denominator,"interval:", interval, "z.valueNormalized", z.valueNormalized)
                    
                    if roundedInterval == roundedZNorm {
                        //print ("interval detected")

                        // calculate size based on largest number in ratios
                        var sizeRaw = x.numerator
                        if sizeRaw < x.denominator {sizeRaw = x.denominator}
                        
                        if sizeRaw < y.numerator {sizeRaw = y.numerator}
                        if sizeRaw < y.denominator {sizeRaw = y.denominator}
                        
                        if sizeRaw < z.numerator {sizeRaw = z.numerator}
                        if sizeRaw < z.denominator {sizeRaw = z.denominator}
                        
                        // normalize size
                        var sizeNorm = Double(sizeRaw) / Double(scale.limit)
                        sizeNorm = 1 - sizeNorm

                        let element = DiamondElement (x: x, y: y, sizeNorm: Double(sizeNorm))
                        DiamondList.append(element)
                        //print ("diamond added: x = ", element.xElement.numerator, "/", element.xElement.denominator, " y = ",element.yElement.numerator, "/", element.yElement.denominator, " interval = ",interval, " size = ", sizeNorm)
                        
                        break
                    }
                }
            }
        }
    }
}
