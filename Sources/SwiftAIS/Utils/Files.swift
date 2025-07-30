//
//  Files.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/6/25.
//
//  Tools for working with IQ recordings.

import Foundation
import Accelerate

func readIQFromWAV16Bit(fileURL: URL) throws -> [DSPComplex] {
    let data = try Data(contentsOf: fileURL)
    
    var iqOutput: [DSPComplex] = []

    let iqData = data.dropFirst(44)
    guard iqData.count % 4 == 0 else {
        print("IQ Data is not properly formatted.")
        return []
    }
    
    iqData.withUnsafeBytes { (iqDataPtr: UnsafeRawBufferPointer) in
        let int16ArrayBasePointer = iqDataPtr.bindMemory(to: Int16.self)
        var currOffset: Int = 0
        while currOffset < int16ArrayBasePointer.count {
            let realSample = Float(int16ArrayBasePointer[currOffset]) / 32768.0
            let imagSample = Float(int16ArrayBasePointer[currOffset + 1]) / 32768.0
            iqOutput.append(DSPComplex(real: realSample, imag: imagSample))
            currOffset += 2
        }
    }
    
    return iqOutput
}

func readIQFromWAV16Bit(filePath: String) throws -> [DSPComplex] {
    let fileURL = URL(fileURLWithPath: filePath)
    let data = try Data(contentsOf: fileURL)
    var iqOutput: [DSPComplex] = []

    let iqData = data.dropFirst(44)
    guard iqData.count % 4 == 0 else {
        print("IQ Data is not properly formatted.")
        return []
    }
    
    iqData.withUnsafeBytes { (iqDataPtr: UnsafeRawBufferPointer) in
        let int16ArrayBasePointer = iqDataPtr.bindMemory(to: Int16.self)
        var currOffset: Int = 0
        while currOffset < int16ArrayBasePointer.count {
            let realSample = Float(int16ArrayBasePointer[currOffset]) / 32768.0
            let imagSample = Float(int16ArrayBasePointer[currOffset + 1]) / 32768.0
            iqOutput.append(DSPComplex(real: realSample, imag: imagSample))
            currOffset += 2
        }
    }
    
    return iqOutput
}

public func samplesToCSV(_ samples: [DSPComplex], path: String) {
    var csvText = "I,Q\n"
    for sample in samples {
        csvText.append("\(sample.real),\(sample.imag)\n")
    }
    do {
        try csvText.write(toFile: path, atomically: true, encoding: .utf8)
    }
    catch {
        print("Failed to write sample data to csv file.")
    }
}
