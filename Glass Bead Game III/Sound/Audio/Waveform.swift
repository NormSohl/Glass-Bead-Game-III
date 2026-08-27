//
//  Waveform.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 7/10/22.
//

import Foundation

//  This returns a wave based on the phase input value. Phase is in range 0 to twoPi. Return is in range -1 to 1

class WaveForm{
    func getValue(phase: Double) -> Double {
        return 0
    }
}

//Tested and works correctly, returns full range sine
class Sine:WaveForm {
    override func getValue (phase: Double) -> Double {
        return sin(phase)
    }
}

//Tested, does not work correctly. distorted
class Additive:WaveForm {
    // allocate vars outside of loop to improve performance of Additive
    static let limit:Int = 7 //22  Match to scale limit?
    static var total:Double = 0
    static var temp:Double = 0
    override func getValue (phase: Double) -> Double {
        Additive.total = 0
        for partial in 1...Additive.limit {
            Additive.temp = sin(phase * Double(partial))
            Additive.temp /= Double(Additive.limit)  // scale output by
            Additive.total += Additive.temp
        }
        Additive.total /= 2
            return Additive.total
    }
}
    
//    let twoPi = 2 * Float.pi
    
class WhiteNoise:WaveForm {
    override func getValue(phase: Double) -> Double{
        return (Double(arc4random_uniform(UINT32_MAX)) / Double(UINT32_MAX)) * 2 - 1
    }
}

class SawToothUp:WaveForm {
    let twoPi = 2 * Double.pi
    override func getValue(phase: Double)-> Double{          // all harmonics
        return 1.0 - 2.0 * (phase * (1.0 / twoPi))
    }
}

class SawToothDown:WaveForm {
    let twoPi = 2 * Double.pi
    override func getValue(phase: Double) -> Double {
        return 2.0 * ((phase * (1.0 / twoPi)) - 1.0)
    }
}

class SquareWave:WaveForm {
    override func getValue(phase: Double) -> Double {            // odd harmonics, strong high harmonics
        if phase <= Double.pi {
            return 1.0
        } else {
            return -1.0
        }
    }
}

class Triangle:WaveForm {  // does not seem to work?
    let twoPi = 2 * Double.pi
    func triangle (phase: Double) -> Double {         // odd harmonics, drop off with higher numbers
        var value = (2.0 * (phase * (1.0 / twoPi))) - 1.0
        if value < 0.0 {
            value = -value
        }
        return 2.0 * (value - 0.5)
    }
}
