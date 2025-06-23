//
//  Math.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/5/25.
//
//  Useful math functions for working with signals.

import Accelerate

func calculateAngle(rawIQ: [DSPComplex], result: inout [Float]) {
    let sampleCount = rawIQ.count
    guard sampleCount == result.count && !rawIQ.isEmpty else {
        return
    }
    var splitBuffer = DSPSplitComplex(realp: .allocate(capacity: sampleCount), imagp: .allocate(capacity: sampleCount))
    vDSP.convert(interleavedComplexVector: rawIQ, toSplitComplexVector: &splitBuffer)
    vDSP.phase(splitBuffer, result: &result)
    
    splitBuffer.realp.deallocate()
    splitBuffer.imagp.deallocate()
}

/// vDSP.phase output has a range of [-pi, pi]
/// If the range is surpassed, it will wrap to the opposite end.
/// Ex. if the value is (real: -1, imag: 0.001) the angle will be roughly pi. Once imag becomes negative, the value jumps to -pi, so we need to add 2pi to account.
func unwrapAngle(_ angle: inout [Float]) {
    let discontinuityThreshold = Float.pi
    var storedAccumulation: Float = 0
    var index = 1
    var cachedPreviousValue = angle[0]
    while(index < angle.count) {
        if((angle[index] - cachedPreviousValue).magnitude > discontinuityThreshold) {
            if(cachedPreviousValue > angle[index]) {
                storedAccumulation += (2 * discontinuityThreshold)
            }
            else {
                storedAccumulation -= (2 * discontinuityThreshold)
            }
        }
        cachedPreviousValue = angle[index]
        angle[index] = angle[index] + storedAccumulation
        index += 1
    }
}

func splitArray<T>(_ array: [T], sectionSize: Int) -> [[T]] {
    guard !array.isEmpty else {
        return []
    }
    let numSections = Int(ceil(Float(array.count) / Float(sectionSize)))
    var splitSections: [[T]] = .init(repeating: [], count: numSections)
    var index = 0
    while(index < array.count) {
        splitSections[index / sectionSize].append(array[index])
        index += 1
    }
    return splitSections
}

func shiftFrequencyToBasebandHighPrecision(rawIQ: [DSPComplex], result: inout [DSPComplex], frequency: Float, sampleRate: Int) {
    guard rawIQ.count == result.count else {
        return
    }
    
    let inputBufferAsDoubleComplex = rawIQ.map { DSPDoubleComplex(real: Double($0.real), imag: Double($0.imag)) }
    let sampleCount = rawIQ.count
    let frequenyDouble: Double = Double(frequency)
    let sampleRateDouble: Double = Double(sampleRate)
    let complexMixerArray = (0..<sampleCount).map{ index in
        let angle = -2 * Double.pi * frequenyDouble * Double(index) / sampleRateDouble
        return DSPDoubleComplex(real: cos(angle), imag: sin(angle))
    }
    
    var splitInputBuffer = DSPDoubleSplitComplex(realp: .allocate(capacity: sampleCount), imagp: .allocate(capacity: sampleCount))
    var splitMixerBuffer = DSPDoubleSplitComplex(realp: .allocate(capacity: sampleCount), imagp: .allocate(capacity: sampleCount))
    var splitResultBuffer = DSPDoubleSplitComplex(realp: .allocate(capacity: sampleCount), imagp: .allocate(capacity: sampleCount))
    let splitFloatResultBuffer = DSPSplitComplex(realp: .allocate(capacity: sampleCount), imagp: .allocate(capacity: sampleCount))
    defer {
        splitInputBuffer.realp.deallocate()
        splitInputBuffer.imagp.deallocate()
        splitMixerBuffer.realp.deallocate()
        splitMixerBuffer.imagp.deallocate()
        splitResultBuffer.realp.deallocate()
        splitResultBuffer.imagp.deallocate()
        splitFloatResultBuffer.realp.deallocate()
        splitFloatResultBuffer.imagp.deallocate()
    }
    let splitResultRealBufferPointer: UnsafeBufferPointer<Double> = .init(start: splitResultBuffer.realp, count: sampleCount)
    let splitResultImagBufferPointer: UnsafeBufferPointer<Double> = .init(start: splitResultBuffer.imagp, count: sampleCount)
    var splitFloatResultRealBufferPointer: UnsafeMutableBufferPointer<Float> = .init(start: splitFloatResultBuffer.realp, count: sampleCount)
    var splitFloatResultImagBufferPointer: UnsafeMutableBufferPointer<Float> = .init(start: splitFloatResultBuffer.imagp, count: sampleCount)
    vDSP.convert(interleavedComplexVector: inputBufferAsDoubleComplex, toSplitComplexVector: &splitInputBuffer)
    vDSP.convert(interleavedComplexVector: complexMixerArray, toSplitComplexVector: &splitMixerBuffer)
    vDSP.multiply(splitInputBuffer, by: splitMixerBuffer, count: sampleCount, useConjugate: false, result: &splitResultBuffer)
    vDSP.convertElements(of: splitResultRealBufferPointer, to: &splitFloatResultRealBufferPointer)
    vDSP.convertElements(of: splitResultImagBufferPointer, to: &splitFloatResultImagBufferPointer)
    vDSP.convert(splitComplexVector: splitFloatResultBuffer, toInterleavedComplexVector: &result)
}

func shiftFrequencyToBaseband(rawIQ: [DSPComplex], result: inout [DSPComplex], frequency: Float, sampleRate: Int) {
    guard rawIQ.count == result.count else {
        return
    }
    
    let sampleCount = rawIQ.count
    let complexMixerArray = (0..<sampleCount).map{ index in
        let angle = -2 * Float.pi * frequency * Float(index) / Float(sampleRate)
        return DSPComplex(real: cos(angle), imag: sin(angle))
    }
    
    var splitInputBuffer = DSPSplitComplex(realp: .allocate(capacity: sampleCount), imagp: .allocate(capacity: sampleCount))
    var splitMixerBuffer = DSPSplitComplex(realp: .allocate(capacity: sampleCount), imagp: .allocate(capacity: sampleCount))
    var splitResultBuffer = DSPSplitComplex(realp: .allocate(capacity: sampleCount), imagp: .allocate(capacity: sampleCount))
    defer {
        splitInputBuffer.realp.deallocate()
        splitInputBuffer.imagp.deallocate()
        splitMixerBuffer.realp.deallocate()
        splitMixerBuffer.imagp.deallocate()
        splitResultBuffer.realp.deallocate()
        splitResultBuffer.imagp.deallocate()
    }
    
    vDSP.convert(interleavedComplexVector: rawIQ, toSplitComplexVector: &splitInputBuffer)
    vDSP.convert(interleavedComplexVector: complexMixerArray, toSplitComplexVector: &splitMixerBuffer)
    vDSP.multiply(splitInputBuffer, by: splitMixerBuffer, count: sampleCount, useConjugate: false, result: &splitResultBuffer)
    vDSP.convert(splitComplexVector: splitResultBuffer, toInterleavedComplexVector: &result)
}

func sampleIndexToTime(_ sampleIndex: Int, sampleRate: Int) -> Double {
    return Double(sampleIndex) / Double(sampleRate)
}

func timeToSampleIndex(_ time: Double, sampleRate: Int) -> Int {
    return Int(time * Double(sampleRate))
}

func collapseTimeArray(_ timeArray: [Double], threshold: Double, addBuffer: Double) -> [(Double, Double)] {
    guard timeArray.count > 1 else { return [] }
    
    var collapsedTimes: [(Double, Double)] = []
    var startTime: Double = timeArray[0]
    var previousTime: Double = timeArray[0]
    
    for time in timeArray[1...] {
        if abs(time - previousTime) > threshold {
            collapsedTimes.append(((startTime - threshold - addBuffer),(previousTime + threshold + addBuffer)))
            startTime = time
        }
        previousTime = time
    }
    
    collapsedTimes.append(((startTime - threshold - addBuffer),(previousTime + threshold + addBuffer)))
    return collapsedTimes
}

/// Converts per-sample phase differences (radians) to instant frequency
/// rad x sampleRate = radians per second
/// radians per second / 2pi = freq.
func radToFrequency(radDiffs: [Float], sampleRate: Int) -> [Float] {
    let coefficient = Float(sampleRate) / (2 * Float.pi)
    return vDSP.multiply(coefficient, radDiffs)
}

func downsampleIQ(iqData: [DSPComplex], decimationFactor: Int, filter: [Float] = [0.5, 0.5]) -> [DSPComplex] {
    let iqDataCopy = iqData
    var returnVector: [DSPComplex] = .init(repeating: DSPComplex(real: 0, imag: 0), count: iqDataCopy.count / decimationFactor)
    var splitComplexData = DSPSplitComplex(realp: .allocate(capacity: iqDataCopy.count), imagp: .allocate(capacity: iqDataCopy.count))
    defer {
        splitComplexData.realp.deallocate()
        splitComplexData.imagp.deallocate()
    }
    vDSP.convert(interleavedComplexVector: iqDataCopy, toSplitComplexVector: &splitComplexData)
    let iBranchBufferPointer = UnsafeBufferPointer(start: splitComplexData.realp, count: iqDataCopy.count)
    let qBranchBufferPointer = UnsafeBufferPointer(start: splitComplexData.imagp, count: iqDataCopy.count)
    var iBranchDownsampled = vDSP.downsample(iBranchBufferPointer, decimationFactor: decimationFactor, filter: filter)
    var qBranchDownsampled = vDSP.downsample(qBranchBufferPointer, decimationFactor: decimationFactor, filter: filter)
    return iBranchDownsampled.withUnsafeMutableBufferPointer { iDownsampledBufferPointer in
        qBranchDownsampled.withUnsafeMutableBufferPointer { qDownsampledBufferPointer in
            let splitDownsampledData = DSPSplitComplex(realp: iDownsampledBufferPointer.baseAddress!, imagp: qDownsampledBufferPointer.baseAddress!)
            vDSP.convert(splitComplexVector: splitDownsampledData, toInterleavedComplexVector: &returnVector)
            return returnVector
        }
    }
}


func elementWiseMatchRatio<T>(array1: [T], array2: [T]) -> Float where T: Equatable {
    if(array1.count != array2.count) {
        print("Array length mismatch during comparison! ( \(array1.count), \(array2.count) )")
        return 0.0
    }
    var matchCount: Float = 0.0
    var index = 0
    while(index < array1.count) {
        if array1[index] == array2[index] {
            matchCount += 1
        }
        index += 1
    }
    return matchCount / Float(array1.count)
}






extension [Float] {
    
    func standardDeviation() -> Float {
        return vDSP.standardDeviation(self)
    }
    
    func average() -> Float {
        return vDSP.mean(self)
    }
    
    func normalize() -> [Float] {
        return vDSP.normalize(self)
    }
    
}

extension DSPComplex {
    
    func magnitude() -> Float {
        return ((real * real) + (imag * imag)).squareRoot()
    }
    
}

extension [DSPComplex] {
    
    func magnitude() -> [Float] {
        return self.map({$0.magnitude()})
    }
    
}

extension Array where Element: Comparable {
    
    func localMaximaIndicies(order: Int = 1) -> [Int] {
        var localMaxIndicies: [Int] = []
        var currIndex = order
        while(currIndex + order < self.count) {
            if(self.elementIsLocalMaxima(at: currIndex, order: order)) {
                localMaxIndicies.append(currIndex)
            }
            currIndex += 1
        }
        return localMaxIndicies
    }
    
    func localMinimaIndicies(order: Int = 1) -> [Int] {
        var localMinIndicies: [Int] = []
        var currIndex = order
        while(currIndex + order < self.count) {
            if(self.elementIsLocalMinima(at: currIndex, order: order)) {
                localMinIndicies.append(currIndex)
            }
            currIndex += 1
        }
        return localMinIndicies
    }
    
    private func elementIsLocalMinima(at index: Int, order: Int) -> Bool {
        guard index >= order && index + order < self.count else {
            return false
        }
        var currIndex = index - order
        while(currIndex <= (index + order)) {
            if(currIndex == index) {
                currIndex += 1
                continue
            }
            if(self[currIndex] <= self[index]) {
                return false
            }
            currIndex += 1
        }
        return true
    }
    
    private func elementIsLocalMaxima(at index: Int, order: Int) -> Bool {
        guard index >= order && index + order < self.count else {
            return false
        }
        var currIndex = index - order
        while(currIndex <= (index + order)) {
            if(currIndex == index) {
                currIndex += 1
                continue
            }
            if(self[currIndex] >= self[index]) {
                return false
            }
            currIndex += 1
        }
        return true
    }
}

extension [UInt8] {
    
    func interpretAsBinary() -> UInt8 {
        var sum = 0
        var index = 0
        while(index < self.count) {
            sum += (1 << index) * Int(self[self.count - index - 1])
            index += 1
        }
        return UInt8(sum)
    }
    
    func interpretAsBinaryLarger() -> UInt16 {
        var sum = 0
        var index = 0
        while(index < self.count) {
            sum += (1 << index) * Int(self[self.count - index - 1])
            index += 1
        }
        return UInt16(sum)
    }
    
    func toByteArray(reflect: Bool = false) -> [UInt8] {
        var copy = self
        
        let paddingBitsCount = self.count % 8 == 0 ? 0 : 8 - self.count % 8
        let paddingBits = [UInt8](repeating: 0, count: paddingBitsCount)
        copy.append(contentsOf: paddingBits)
        
        var bytes = [UInt8]()
        var index = 0
        while(index + 8 <= copy.count) {
            let byteSlice = reflect ? Array(copy[index..<index+8].reversed()) : Array(copy[index..<index+8])
            bytes.append(byteSlice.interpretAsBinary())
            index += 8
        }
        return bytes
    }
    
}
