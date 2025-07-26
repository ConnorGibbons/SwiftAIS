//
//  SignalProcessor.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/17/25.
//
import Accelerate
import Foundation
import RTLSDRWrapper
import SignalTools

class SignalProcessor {
    
    var sampleRate: Int
    var samplesPerSymbol: Int {
        sampleRate / 9600
    }
    var rawFilters: [FIRFilter] = []
    var impulseFilters: [FIRFilter] = []
    var angleFilters: [FIRFilter] = []
    
    var debugOutput: Bool
    
    init(sampleRate: Int, debugOutput: Bool = false) throws {
        self.sampleRate = sampleRate
        let defaultFinerFilter = try FIRFilter(type: .lowPass, cutoffFrequency: 9600, sampleRate: sampleRate, tapsLength: 31)
        let defaultImpulseFilter = try FIRFilter(type: .lowPass, cutoffFrequency: 9600, sampleRate: sampleRate, tapsLength: 15)
        self.rawFilters = [defaultFinerFilter]
        self.impulseFilters = [defaultImpulseFilter]
        self.angleFilters = []
        self.debugOutput = debugOutput
    }
    
    init(sampleRate: Int, rawFilters: [FIRFilter], impulseFilters: [FIRFilter], angleFilters: [FIRFilter], debugOutput: Bool = false) {
        self.sampleRate = sampleRate
        self.rawFilters = rawFilters
        self.impulseFilters = impulseFilters
        self.angleFilters = angleFilters
        self.debugOutput = debugOutput
    }
    
    func filterRawSignal(_ signal: inout [DSPComplex]) {
        for filter in rawFilters {
            filter.filtfilt(&signal)
        }
    }
    
    func frequencyOverTime(_ signal: [DSPComplex]) -> [Float] {
        let radianDiffs = demodulateFM(signal)
        var frequencies = radToFrequency(radDiffs: radianDiffs, sampleRate: self.sampleRate)
        for filter in impulseFilters {
            filter.filtfilt(&frequencies)
        }
        return frequencies
    }
    
    func angleOverTime(_ signal: [DSPComplex]) -> [Float] {
        var angles = [Float].init(repeating: 0, count: signal.count)
        calculateAngle(rawIQ: signal, result: &angles)
        unwrapAngle(&angles)
        for filter in angleFilters {
            filter.filtfilt(&angles)
        }
        return angles
    }
    
    func estimateFrequencyError(preambleAngle: [Float]) -> Float {
        let workingPreambleAngle = preambleAngle.map {
            $0 - preambleAngle[0] // Just changing it so everything is relative to the starting angle
        }
        let localMax = getSignificantExtremaIndicies(angle: preambleAngle)
        guard localMax.count >= 2 else {
            debugPrint("Failed to find enough significant extrema in signal to estimate frequency error.")
            return -1
        }
        let firstPeakIndex = localMax[0]
        let sixthPeakIndex = localMax.count > 5 ? localMax[5] : localMax[localMax.count - 1]
        let timeDifference = Float(sixthPeakIndex - firstPeakIndex) / Float(sampleRate)
        let angleDifference = workingPreambleAngle[sixthPeakIndex] - workingPreambleAngle[firstPeakIndex]
        let anglePerSecond = angleDifference / timeDifference
        let frequencyError = anglePerSecond / (2 * Float.pi)
        debugPrint("Estimated Frequency Error: \(frequencyError)")
        return frequencyError
    }
    
    private func getSignificantExtremaIndicies(angle: [Float], useMax: Bool = true) -> [Int] {
        let indicies = useMax ? angle.localMaximaIndicies() : angle.localMinimaIndicies()
        return indicies.filter {
            abs(angle[$0]) > (Float.pi / 2 - 1)
        }
    }
    
    func correctFrequencyError(signal: [DSPComplex], error: Float) -> [DSPComplex] {
        var correctedSignal: [DSPComplex] = .init(repeating: DSPComplex(real: 0.0, imag: 0.0), count: signal.count)
        shiftFrequencyToBaseband(rawIQ: signal, result: &correctedSignal, frequency: error, sampleRate: self.sampleRate)
        self.filterRawSignal(&correctedSignal)
        return correctedSignal
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print(str)
        }
    }
    
}
