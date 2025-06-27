//
//  SwiftAISTests.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/27/25.
//
import Testing
import Foundation
import SignalTools
import Accelerate
@testable import SwiftAIS

// Should make the sentence: !AIVDM,1,1,,B,E>k`HC0VTah9QTb:Pb2h0ab0P00=N97j<4dDP00000<020,4*6F without having to do any error correction.
@Test func testSentence1() {
    
    do {
        guard let sentence1Path = Bundle.module.url(forResource: "sentence1", withExtension: "wav")?.path() else {
            print("Failed to find sentence1.wav -- did you delete the TestData folder?")
            assert(false)
        }
        let sentence1IQData = try readIQFromWAV16Bit(filePath: sentence1Path)
        var sentence1Shifted: [DSPComplex] = .init(repeating: DSPComplex(real: 0.0, imag: 0.0), count: sentence1IQData.count)
        shiftFrequencyToBasebandHighPrecision(rawIQ: sentence1IQData, result: &sentence1Shifted, frequency: 33000, sampleRate: 240000)
        let testReceiver = try AISReceiver(inputSampleRate: 240000, channel: .B)
        let prepocessed = testReceiver.preprocessor.processAISSignal(&sentence1Shifted)
        let sentence1 = try testReceiver.analyzeSamples(prepocessed, sampleRate: 48000)
        assert(sentence1 != nil)
        assert(String(describing: sentence1!) == "!AIVDM,1,1,,B,E>k`HC0VTah9QTb:Pb2h0ab0P00=N97j<4dDP00000<020,4*6F")
    }
    catch {
        assert(false , error.localizedDescription)
    }
    
    assert(true)
}

