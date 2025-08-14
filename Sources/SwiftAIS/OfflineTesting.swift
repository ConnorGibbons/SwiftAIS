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

func offlineTesting(samples: [DSPComplex]) {
    let serverSemaphore = DispatchSemaphore(value: 0)
    let server = try! TCPServer(port: 50100, actionOnStateUpdate: { newState in
        if newState == .ready {
            print("Test TCP Server started.")
            serverSemaphore.signal()
        }
    })
    server.startServer()
    var resultBuffer: [DSPComplex] = .init(repeating: DSPComplex(real: 0, imag: 0), count: samples.count)
    let t0 = Date().timeIntervalSinceReferenceDate
    shiftFrequencyToBasebandHighPrecision(rawIQ: samples, result: &resultBuffer, frequency: 33000, sampleRate: 240000)
    let seqIDGenerator = SequentialIDGenerator()
    let newReceiver = try! AISReceiver(inputSampleRate: 240000, channel: .A, seqIDGenerator: seqIDGenerator, debugConfig: DebugConfiguration(debugOutput: true, saveDirectoryPath: nil))
    _ = serverSemaphore.wait(timeout: DispatchTime.now() + 1)
    let t0_y = Date().timeIntervalSinceReferenceDate
    let sentences = newReceiver.processSamples(resultBuffer)
    let t1_y = Date().timeIntervalSinceReferenceDate
    print("Processed \(sentences.count) sentences in \(t1_y - t0_y) seconds")
    for sentence in sentences {
        print(sentence)
        print(sentence.packetIsValid)
        try! server.broadcastMessage(sentence.description + "\n")
        print(sentence.payloadBitstring.count)
        print(sentence.payloadBitstring)
    }
    let t1 = Date().timeIntervalSinceReferenceDate
    print("Finished: \(t1 - t0) seconds")
}
