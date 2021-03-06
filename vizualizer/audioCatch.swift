//
//  audioCatch.swift
//  vizualizer
//
//  Created by 今野暁 on 2017/07/15.
//  Copyright © 2017年 今野暁. All rights reserved.
//

import Foundation
import CoreAudio
import AVFoundation
import AudioUnit
import AudioToolbox

let kOutputBus: UInt32 = 0;
let kInputBus: UInt32 = 1;

let graphView = Graph.sharedInstance;

var count = 0;

class AudioCatcher{
    var audioUnit:AudioUnit? = nil;
    var defaultAudioDeviceId:AudioDeviceID?;
    static let sharedInstance = AudioCatcher();
    
    private func setUpAudioHAL() -> OSStatus{
        var desc = AudioComponentDescription();
        var comp:AudioComponent?
        
        desc.componentType = kAudioUnitType_Output
        desc.componentSubType = kAudioUnitSubType_HALOutput
        
        desc.componentManufacturer = kAudioUnitManufacturer_Apple
        desc.componentFlags = 0
        desc.componentFlagsMask = 0
        
        comp = AudioComponentFindNext(nil, &desc)
        if comp == nil{
            return -1
        }
        
        let err = AudioComponentInstanceNew(comp!, &self.audioUnit);
        return err;
    }
    
    private func setUpEnableIO() -> OSStatus
    {
        // AudioUnitの入力を有効化、出力を無効化する。
        // デフォルトは出力有効設定
        var enableIO: UInt32 = 1
        var disableIO: UInt32 = 0
        var err: OSStatus?
        
        err = AudioUnitSetProperty(self.audioUnit!, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableIO, UInt32(MemoryLayout<UInt32>.size))
        
        if err == noErr
        {
            err = AudioUnitSetProperty(self.audioUnit!, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disableIO, UInt32(MemoryLayout<UInt32>.size))
        }
        
        return err!
    }
    
    private func setUpMicInput() -> OSStatus
    {
        // 入力デバイスを設定
        
        var inputDeviceId = AudioDeviceID(0)
        var err = noErr;
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        if(defaultAudioDeviceId == nil){
            var address =  AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                      mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMaster)
            
            err = AudioObjectGetPropertyData(UInt32(kAudioObjectSystemObject), &address, 0, nil, &size, &inputDeviceId)
            // デフォルトの入力デバイスを取得
        }else{
            inputDeviceId = defaultAudioDeviceId!;
        }
        
        if err == noErr
        {
            err = AudioUnitSetProperty(self.audioUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &inputDeviceId, size)
            // AudioUnitにデバイスを設定
        }
        
        // 確認用
        Swift.print("DeviceName:",inputDeviceId)
        Swift.print("BufferSize:",self.bufferSize(inputDeviceId))
        
        return err
    }
    
    private func setUpInputFormat() -> OSStatus
    {
        // サンプリングレートやデータビット数、データフォーマットなどを設定
        var audioFormat = AudioStreamBasicDescription()
        audioFormat.mBitsPerChannel = 16
        audioFormat.mBytesPerFrame = 4
        audioFormat.mBytesPerPacket = 4
        audioFormat.mChannelsPerFrame = 2
        audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        audioFormat.mFormatID = kAudioFormatLinearPCM
        audioFormat.mFramesPerPacket = 1
        audioFormat.mSampleRate = 44100.00
        
        let size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let err = AudioUnitSetProperty(self.audioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &audioFormat, size)
        
        return err
    }
    
    private func bufferSize(_ devID: AudioDeviceID) -> UInt32
    {
        // バッファサイズ確認
        var address =  AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMaster)
        var buf: UInt32 = 0
        var bufSize = UInt32(MemoryLayout<UInt32>.size)
        
        AudioObjectGetPropertyData(devID, &address, 0, nil, &bufSize, &buf)
        
        return buf
    }
    
    private func setUpCallback() -> OSStatus
    {
        // サンプリング用コールバックを設定
        var input = AURenderCallbackStruct(inputProc: renderCallback, inputProcRefCon: nil)
        
        let size = UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        let err = AudioUnitSetProperty(self.audioUnit!, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &input, size)
        
        return err
    }
    
    
    func initialize() {
        self.audioUnit = nil;
        if self.setUpAudioHAL() != noErr
        {
            exit(-1)
        }
        AudioUnitInitialize( self.audioUnit! );
        
        if self.setUpEnableIO() != noErr
        {
            exit(-1)
        }
        
        if self.setUpMicInput() != noErr
        {
            exit(-1)
        }
        
        if self.setUpInputFormat() != noErr
        {
            exit(-1)
        }
        
        if self.setUpCallback() != noErr
        {
            exit(-1)
        }
        
        if AudioUnitInitialize(self.audioUnit!) != noErr
        {
            exit(-1)
        }
        
        Swift.print("audio init!!")
        Swift.print(self.audioUnit!)
    }
    
    func start() {
        if self.audioUnit  == nil {
            return;
        }
        Swift.print("start");
        AudioOutputUnitStart( audioUnit! );
    }
    
    func end() {
        if self.audioUnit == nil {
            //     Swift.print("nilll")
            return;
        }
        Swift.print("end");
        AudioOutputUnitStop( self.audioUnit! );
    }
}

@objc protocol AURenderCallbackDelegate {
    func performRender(inRefCon:UnsafeMutableRawPointer,
                       ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                       inTimeStamp: UnsafePointer<AudioTimeStamp>,
                       inBusNumber: UInt32,
                       inNumberFrames: UInt32,
                       ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus
}

func renderCallback(inRefCon:UnsafeMutableRawPointer,
                    ioActionFlags:UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                    inTimeStamp:UnsafePointer<AudioTimeStamp>,
                    inBufNumber:UInt32,
                    inNumberFrames:UInt32,
                    ioData:UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    var err :OSStatus = noErr
    
    let buffer = allocateAudioBuffer(numChannel: 2, size: inNumberFrames)
    var bufs = AudioBufferList.init(mNumberBuffers: 1, mBuffers: buffer)
    
    let audioUnit = AudioCatcher.sharedInstance.audioUnit;
    if(AudioCatcher.sharedInstance.audioUnit != nil){
        err = AudioUnitRender(AudioCatcher.sharedInstance.audioUnit!,
                              ioActionFlags,
                              inTimeStamp,
                              inBufNumber,
                              inNumberFrames,
                              &bufs)
        
        if err == noErr
        {
            var array = [Int16]()
            let data=bufs.mBuffers.mData!.assumingMemoryBound(to: Int16.self)
            array.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(inNumberFrames)));
            count += 1;
            if(count >= 3){
                graphView.array = array;
                DispatchQueue.mainSyncSafe() {
                    graphView.setNeedsDisplay(graphView.frame)
                    //    Swift.print("call")
                }
                count = 0;
            }
        }
    }
    return err
    
}

func allocateAudioBuffer(numChannel: UInt32, size: UInt32) -> AudioBuffer {
    let dataSize = UInt32(numChannel * UInt32(MemoryLayout<Float64>.size) * size)
    let data = malloc(Int(dataSize))
    let buffer = AudioBuffer.init(mNumberChannels: numChannel, mDataByteSize: dataSize, mData: data)
    
    return buffer
}

func performRender(ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, inTimeStamp: UnsafePointer<AudioTimeStamp>, inBusNumber: UInt32, inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    Swift.print("Hello there!")
    return noErr
}


//catch Audiodevices
func getAudioDevices() throws -> Dictionary<String,UInt32>{
    
    //    var audioDevices: [AudioDeviceID] = []
    var audioDevicesDictionary = Dictionary<String,UInt32>();
    
    // Construct the address of the property which holds all available devices
    var devicesPropertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMaster)
    var propertySize = UInt32(0)
    
    // Get the size of the property in the kAudioObjectSystemObject so we can make space to store it
    try handle(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &devicesPropertyAddress, 0, nil, &propertySize))
    
    // Get the number of devices by dividing the property address by the size of AudioDeviceIDs
    let numberOfDevices = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    
    // Swift.print(numberOfDevices)
    
    // Create space to store the values
    var deviceIDs: [AudioDeviceID] = []
    for _ in 0 ..< numberOfDevices {
        deviceIDs.append(AudioDeviceID())
    }
    
    // Get the available devices
    try handle(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devicesPropertyAddress, 0, nil, &propertySize, &deviceIDs))
    
    // Iterate
    for id in deviceIDs {
        
        // Get the device name for fun
        var name: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var deviceNamePropertyAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceNameCFString, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMaster)
        try handle(AudioObjectGetPropertyData(id, &deviceNamePropertyAddress, 0, nil, &propertySize, &name))
        
        // Check the input scope of the device for any channels. That would mean it's an input device
        
        // Get the stream configuration of the device. It's a list of audio buffers.
        var InputStreamConfigAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: 0)
        
        // Get the size so we can make room again
        try handle(AudioObjectGetPropertyDataSize(id, &InputStreamConfigAddress, 0, nil, &propertySize))
        
        // Create a buffer list with the property size we just got and let core audio fill it
        let audioBufferList = AudioBufferList.allocate(maximumBuffers: Int(propertySize))
        try handle(AudioObjectGetPropertyData(id, &InputStreamConfigAddress, 0, nil, &propertySize, audioBufferList.unsafeMutablePointer))
        
        // Get the number of channels in all the audio buffers in the audio buffer list
        var channelCount = 0
        for i in 0 ..< Int(audioBufferList.unsafeMutablePointer.pointee.mNumberBuffers) {
            channelCount = channelCount + Int(audioBufferList[i].mNumberChannels)
        }
        
        free(audioBufferList.unsafeMutablePointer)
        
        // If there are channels, it's an input device
        if channelCount > 0 {
            Swift.print("Found Input device '\(name)' with \(channelCount) channels id:\(id)")
            //    audioDevices.append(id)
            audioDevicesDictionary[name as String] = id
        }
        
    }
    
    
    
    return audioDevicesDictionary
}


func handle(_ errorCode: OSStatus) throws {
    if errorCode != kAudioHardwareNoError {
        let error = NSError(domain: NSOSStatusErrorDomain, code: Int(errorCode), userInfo: [NSLocalizedDescriptionKey : "CAError: \(errorCode)" ])
        throw error
    }
}





