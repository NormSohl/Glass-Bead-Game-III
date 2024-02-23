////
////  Midi.swift - obsolete
////  Glass Bead Game
////
////  Created by Norman Sohl on 6/20/22.
////
//
//import Foundation
//import AVFoundation
//import AVFAudio
//
//class MIDIUtil{
//
//    let engine = AVAudioEngine()
//    let sampler = AVAudioUnitSampler()
//    let melodicBank = UInt8(kAUSampler_DefaultMelodicBankMSB)
//    let defaultBankLSB = UInt8(kAUSampler_DefaultBankLSB)
//    let gmMarimba = UInt8(12)
//    let gmHarpsichord = UInt8(6)
//    //let gmHarpsichord = UInt8(0)
//
//    init(){
//
//        let mixer = engine.mainMixerNode
//        engine.attach(sampler)
//        engine.connect(sampler, to: mixer, format:mixer.outputFormat(forBus:0))
//        playNote()
//    }
//
//    func loadPatch(gmpatch:UInt8, channel:UInt8 = 0) {
//
//        guard let soundbank =
//                Bundle.main.url(forResource: "GeneralUser GS MuseScore v1.442", withExtension: "sf2")
//            else {
//                print("could not read sound font")
//                return
//        }
//
//        do {
//            try sampler.loadSoundBankInstrument(at: soundbank, program:gmpatch,
//                bankMSB: melodicBank, bankLSB: defaultBankLSB)
//
//        } catch let error as NSError {
//            print("\(error.localizedDescription)")
//            return
//        }
//
//        self.sampler.sendProgramChange(gmpatch, bankMSB: melodicBank, bankLSB: defaultBankLSB, onChannel: channel)
//    }
//
//    func playNote(){
//        loadPatch(gmpatch: gmHarpsichord)
//        // play middle C, mezzo forte on MIDI channel 0
//        self.sampler.startNote(60, withVelocity: 64, onChannel: 0)
//
//        // in another action
//        self.sampler.stopNote(60, onChannel: 0)
//    }
//}
