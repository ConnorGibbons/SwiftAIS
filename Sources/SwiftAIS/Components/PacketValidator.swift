//
//  PacketValidator.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/18/25.
//

import Foundation

/// PacketValidator will provide CRC verification & eventually small error correction.
/// maxFlipAttempts determines the max number of bits it will attempt flipping prior to giving up error correction.
/// Be careful with this parameter as the computational requirement grows fast (2^x)
class PacketValidator {
    var maxFlipAttempts: Int = 10
    var checksumCalculator: CRC_16
    
    var debugOutput: Bool
    
    init(maxFlipAtttempts: Int, debugOutput: Bool = false) {
        self.maxFlipAttempts = maxFlipAtttempts
        self.checksumCalculator = CRC_16(poly: 0x1021, initialValue: 0xFFFF, finalXOR: 0xFFFF, reverseInput: true, reverseOutput: true)
        self.debugOutput = debugOutput
    }
    
    func verifyCRC(_ bits: [UInt8]) -> (Bool, UInt16) {
        let providedCRCBits = Array(bits[bits.count - 16 ..< bits.count].reversed())
        let providedCRC = providedCRCBits.interpretAsBinaryLarger()
        let payloadBits = Array(bits[0..<bits.count-16]).toByteArray(reflect: true)
        let calculatedCRC = checksumCalculator.calculateCRC(payloadBits)
        debugPrint("Provided CRC: \(String(format: "0x%X", providedCRC))")
        debugPrint("Calculated CRC: \(String(format: "0x%X", calculatedCRC))")
        return (providedCRC == calculatedCRC, providedCRC)
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print(str)
        }
    }
}
