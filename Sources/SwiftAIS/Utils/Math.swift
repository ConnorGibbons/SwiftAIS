//
//  Math.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/5/25.
//
//  Useful math functions for working with signals.

import Accelerate

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
