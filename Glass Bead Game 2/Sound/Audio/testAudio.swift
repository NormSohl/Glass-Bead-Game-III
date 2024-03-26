//
//  testAudio.swift
//  Glass Bead Game 2
//
//  Created by Norman Sohl on 3/23/24.
//

/* from https://gist.github.com/rlxone/584467a63ac0ddf4d62fe1a983b42d0e
 
    static func getOutputDevices() -> [AudioDeviceID: String]?
    static func isOutputDevice(deviceID: AudioDeviceID) -> Bool
    static func getAggregateDeviceSubDeviceList(deviceID: AudioDeviceID) -> [AudioDeviceID]
    static func isAggregateDevice(deviceID: AudioDeviceID) -> Bool
    static func setDeviceVolume(deviceID: AudioDeviceID, leftChannelLevel: Float, rightChannelLevel: Float)
    static func setOutputDevice(newDeviceID: AudioDeviceID)
    static func getDeviceVolume(deviceID: AudioDeviceID) -> [Float]
    static func getDefaultOutputDevice() -> AudioDeviceID
*/

import Foundation
import AudioToolbox

public class TestAudio {
    
    func test(){
        var outputDevices = getOutputDevices()
        for device in outputDevices {
            print("\n")
            print("TEST: Device = \(getDeviceName(deviceID:device))")
            
            //var agg = isAggregateDevice (deviceID: device)
            //print("TEST:     Aggrate? = \(agg)")
            
            var numSubDevices = getNumberOfSubDevices(deviceID: device)
            print("TEST: Sub device count = \(numSubDevices)")
            
            var subDevice = getAggregateDeviceSubDeviceList(deviceID: device)
            
            for device in subDevice {
                print("TEST SubAgDevice = \(getDeviceName(deviceID: device))")
            }
            
            //var chanLayout = getDeviceChannelLayout(deviceID: device)
            //print("TEST:     channels: \(chanLayout.mNumberChannelDescriptions)")
            
            //_ = getDeviceStereoChannel(deviceID:device)
            
            var ret = getDeviceTransportType(deviceID:device)
            //if ret == kAudioDeviceTransportTypeUSB{
            //    print("USB ", ret)
            //}
            //else{
            //    print("Unknown: ",ret)
            //}
        }
        print("\n")
    }
        
        func getOutputDevices() -> [AudioDeviceID] {
            var result: [AudioDeviceID] = []
            let devices = getAllDevices()
            
            for device in devices {
                if isOutputDevice(deviceID: device) {
                    result.append(device)
                }
            }
            return result
        }
        
        func getOutputDevicestrings() -> [AudioDeviceID: String]? {
            var result: [AudioDeviceID: String] = [:]
            let devices = getAllDevices()
            
            for device in devices {
                if isOutputDevice(deviceID: device) {
                    result[device] = getDeviceName(deviceID: device)
                }
            }
            
            return result
        }
        
        func isOutputDevice(deviceID: AudioDeviceID) -> Bool {
            var propertySize: UInt32 = 256
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreams),
                mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            _ = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
            
            return propertySize > 0
        }
        
        func getAggregateDeviceSubDeviceList(deviceID: AudioDeviceID) -> [AudioDeviceID] {
            let subDevicesCount = getNumberOfSubDevices(deviceID: deviceID)
            var subDevices = [AudioDeviceID](repeating: 0, count: Int(subDevicesCount))
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioAggregateDevicePropertyActiveSubDeviceList),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            var subDevicesSize = subDevicesCount * UInt32(MemoryLayout<UInt32>.size)
            
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &subDevicesSize, &subDevices)
            
            return subDevices
        }
        
        func isAggregateDevice(deviceID: AudioDeviceID) -> Bool {
            let deviceType = getDeviceTransportType(deviceID: deviceID)
            return deviceType == kAudioDeviceTransportTypeAggregate
        }
        
        func setDeviceVolume(deviceID: AudioDeviceID, leftChannelLevel: Float, rightChannelLevel: Float) {
            let channelsCount = 2
            var channels = [UInt32](repeating: 0, count: channelsCount)
            var propertySize = UInt32(MemoryLayout<UInt32>.size * channelsCount)
            var leftLevel = leftChannelLevel
            var rigthLevel = rightChannelLevel
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyPreferredChannelsForStereo),
                mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &channels)
            
            if status != noErr { return }
            
            propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar
            propertySize = UInt32(MemoryLayout<Float32>.size)
            propertyAddress.mElement = channels[0]
            
            AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, propertySize, &leftLevel)
            
            propertyAddress.mElement = channels[1]
            
            AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, propertySize, &rigthLevel)
        }
        
        func setOutputDevice(newDeviceID: AudioDeviceID) {
            let propertySize = UInt32(MemoryLayout<UInt32>.size)
            var deviceID = newDeviceID
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, propertySize, &deviceID)
        }
        
        func getDeviceVolume(deviceID: AudioDeviceID) -> [Float] {
            let channelsCount = 2
            var channels = [UInt32](repeating: 0, count: channelsCount)
            var propertySize = UInt32(MemoryLayout<UInt32>.size * channelsCount)
            var leftLevel = Float32(-1)
            var rigthLevel = Float32(-1)
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyPreferredChannelsForStereo),
                mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &channels)
            
            if status != noErr { return [-1] }
            
            propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar
            propertySize = UInt32(MemoryLayout<Float32>.size)
            propertyAddress.mElement = channels[0]
            
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &leftLevel)
            
            propertyAddress.mElement = channels[1]
            
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &rigthLevel)
            
            return [leftLevel, rigthLevel]
        }
        
        func getDefaultOutputDevice() -> AudioDeviceID {
            var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
            var deviceID = kAudioDeviceUnknown
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
            
            return deviceID
        }
        
        func getDeviceTransportType(deviceID: AudioDeviceID) -> AudioDevicePropertyID {
            
            var deviceTransportType = AudioDevicePropertyID()
            var propertySize = UInt32(MemoryLayout<AudioDevicePropertyID>.size)
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyTransportType),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &deviceTransportType)
            
            switch deviceTransportType {
            case kAudioDeviceTransportTypeUnknown:
                print("kAudioDeviceTransportTypeUnknown")
                
            case kAudioDeviceTransportTypeBuiltIn:
                print("kAudioDeviceTransportTypeBuiltIn")
                
            case kAudioDeviceTransportTypeAggregate:
                print("kAudioDeviceTransportTypeAggregate")
                
            case kAudioDeviceTransportTypeVirtual:
                print("kAudioDeviceTransportTypeVirtual")
                
            case kAudioDeviceTransportTypePCI:
                print("kAudioDeviceTransportTypePCI")
                
            case kAudioDeviceTransportTypeUSB:
                print("kAudioDeviceTransportTypeUSB")
                
            case kAudioDeviceTransportTypeFireWire:
                print("kAudioDeviceTransportTypeFireWire")
                
            case kAudioDeviceTransportTypeBluetooth:
                print("kAudioDeviceTransportTypeBluetooth")
                
            case kAudioDeviceTransportTypeBluetoothLE:
                print("kAudioDeviceTransportTypeBluetoothLE")
                
            case kAudioDeviceTransportTypeHDMI:
                print("kAudioDeviceTransportTypeHDMI")
                
            case kAudioDeviceTransportTypeDisplayPort:
                print("kAudioDeviceTransportTypeDisplayPort")
                
            case kAudioDeviceTransportTypeAirPlay:
                print("kAudioDeviceTransportTypeAirPlay")
                
            case kAudioDeviceTransportTypeAVB:
                print("kAudioDeviceTransportTypeAVB")
                
            case kAudioDeviceTransportTypeThunderbolt:
                print("kAudioDeviceTransportTypeThunderbolt")
                
            case kAudioDeviceTransportTypeContinuityCaptureWired:
                print("kAudioDeviceTransportTypeContinuityCaptureWired")
                
            case kAudioDeviceTransportTypeContinuityCaptureWireless:
                print("kAudioDeviceTransportTypeContinuityCaptureWireless")
                
            default:
                print("no audio device match")
            }
            
            return deviceTransportType
        }
        
        func getDeviceChannelLayout(deviceID: AudioDeviceID) -> AudioChannelLayout {
            
            //AudioChannelLayout.mChannelLayoutTag: AudioChannelLayoutTag
            //AudioChannelLayout.mChannelBitmap: AudioChannelBitmap
            //AudioChannelLayout.mNumberChannelDescriptions: UInt32
            //AudioChannelLayout.mChannelDescriptions: [AudioChannelDescription] // this is a variable length array of mNumberChannelDescriptions elements
            
            var channelLayout = AudioChannelLayout()
            var propertySize = UInt32(MemoryLayout<AudioChannelLayout>.size)
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyPreferredChannelLayout),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            var status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &channelLayout)  // status says unknown property.
            print(deviceID)
            print(status.description)
            print(channelLayout.mChannelLayoutTag)
            print(channelLayout.mChannelBitmap)
            print(channelLayout.mNumberChannelDescriptions)
            print(channelLayout.mChannelDescriptions) // this is a variable length array of mNumberChannelDescriptions elements
            return channelLayout
        }
        
        func getDeviceStereoChannel(deviceID: AudioDeviceID) -> (UInt32,UInt32) {
            
            var channelIDs: [UInt32] = [0,0]
            var propertySize:UInt32 = 64
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyPreferredChannelLayout),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            var status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &channelIDs)  // status says unknown property.
            print(status) //2003332927 is unknown property.
            print(channelIDs)
            
            return (channelIDs[0], channelIDs[1])
        }
        
        func getNumberOfDevices() -> UInt32 {
            var propertySize: UInt32 = 0
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            _ = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
            
            return propertySize / UInt32(MemoryLayout<AudioDeviceID>.size)
        }
        
        func getNumberOfSubDevices(deviceID: AudioDeviceID) -> UInt32 {
            var propertySize: UInt32 = 0
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioAggregateDevicePropertyActiveSubDeviceList),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            _ = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
            
            return propertySize / UInt32(MemoryLayout<AudioDeviceID>.size)
        }
        
        func getDeviceName(deviceID: AudioDeviceID) -> String {
            var propertySize = UInt32(MemoryLayout<CFString>.size)
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceNameCFString),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            var result: CFString = "" as CFString
            
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &result)
            
            return result as String
        }
        
        func getAllDevices() -> [AudioDeviceID] {
            let devicesCount = getNumberOfDevices()
            var devices = [AudioDeviceID](repeating: 0, count: Int(devicesCount))
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
            
            var devicesSize = devicesCount * UInt32(MemoryLayout<UInt32>.size)
            
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &devicesSize, &devices)
            
            return devices
        }
        
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
