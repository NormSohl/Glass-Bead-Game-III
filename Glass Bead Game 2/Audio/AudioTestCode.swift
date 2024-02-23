//
//  AudioTestCode.swift
//  Glass Bead Game
//
//  Created by Norman Sohl on 2/6/24.
//
/*
import Foundation
import CoreAudio

struct AudioDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
    let inputChannels: Int
    let outputChannels: Int
}

// basic test function for AudioDeviceManager
func test(){
    let devices = AudioDevicesManager.getAudioDevices()
    let num = devices.count
    let _ = print("number of devices = \(num)")
        devices.forEach { device in
        print("ID = \(device.id), name = \(device.name), InputChannels = \(device.inputChannels), outputChannels = \(device.outputChannels) ")
    }
}

class AudioDevicesManager {
    static func getAudioDevices() -> [AudioDevice] {
        var devices = [AudioDevice]()
        
        var propertySize: UInt32 = 0
        var status: OSStatus = noErr
        
        // Get the number of devices using coreaudio API
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        if status != noErr {
            print("Error: Unable to get the number of audio devices.")
            return devices
        }
        
        // Get the device IDs
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        if status != noErr {
            print("Error: Unable to get the audio device IDs.")
            return devices
        }
        
        // Get device info for each device
        for deviceID in deviceIDs {
            var deviceName: String = ""
            var inputChannels: Int = 0
            var outputChannels: Int = 0
            
            // Get device name
            propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString
            propertySize = UInt32(MemoryLayout<CFString>.size)
            var name: CFString? = nil
            status = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &propertySize,
                &name
            )
            if status == noErr, let deviceNameCF = name as String? {
                deviceName = deviceNameCF
            }
            
            // Get input channels
            propertyAddress.mSelector = kAudioDevicePropertyStreamConfiguration
            propertyAddress.mScope = kAudioDevicePropertyScopeInput
            status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
            if status == noErr {
                let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                defer { bufferListPointer.deallocate() }
                status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, bufferListPointer)
                if status == noErr {
                    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
                    for buffer in bufferList {
                        inputChannels += Int(buffer.mNumberChannels)
                    }
                }
            }
            
            // Get output channels
            propertyAddress.mScope = kAudioDevicePropertyScopeOutput
            status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
            if status == noErr {
                let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                defer { bufferListPointer.deallocate() }
                status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, bufferListPointer)
                if status == noErr {
                    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
                    for buffer in bufferList {
                        outputChannels += Int(buffer.mNumberChannels)
                    }
                }
            }
            
            devices.append(AudioDevice(id: deviceID, name: deviceName, inputChannels: inputChannels, outputChannels: outputChannels))
        }
        
        return devices
        
    }
}
*/
