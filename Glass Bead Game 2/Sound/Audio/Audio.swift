//
//  File.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 7/2/22.
//

import Foundation
import AVFoundation

class Audio {
    // manage debug audio trace
    let audioTrace = false
    
    // AV components
    let engine: AVAudioEngine
    let mainMixer: AVAudioMixerNode
    let output: AVAudioOutputNode
    let outputFormat: AVAudioFormat
    let inputFormat: AVAudioFormat
    let echo = AVAudioUnitDelay()
    
    var triad = Triad()
    
    // variables for systhesis of signal
    var sampleRate: Double
    
    init(){
        if audioTrace {print("Audio init")}
        // create the nodes for the audio chain
        engine = AVAudioEngine()
        mainMixer = engine.mainMixerNode
        output = engine.outputNode // gets the singleton for the default AVAudioOutputNode, as set in OS audio options
        //When rendering to and from an audio device in macOS, AVAudioInputNode and AVAudioOutputNode communicate with the system’s default input and output devices.
        // create structures for format
        outputFormat = output.inputFormat(forBus: 0) //An AVAudioNodeBus represents a bus as a zero-based index. AVAudioNode objects potentially have multiple input and output buss0es.
        sampleRate = (outputFormat.sampleRate)
        // Use the output format for the input, but reduce the channel count to 1.
        inputFormat = AVAudioFormat(commonFormat: outputFormat.commonFormat,
                                    sampleRate: outputFormat.sampleRate,
                                    channels: 1, // changing this to 2 appears to have no impact
                                    interleaved: outputFormat.isInterleaved)!
        triad.setTriadSampleRate(sampleRate: outputFormat.sampleRate)
        
        // create source node
        let srcNode = AVAudioSourceNode {_, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                
                let value = self.triad.getTriadValue()
                
                // Advance the phase for the next frame.
                self.triad.incrementTriadPhase()
                
                // Set the same value on all channels (due to the inputFormat, there's only one channel though).
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)  // this appears to be putting a simple 16 bit float into the actual data stream. I think Float and Float32 are the same on modern systems. The commonFormat above is set to 1 which is pcmFormatFloat32, otherwise known as float. So all is good. value from note is actually double, so see what that gets us.
                    buf[frame] = Float(value)
                }
            }
            return noErr
        }
        
        // wire up the nodes for the audio chain
        engine.attach(srcNode)
        engine.connect(srcNode, to: mainMixer, format: inputFormat)
        engine.connect(mainMixer, to: output, format: outputFormat)
        mainMixer.outputVolume = 0.0
        startEngine()
    }
    
    deinit{
        stopEngine()
        // this appears never to be called. Why?
    }
    
    func startEngine (){
        do {
            if audioTrace {print("Audio: startEngine")}
            try engine.start()
            CFRunLoopRunInMode(.defaultMode, // mode: Docs are not clear about what this does. .commonMode trigers invalidMode
                               0, //CFTimeInterval(duration), // seconds: The length of time to run the run loop. If 0, only one pass is made through the run loop before returning
                               true //returnAfterSourceHandled: A flag indicating whether the run loop should exit after processing one source. If false, the run loop continues processing events until seconds has passed.
            )
            
        } catch {
            if audioTrace {print("Could not start engine: \(error)")}
        }
    }
    
    func stopEngine(){
        engine.stop()
            if audioTrace { print("Audio: stopEngine")}
    }
    
    func startAudio(amp: Float){
        if self.mainMixer.outputVolume == 0 {
            self.mainMixer.outputVolume = amp
            if audioTrace { print("Audio: startAudio: mainMixer.outputVolume = \(mainMixer.outputVolume)")}
        }
    }
    
    func stopAudio(){
        self.mainMixer.outputVolume = 0.0
            if audioTrace {print("Audio: stopAudio: mainMixer.outputVolume = \(mainMixer.outputVolume)")}
    }
}
