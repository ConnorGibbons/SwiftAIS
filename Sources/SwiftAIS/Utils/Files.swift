//
//  Files.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/6/25.
//
//  Tools for working with IQ recordings.

import Foundation
import Accelerate

struct DemodulationDebugStats: Encodable {
    let samples: [DSPComplex]
    let sentence: String
    let coarseStartingSampleIndex: Int
    let preciseStartingSampleIndex: Int
    var isReversePolarity: Bool
    
    enum CodingKeys: String, CodingKey {
        case sentence
        case coarseStartingSampleIndex
        case preciseStartingSampleIndex
        case isReversePolarity
    }
}

func directoryExists(_ path: String) -> Bool {
    var isDirObjCBool: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDirObjCBool) {
        return isDirObjCBool.boolValue
    } else {
        return false
    }
}

/// Saves debug stats from AISReceiver as (current time).aisDebug
/// This is called for each unsuccessful decoding attempt, per-sentence. Can be used to determine what went wrong for a particular demodulation attempt.
/// Format:
/// sentence, coarseStartingSampleIndex, preciseStartingSampleIndex, isReversePolarity contained in a JSON object
/// Complex samples as comma separated values, each row in the format "I,Q\n".
func writeDebugStats(directoryPath: String, stats: DemodulationDebugStats) {
    guard directoryExists(directoryPath) else {
        print("Directory does not exist: \(directoryPath), can't write debug stats")
        return
    }
    let newFileName = "debug_stats_\(Date().timeIntervalSince1970).aisDebug"
    let newFilePath = "\(directoryPath)/\(newFileName)"
    guard FileManager.default.createFile(atPath: newFilePath, contents: nil) else {
        print("Failed to create file at \(newFilePath), can't write debug stats")
        return
    }
    do {
        let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: newFilePath))
        let jsonDebugData = try JSONEncoder().encode(stats)
        var csvText = "I,Q\n"
        for sample in stats.samples {
            csvText.append("\(sample.real),\(sample.imag)\n")
        }
        let csvData = csvText.data(using: .utf8)!
        fileHandle.write(jsonDebugData)
        fileHandle.write(csvData)
        fileHandle.closeFile()
    }
    catch {
        print("Failed to save debug stats to file, error: \(error.localizedDescription), path: \(newFilePath)")
    }
}

func saveSentencesToFile(_ sentences: [AISSentence], path: String) {
    var sentenceText = "\n"
    for sentence in sentences {
        sentenceText.append("\(sentence.description)\n")
    }
    do {
        try sentenceText.write(toFile: path, atomically: true, encoding: .utf8)
    }
    catch {
        print("Failed to write NMEA sentences to file, \(path)")
    }
}

// Note: This assumes that file pointer is already at end of file
func writeSentenceToFile(_ sentence: AISSentence, file: FileHandle) {
    guard let sentenceAsData = (sentence.description + "\n").data(using: .utf8) else {
        print("Failed to encode NMEA sentence as data, \(sentence.description)")
        return
    }
    file.write(sentenceAsData)
}
