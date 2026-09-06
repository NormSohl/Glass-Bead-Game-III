//
//  Audio.swift
//  Glass Bead Game III
//
//  Created by Norman Sohl on 7/2/22.
//

import Foundation
import AVFoundation

public class Audio {
    // manage debug audio trace
    let audioTrace = false

    // AV components
    let engine: AVAudioEngine
    let mainMixer: AVAudioMixerNode
    let output: AVAudioOutputNode
    let outputFormat: AVAudioFormat
    let inputFormat: AVAudioFormat
    let echo = AVAudioUnitDelay()

    public var triad = Triad()

    // Set once the sequencer exists (SequencerState.init) - advanced one sample at a time from
    // inside the render callback below, ahead of reading triad.getTriadValue(), so score
    // playback pushes its own pitch/amplitude into the same triad live touch already drives.
    // nil (the default, before any sequencer exists, and always true when the sequencer panel
    // has never been opened) makes the callback behave exactly as it always has.
    public var scorePlayer: ScorePlayer?

    // variables for synthesis of signal
    public var sampleRate: Double

    public init(){
        if audioTrace {print("Audio init")}
        // create the nodes for the audio chain
        engine = AVAudioEngine()
        mainMixer = engine.mainMixerNode
        output = engine.outputNode // gets the singleton for the default AVAudioOutputNode, as set in OS audio options
        //When rendering to and from an audio device in macOS, AVAudioInputNode and AVAudioOutputNode communicate with the system’s default input and output devices.
        // create structures for format
        outputFormat = output.inputFormat(forBus: 0) //An AVAudioNodeBus represents a bus as a zero-based index. AVAudioNode objects potentially have multiple input and output buss0es.
        sampleRate = (outputFormat.sampleRate)
        // Stereo now - Triad.getTriadValue() returns a panned (left, right) pair (root/X/Y/Z
        // each fixed across the stereo field - see Triad.swift's own pan-gain comment), not one
        // mono value duplicated onto every channel. The old channels: 1 here (with its own
        // "changing this to 2 appears to have no impact" comment) was never actually an
        // AVAudioEngine limitation - the render loop below used to write the identical mono
        // value into every channel buffer regardless of channel count, which is why bumping
        // this alone never did anything.
        inputFormat = AVAudioFormat(commonFormat: outputFormat.commonFormat,
                                    sampleRate: outputFormat.sampleRate,
                                    channels: 2,
                                    interleaved: outputFormat.isInterleaved)!
        triad.setTriadSampleRate(sampleRate: outputFormat.sampleRate)

        // create source node
        let srcNode = AVAudioSourceNode {_, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // inputFormat above is always non-interleaved (matches outputFormat.isInterleaved,
            // which - like virtually all AVAudioEngine formats - is false), so channels: 2
            // guarantees exactly two separate buffers here, one per channel.
            guard ablPointer.count >= 2 else { return noErr }
            let leftBuffer = UnsafeMutableBufferPointer<Float>(ablPointer[0])
            let rightBuffer = UnsafeMutableBufferPointer<Float>(ablPointer[1])

            for frame in 0..<Int(frameCount) {

                self.scorePlayer?.advance()

                let stereo = self.triad.getTriadValue()

                // Advance the phase for the next frame.
                self.triad.incrementTriadPhase()

                leftBuffer[frame] = Float(stereo.left)
                rightBuffer[frame] = Float(stereo.right)
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
    
    public func startAudio(amp: Float){
        if self.mainMixer.outputVolume == 0 {
            self.mainMixer.outputVolume = amp
            if audioTrace { print("Audio: startAudio: mainMixer.outputVolume = \(mainMixer.outputVolume)")}
        }
    }

    public func stopAudio(){
        self.mainMixer.outputVolume = 0.0
            if audioTrace {print("Audio: stopAudio: mainMixer.outputVolume = \(mainMixer.outputVolume)")}
    }
}
