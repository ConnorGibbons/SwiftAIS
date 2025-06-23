//
//  MSKGen.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/9/25.
//
import Foundation
import Accelerate

func nrziEncode(_ bits: [UInt8], initialLevel: UInt8 = 1) -> [UInt8] {
    var output: [UInt8] = []
    var currentLevel = initialLevel

    for bit in bits {
        if bit == 0 {
            currentLevel = 1 - currentLevel
        }
        output.append(currentLevel)
    }
    return output
}

func generateSignal(bits: [UInt8], sampleRate: Int, baud: Int, initialNrziLevel: UInt8 = 1) -> ([DSPComplex], [Float]) {
    let nrziBits = nrziEncode(bits, initialLevel: initialNrziLevel)
    var phase: Float = 0.0
    var iqSamples: [DSPComplex] = []
    var phaseSamples: [Float] = []

    let samplesPerSymbol = sampleRate / baud
    let perSamplePhaseChange = (.pi / 2.0) / Float(samplesPerSymbol)

    for bit in nrziBits {
        let direction: Float = (bit == 1) ? 1.0 : -1.0
        for _ in 0..<samplesPerSymbol {
            phase += perSamplePhaseChange * direction
            let i = cos(phase)
            let q = sin(phase)
            iqSamples.append(DSPComplex(real: i, imag: q))
            phaseSamples.append(phase)
        }
    }

    return (iqSamples, phaseSamples)
}
