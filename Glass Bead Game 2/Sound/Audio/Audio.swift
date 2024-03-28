//
//  File.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 7/2/22.
//

import Foundation
import AVFoundation
//import AudioToolbox

class Audio {
    
    // AV components
    let engine: AVAudioEngine
    let mainMixer: AVAudioMixerNode
    let output: AVAudioOutputNode
    let outputFormat: AVAudioFormat
    let inputFormat: AVAudioFormat
    let echo = AVAudioUnitDelay()
    
    var triad = Triad()
    var testAudio = TestAudio()
    
    // variables for systhesis of signal    var triad = Triad(sampleRate: 44100)
    var sampleRate: Double
    
    init(){
        print("Audio init")
        // create the nodes for the audio chain
        engine = AVAudioEngine()
        mainMixer = engine.mainMixerNode
        output = engine.outputNode // gets the singleton for the default AVAudioOutputNode, as set in OS audio options
        //print("Audio: init: outputNode: componentName = \(String(describing: output.auAudioUnit.componentName))")  //Apple: AudioDeviceOutput
        //print("Audio: init: outputNode: device ID = \(output.auAudioUnit.deviceID)")
        //print("Audio: init: outputNode: audioUnitName = \(String(describing: output.auAudioUnit.audioUnitName))")


        //When rendering to and from an audio device in macOS, AVAudioInputNode and AVAudioOutputNode communicate with the system’s default input and output devices.
        // create structures for format
        outputFormat = output.inputFormat(forBus: 0) //An AVAudioNodeBus represents a bus as a zero-based index. AVAudioNode objects potentially have multiple input and output buss0es.
        sampleRate = (outputFormat.sampleRate)
        //print("Audio: init: outputFormat.sampleRate = \(outputFormat.sampleRate)")
        //print("Audio: init: outputFormat.commonFormat = \(outputFormat.commonFormat)")  // this appears to be 1,  a float32, 4 bits of storage
        //print("Audio: init: outputFormat.channelCount = \(outputFormat.channelCount)")
        //print("Audio: init: outputFormat.isInterleaved = \(outputFormat.isInterleaved)")
        
        // Use the output format for the input, but reduce the channel count to 1.
        inputFormat = AVAudioFormat(commonFormat: outputFormat.commonFormat,
                                    sampleRate: outputFormat.sampleRate,
                                    channels: 1, // changing this to 2 appears to have no impact
                                    interleaved: outputFormat.isInterleaved)!
        
        //print("Audio: init: inputFormat.sampleRate = \(inputFormat.sampleRate)")
        //print("Audio: init: inputFormat.commonFormat = \(inputFormat.commonFormat)")  // this appears to be 1,  pcmFormatFloat32, 4 bits of storage
        //print("Audio: init: inputFormat.channelCount = \(inputFormat.channelCount)")
        //print("Audio: init: inputFormat.isInterleaved = \(inputFormat.isInterleaved)")
        
        triad.setTriadSampleRate(sampleRate: outputFormat.sampleRate)
        
        // create source node
        let srcNode = AVAudioSourceNode {_, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                
                let value = self.triad.getTriadValue()
                //var value = 0.0
                
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
        //print("Audio: init: mainMixer.outputVolume = \(mainMixer.outputVolume)")
        startEngine()
        //let numOut = output.numberOfOutputs
        //let description = output.description
        //print("Description = \(description), number of outputs = \(numOut)")
        
    }
    
    deinit{
        //print("Audio: deinit called")
        stopEngine()
        // this appears never to be called. Why?
    }
    
    func startEngine (){
        do {
            //print("Audio: startEngine")
            try engine.start()
            CFRunLoopRunInMode(.defaultMode, // mode: Docs are not clear about what this does. .commonMode trigers invalidMode
                               0, //CFTimeInterval(duration), // seconds: The length of time to run the run loop. If 0, only one pass is made through the run loop before returning
                               true //returnAfterSourceHandled: A flag indicating whether the run loop should exit after processing one source. If false, the run loop continues processing events until seconds has passed.
            )
            
        } catch {
            print("Could not start engine: \(error)")
        }
        //getOutputDevices()
    }
    
    func stopEngine(){
        engine.stop()
        // print("Audio: stopEngine")
    }
    
    func startAudio(amp: Float){
        if self.mainMixer.outputVolume == 0 {
            self.mainMixer.outputVolume = amp
            //print("Audio: startAudio: mainMixer.outputVolume = \(mainMixer.outputVolume)")
        }
    }
    
    func stopAudio(){
        self.mainMixer.outputVolume = 0.0
        //print("Audio: stopAudio: mainMixer.outputVolume = \(mainMixer.outputVolume)")
    }
    
    //func getOutputDevices(){
        //listDevices()
        //testAudio.test()
    //}
    
    func listDevices(){
        // from: https://gist.github.com/glaurent/b4e9a2a1bc5223977df428e03d465560
        // this works, but I can't figure how to query number of channels
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var propertySize:UInt32 = 0
        if AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize) == noErr {
            
            // get device ids
            let numDevices = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
            var deviceIDs = [AudioDeviceID](repeating: 0, count: numDevices)
            if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceIDs) == noErr {
                var deviceAddress = AudioObjectPropertyAddress()
                var deviceNameCString = [CChar](repeating:0, count: 64)
                var manufacturerNameCString = [CChar](repeating:0, count: 64)
                
                // loop through device IDs
                for idx in (0..<numDevices) {
                    
                    // get device name
                    propertySize = UInt32(MemoryLayout<CChar>.size * 64)
                    deviceAddress.mSelector = kAudioDevicePropertyDeviceName
                    deviceAddress.mScope = kAudioObjectPropertyScopeGlobal
                    deviceAddress.mElement = kAudioObjectPropertyElementMain
                    if AudioObjectGetPropertyData(deviceIDs[idx], &deviceAddress, 0, nil, &propertySize, &deviceNameCString) == noErr {
                        
                        // get device Manufacturer
                        let deviceName = String(cString:deviceNameCString)
                        propertySize = UInt32(MemoryLayout<CChar>.size * 64)
                        deviceAddress.mSelector = kAudioDevicePropertyDeviceManufacturer
                        deviceAddress.mScope = kAudioObjectPropertyScopeGlobal
                        deviceAddress.mElement = kAudioObjectPropertyElementMain
                        if (AudioObjectGetPropertyData(deviceIDs[idx], &deviceAddress, 0, nil, &propertySize, &manufacturerNameCString) == noErr) {
                            
                            // get device ID string
                            let manufacturerName = String(cString:manufacturerNameCString)
                            var uidString = "" as CFString
                            propertySize = UInt32(MemoryLayout.size(ofValue: uidString))
                            deviceAddress.mSelector = kAudioDevicePropertyDeviceUID
                            deviceAddress.mScope = kAudioObjectPropertyScopeGlobal
                            deviceAddress.mElement = kAudioObjectPropertyElementMain
                            if (AudioObjectGetPropertyData(deviceIDs[idx], &deviceAddress, 0, nil, &propertySize, &uidString) == noErr) {
                                
                                // print device name, device manufacturer and device ID
                                print("device \(deviceName)\nby \(manufacturerName)\nid \(uidString)\n\n")
                                
                                //kAudioEndPointOutputChannelsKey
                                
                                
                            }
                        }
                    }
                } // end loop through device IDs
            }
        }
    }
    
    
    
    
    
    
    
    
    /*
     //var devices:Array<AudioDeviceID> = Array()
     //devices = availableDevices()
     //for device in devices{
     //    print("Avaliable output device = \(device.description)")
     //}
     
     var status =  AudioObjectGetPropertyData(
     inObjectID: AudioObjectID,
     inAddress: UnsafePointer<AudioObjectPropertyAddress>,
     inQualifierDataSize: UInt32,
     inQualifierData: UnsafeRawPointer?,
     ioDataSize: UnsafeMutablePointer<UInt32>,
     outData: UnsafeMutableRawPointer
     }
     */
    
    //status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize, audioDevices);
    /*
     private func availableDevices() -> Array<AudioDeviceID> {
     var property: AudioObjectPropertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
     var dataSize:UInt32 = 0
     let status: OSStatus = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &dataSize)
     var devices:Array<AudioDeviceID> = Array()
     if status != kAudioHardwareNoError {
     devices = Array()
     } else {
     let deviceCount: Int = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
     var foundDevices: Array<AudioDeviceID> = Array<AudioDeviceID>(repeating: 0, count: deviceCount)
     foundDevices.withUnsafeMutableBufferPointer { ( item: inout UnsafeMutableBufferPointer<AudioDeviceID>) -> () in
     let error: OSStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &dataSize, item.baseAddress!)
     if error != kAudioHardwareNoError { print("each device ID Get Error: \(error)") }
     }// end withUnsafeMutableBufferPointer
     devices = Array(foundDevices)
     }// end if
     
     return devices
     }// end availableDevices
     */
}
