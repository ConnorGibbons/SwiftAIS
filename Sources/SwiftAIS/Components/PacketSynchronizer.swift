//
//  PacketSynchronizer.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/17/25.
//

// Determines the coarse & precise starting points of an AIS signal.

import Accelerate
import Foundation

let aisPreamble: [UInt8] = Array(repeating: [0, 1], count: 12).flatMap { $0 }
let startEndByte: [UInt8] = [0, 1, 1, 1, 1, 1, 1, 0] // 0x7E
let aisPreambleAlt = Array(aisPreamble[2..<24])
let preambleAndStart = aisPreamble + startEndByte

class PacketSynchronizer {
    var sampleRate: Int
    var samplesPerSymbol: Int {
        sampleRate / 9600
    }
    var decoder: PacketDecoder
    
    var debugOutput: Bool
    
    init(sampleRate: Int, decoder: PacketDecoder, debugOutput: Bool = false) {
        self.sampleRate = sampleRate
        self.decoder = decoder
        self.debugOutput = debugOutput
    }
    
    func getCoarseStartingSample(samples: [DSPComplex], angleOverTime: [Float], frequencyOverTime: [Float]) -> Int {
        let correlation = vDSP.absolute(vDSP.correlate(frequencyOverTime, withKernel: idealPreambleAndStartImpulse))
        let maxima = correlation.localMaximaIndicies(order: 1).sorted {
            correlation[$0] > correlation[$1]
        }
        var currIndex = 0
        while(currIndex < 15 && currIndex < maxima.count) {
            if(maxima[currIndex] + (33 * samplesPerSymbol) > angleOverTime.count) {
                currIndex += 1
                continue
            }
            let (decodedBits, _) = decoder.decodeBitsFromAngleOverTime(Array(angleOverTime[maxima[currIndex]..<maxima[currIndex]+(33*samplesPerSymbol)]))
            let (decodedBitsRP, _) = decoder.decodeBitsFromAngleOverTime(Array(angleOverTime[maxima[currIndex]..<maxima[currIndex]+(33*samplesPerSymbol)]), nrziStartHigh: false)
            let matchRatio = elementWiseMatchRatio(array1: decodedBits, array2: preambleAndStart)
            let matchRatioRP = elementWiseMatchRatio(array1: decodedBitsRP, array2: preambleAndStart)
            if(matchRatio > 0.9 || matchRatioRP > 0.9) {
                debugPrint("Found coarse starting sample: \(maxima[currIndex]), Match Ratio: \(matchRatio), Match Ratio (RP): \(matchRatioRP)")
                //print(angleOverTime[maxima[currIndex]..<maxima[currIndex]+(33*samplesPerSymbol)])
                return maxima[currIndex]
            }
            currIndex += 1
        }
        return -1
    }
    
    func getPreciseStartingSampleAndPolarity(angle: [Float], offset: Int) -> (Int, Bool) {
        let workingPreambleAngle = angle.map {
            $0 - angle[0]
        }
        let samplesPerBit = sampleRate / 9600
        
        let rp = workingPreambleAngle[0] < workingPreambleAngle[workingPreambleAngle.count - 1]
        
        let startingTrend = angle[samplesPerBit - 1] - angle[0]
        let treatAsRP = (startingTrend > -1 && !rp)
        if(treatAsRP) {
            debugPrint("Treating signal as reverse polarity due to first two bits being weakly transmitted.")
        }
        
        let localMaxIndicies = getSignificantExtremaIndicies(angle: workingPreambleAngle, useMax: rp || treatAsRP)
        if(localMaxIndicies.isEmpty) {
            debugPrint("Unable to find sufficient extrema for precise start sample calculation.")
            return (-1, false)
        }
        
        let preciseStartingIndex = localMaxIndicies[0] - (2 * samplesPerSymbol)
        return (offset + preciseStartingIndex, rp || treatAsRP)
    }
    
    private func getSignificantExtremaIndicies(angle: [Float], useMax: Bool = true) -> [Int] {
        let indicies = useMax ? angle.localMaximaIndicies() : angle.localMinimaIndicies()
        return indicies.filter {
            abs(angle[$0]) > (Float.pi / 2 - 1)
        }
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print(str)
        }
    }
    
    
    
}
