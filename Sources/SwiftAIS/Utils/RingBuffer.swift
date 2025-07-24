//
//  RingBuffer.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/6/25.
//
import Foundation
import Dispatch
import Accelerate

/// Important disclaimer here that "count" really refers to the size of the buffer and *not* how many valid elements are in it.
class RingBuffer<T> {
    var readHeadPosition: Int = 0
    var writeHeadPosition: Int = 0
    var internalBuffer: UnsafeMutableBufferPointer<T>
    var bufferStartPointer: UnsafeMutablePointer<T>
    var readWriteDiff: Int = 0
    var sem: DispatchSemaphore = DispatchSemaphore(value: 1)
    var count: Int {
        return internalBuffer.count
    }
    var isEmpty: Bool {
        return readWriteDiff <= 0
    }
    
    init(defaultVal: T, size: Int) {
        internalBuffer = UnsafeMutableBufferPointer<T>.allocate(capacity: size)
        internalBuffer.initialize(repeating: defaultVal)
        bufferStartPointer = internalBuffer.baseAddress!
    }
    
    func setValueAt(_ index: Int, _ value: T) {
        guard index >= 0 && index < count else { return }
        internalBuffer[index] = value
    }
    
    func getValueAt(_ index: Int) -> T? {
        guard index >= 0 && index < count else { return nil }
        return internalBuffer[index]
    }
    
    func write(_ value: T) {
        sem.wait()
        setValueAt(writeHeadPosition, value)
        writeHeadPosition = (writeHeadPosition + 1) % count
        readWriteDiff += 1
        sem.signal()
    }
    
    func noLockWrite(_ value: T) {
        setValueAt(writeHeadPosition, value)
        writeHeadPosition = (writeHeadPosition + 1) % count
        readWriteDiff += 1
    }
    
    func write(_ values: [T]) {
        sem.wait()
        for value in values {
            noLockWrite(value)
        }
        sem.signal()
    }
    
    func read(count: Int) -> (UnsafeBufferPointer<T>, UnsafeBufferPointer<T>?)? {
        sem.wait()
        guard count < self.count else { return nil }
        let oldReadHeadPosition = readHeadPosition
        readHeadPosition = (oldReadHeadPosition + count) % self.count
        readWriteDiff -= count
        checkReadWriteDiff()
        if oldReadHeadPosition + count < self.count {
            let ptr1 = UnsafeBufferPointer(start: bufferStartPointer.advanced(by: oldReadHeadPosition), count: count)
            return (ptr1, nil)
        }
        else {
            let ptr1 = UnsafeBufferPointer(start: bufferStartPointer.advanced(by: oldReadHeadPosition), count: self.count - oldReadHeadPosition)
            let ptr2 = UnsafeBufferPointer(start: bufferStartPointer, count: readHeadPosition)
            return (ptr1, ptr2)
        }
    }
    
    func signalDataWasConsumed() {
        sem.signal()
    }
    
    func checkReadWriteDiff() {
        if(readWriteDiff < 0) {
            print("**WARNING** Consuming from RingBuffer faster than writing to it! Expect bugs!")
        }
        else if(readWriteDiff > count) {
            print("**WARNING** Producing to RingBuffer faster than reading from it! Expect bugs!")
        }
    }
    
}

extension RingBuffer<DSPComplex> {
    
    /// Disclaimer: This function is **only** for use with this program (SwiftAIS) because of the unique use case where the buffer is never consumed from except for calculating the magnitude.
    /// As a result, the read head is never moved from it's starting position, and we can use readWriteDiff to determine if the whole buffer is valid or if we should just use the first portion of it.
    /// Going to need to rewrite this with vDSP as this version will probably be really slow!
    func magnitude() -> [Float] {
        var useCount = self.count
        if(readWriteDiff < count) {
            useCount = readWriteDiff
        }
        let fullBuffer = UnsafeBufferPointer<DSPComplex>(start: self.bufferStartPointer, count: useCount)
        let fullBufferAsSwiftArray: [DSPComplex] = Array(fullBuffer)
        return fullBufferAsSwiftArray.magnitude()
    }
    
}
