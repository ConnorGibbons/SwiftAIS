//
//  OfflineTesting.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/23/25.
//

import Foundation
import Accelerate
import RTLSDRWrapper
import SignalTools

/// Takes in RunTime state and uses stored offline variables as input if present.
/// Respects runtime arguments by calling handleSentence from main w/ state.
func offlineTesting(state: RuntimeState) throws {
    guard let centerFrequency = state.offlineCenterFrequency, let sampleRate = state.offlineSampleRate, let samples = state.offlineSamples else {
        print("Missing data required for offline decoding.")
        exit(1)
    }
    
    var timer = TimeOperation(operationName: "Preparing data")
    var channelABuffer: [DSPComplex] = .init(repeating: DSPComplex(real: 0, imag: 0), count: samples.count)
    var channelBBuffer: [DSPComplex] = .init(repeating: DSPComplex(real: 0, imag: 0), count: samples.count)
    shiftFrequencyToBasebandHighPrecision(rawIQ: samples, result: &channelABuffer, frequency: Float(AIS_CHANNEL_A - centerFrequency), sampleRate: sampleRate)
    shiftFrequencyToBasebandHighPrecision(rawIQ: samples, result: &channelBBuffer, frequency: Float(AIS_CHANNEL_B - centerFrequency), sampleRate: sampleRate)
    print(timer.stop())
    
    
    let channelAReceiver = try AISReceiver(inputSampleRate: sampleRate, channel: .A, seqIDGenerator: state.seqIDGenerator, debugConfig: state.debugConfig)
    let channelBReceiver = try AISReceiver(inputSampleRate: sampleRate, channel: .B, seqIDGenerator: state.seqIDGenerator, debugConfig: state.debugConfig)
    var sentences: [AISSentence] = []
    var processingTimer = TimeOperation(operationName: "Processing data")
    sentences.append(contentsOf: channelAReceiver.processSamples(channelABuffer))
    sentences.append(contentsOf: channelBReceiver.processSamples(channelBBuffer))
    print(processingTimer.stop())
    
    guard sentences.count > 0 else {
        print("Found no AIS sentences. Exiting...")
        return
    }
    
    for sentence in sentences {
        handleSentence(sentence, state: state)
    }
    
    
}
