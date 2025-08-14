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
    sentences.append(contentsOf: channelAReceiver.processSamples(channelABuffer))
    sentences.append(contentsOf: channelBReceiver.processSamples(channelBBuffer))
    
    guard sentences.count > 0 else {
        print("Found no AIS sentences. Exiting...")
        return
    }
    
    for sentence in sentences {
        guard sentence.packetIsValid else { continue }
        state.validSentences.append(sentence)
        
        if(state.outputValidSentencesToConsole) {
            print(sentence.description)
        }
        
        if let saveFileHandle = state.outputFile {
            writeSentenceToFile(sentence, file: saveFileHandle)
        }
        
        if let server = state.outputServer {
            let splitSentences = sentence.description.split(separator: "\n") // In case it's a multi sentence message.
            do {
                for sentence in splitSentences {
                    try server.broadcastMessage(String(sentence))
                }
            }
            catch {
                print("Unable to broadcast message: \(error)")
            }
        }
        
    }
    
    
}
