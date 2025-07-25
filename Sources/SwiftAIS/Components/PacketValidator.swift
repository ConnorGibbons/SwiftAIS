//
//  PacketValidator.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/18/25.
//

import Foundation

/// PacketValidator will provide CRC verification & eventually small error correction.
/// maxFlipAttempts determines the max number of bits it will attempt flipping prior to giving up error correction.
/// Be careful with this parameter as the computational requirement grows fast --> max number of combinations checked is: cutoff Choose maxBitFlipCount --> (cutoff!) / (maxBitFlipCount)!(cutoff-maxBitFlipCount)!
class PacketValidator {
    var maxBitFlipCount: Int
    var cutoff: Int = 20
    var bitFlipIndicies: [[[Int]]] = []
    var checksumCalculator: CRC_16
    
    var debugOutput: Bool
    
    init(maxBitFlipCount: Int, debugOutput: Bool = false) {
        self.maxBitFlipCount = maxBitFlipCount
        self.checksumCalculator = CRC_16(poly: 0x1021, initialValue: 0xFFFF, finalXOR: 0xFFFF, reverseInput: true, reverseOutput: true)
        self.debugOutput = debugOutput
        self.bitFlipIndicies = combinationsBySize(n: cutoff, k: maxBitFlipCount)
    }
    
    func verifyCRC(_ bits: [UInt8]) -> (Bool, UInt16) {
        let providedCRCBits = Array(bits[bits.count - 16 ..< bits.count].reversed())
        let providedCRC = providedCRCBits.interpretAsBinaryLarger()
        let payloadBits = Array(bits[0..<bits.count-16]).toByteArray(reflect: true)
        let calculatedCRC = checksumCalculator.calculateCRC(payloadBits)
        return (providedCRC == calculatedCRC, providedCRC)
    }
    
    func correctErrors(bitsWithoutFlags: [UInt8], certainties: [(Float, Int)]) -> ([UInt8], UInt16, Int, Bool) {
        let providedCRC = verifyCRC(bitsWithoutFlags)
        guard !providedCRC.0 else {
            return (bitsWithoutFlags, providedCRC.1, 0, true)
        }
        guard maxBitFlipCount > 0 else {
            return ([], 0, 0, false)
        }
        guard certainties.count > 0 && bitsWithoutFlags.count >= certainties.count && bitsWithoutFlags.count > cutoff else {
            debugPrint("correctErrors called with bad parameters: bitsWithoutFlags:\(bitsWithoutFlags.count) entries, cetainties:\(certainties.count) entries, cutoff:\(cutoff)")
            return ([], 0, 0, false)
        }
        for currentBitFlipCount in 1...maxBitFlipCount {
            let currentIndiciesToTry = bitFlipIndicies[currentBitFlipCount - 1]
            for indiciesToTry in currentIndiciesToTry {
                let indexesInBitstring = getBitIndiciesFromCertaintyIndicies(certaintyIndex: indiciesToTry, certainties: certainties)
                let flipResult = nrziFlipBits(bits: bitsWithoutFlags, positions: indexesInBitstring)
                let (verificationResult, newCRC) = self.verifyCRC(flipResult)
                if verificationResult {
                    return (flipResult, newCRC, currentBitFlipCount, true)
                }
            }
        }
        return ([], 0, 0, false)
    }
    
    private func getBitIndiciesFromCertaintyIndicies(certaintyIndex: [Int], certainties: [(Float, Int)]) -> [Int] {
        var bitIndicies: [Int] = []
        for index in certaintyIndex {
            guard index < certainties.count else { continue }
            bitIndicies.append(certainties[index].1)
        }
        return bitIndicies
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print(str)
        }
    }
}
