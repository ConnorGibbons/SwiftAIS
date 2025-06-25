//
//  EnergyDetector.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/6/25.
//
import Accelerate
import SignalTools

class EnergyDetector {
    let sampleRate: Int
    var buffer: RingBuffer<DSPComplex>
    var bufferSize: Int {
        return buffer.count
    }
    var windowSize: Int
    
    var debugOutput: Bool
    
    init(sampleRate: Int, bufferDuration: Double?, windowSize: Int?, debugOutput: Bool = false) {
        if bufferDuration == nil {
            self.buffer = RingBuffer<DSPComplex>.init(defaultVal: .init(real: 0, imag: 0), size: sampleRate / 2) // 500ms default
        }
        else {
            self.buffer = RingBuffer<DSPComplex>.init(defaultVal: .init(real: 0, imag: 0), size: Int(Double(sampleRate) * bufferDuration!))
        }
        self.sampleRate = sampleRate
        self.windowSize = windowSize ?? sampleRate / 300
        self.debugOutput = debugOutput
    }
    
    func addSamples(_ samples: [DSPComplex]) -> [Int] {
        if samples.count > bufferSize {
            debugPrint("Input array cannot be greater than buffer size -- input: \(samples.count), size: \(bufferSize)")
            return []
        }
        else if samples.isEmpty {
            return []
        }
        
        self.buffer.write(samples)
        let threshold = self.processBuffer()
        var highEnergyIndicies: [Int] = []
        var currentIndex = 0
        let sampleMagnitudes = samples.magnitude()
        while (currentIndex + self.windowSize) < samples.count {
            let currentWindow = Array(sampleMagnitudes[currentIndex..<(currentIndex + self.windowSize)])
            let averageMagnitude = currentWindow.average()
            if averageMagnitude > threshold {
                highEnergyIndicies.append(currentIndex)
            }
            currentIndex += windowSize
        }
        
        return highEnergyIndicies
    }
    
    func processBuffer() -> Float {
        let magnitude = self.buffer.magnitude()
        let averageMagnitude = magnitude.average()
        let standardDeviation = magnitude.standardDeviation()
        return averageMagnitude + (2 * standardDeviation)
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print(str)
        }
    }
    
}
