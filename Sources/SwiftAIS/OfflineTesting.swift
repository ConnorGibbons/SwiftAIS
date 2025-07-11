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

/// Don't forget to replace filePath with the path to a .wav file! Samples should be 16 bits each, interleaved IQ.
func offlineTesting() {
    let t0_x = Date().timeIntervalSinceReferenceDate
    let serverSemaphore = DispatchSemaphore(value: 0)
    let server = try! TCPServer(port: 50100, actionOnStateUpdate: { newState in
        if newState == .ready {
            print("Test TCP Server started.")
            serverSemaphore.signal()
        }
    })
    server.startServer()
    let fullSampleFile = try! readIQFromWAV16Bit(filePath: "/Users/connorgibbons/Documents/Projects/DSPPlayground2/AIS Sample/5.31.25/resampled/firstSample.wav")
    let t1_x = Date().timeIntervalSinceReferenceDate
    print("Opened file for reading in \(t1_x - t0_x) seconds")
    var resultBuffer: [DSPComplex] = .init(repeating: DSPComplex(real: 0, imag: 0), count: fullSampleFile.count)
    let t0 = Date().timeIntervalSinceReferenceDate
    shiftFrequencyToBasebandHighPrecision(rawIQ: fullSampleFile, result: &resultBuffer, frequency: 33000, sampleRate: 240000)
    let newReciever = try! AISReceiver(inputSampleRate: 240000, channel: .A, debugOutput: true)
    _ = serverSemaphore.wait(timeout: DispatchTime.now() + 1)
    let t0_y = Date().timeIntervalSinceReferenceDate
    let sentences = newReciever.processSamples(resultBuffer)
    let t1_y = Date().timeIntervalSinceReferenceDate
    print("Processed \(sentences.count) sentences in \(t1_y - t0_y) seconds")
    for sentence in sentences {
        print(sentence)
        try! server.broadcastMessage(sentence.description + "\n")
        print(sentence.payloadBitstring.count)
    }
    let t1 = Date().timeIntervalSinceReferenceDate
    print("Finished: \(t1 - t0) seconds")
}
