//
//  CRC.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/16/25.
//

class CRC_16 {
    let poly: UInt16
    let initialValue: UInt16
    let finalXOR: UInt16
    let reverseInput: Bool
    let reverseOutput: Bool
    var lookupTable: [UInt16]?
    
    init(poly: UInt16, initialValue: UInt16, finalXOR: UInt16, reverseInput: Bool, reverseOutput: Bool) {
        self.poly = poly
        self.initialValue = initialValue
        self.finalXOR = finalXOR
        self.reverseInput = reverseInput
        self.reverseOutput = reverseOutput
        self.lookupTable = nil
        self.lookupTable = calculateLUT()
    }
    
    /// Stores the 16-bit state of the register after processing a byte with the value of the index, assuming beginning with zero.
    private func calculateLUT() -> [UInt16] {
        var table: [UInt16] = .init(repeating: 0, count: 256)
    
            for i in 0..<256 {
                var crc = UInt16(i) << 8
                for _ in 0..<8 {
                    let MSBisOne = (crc & 0x8000) != 0
                    crc <<= 1
                    if MSBisOne {
                        crc ^= self.poly
                    }
                }
                table[i] = crc
            }
        
        return table
    }
    
    func calculateCRC(_ data: [UInt8]) -> UInt16 {
        guard lookupTable != nil else { return 0x0000 }
        let lut = lookupTable!
        
        var crc: UInt16 = UInt16(initialValue)
        var index: UInt16 = 0
        
        for byte in data {
            let workingByte = reverseInput ? reverseBits(byte) : byte
            index = UInt16(workingByte) ^ (crc >> 8) & 0xFF
            crc = (crc << 8) ^ UInt16(lut[Int(index)])
        }
        
        if(reverseOutput) {
            crc = reverseBits(crc)
        }
        
        return crc ^ finalXOR
    }
    
}

func reverseBits(_ n: UInt32) -> UInt32 {
    var reversed: UInt32 = 0
    
    for i in 0..<32 {
        let mask = UInt32(1 << i)
        let currBit = (n & mask) != 0 ? 1 : 0
        reversed += UInt32(currBit) << (31 - i)
    }
    
    return reversed
}

func reverseBits(_ n: UInt16) -> UInt16 {
    var reversed: UInt16 = 0
    
    for i in 0..<16 {
        let mask = UInt16(1 << i)
        let currBit = (n & mask) != 0 ? 1 : 0
        reversed += UInt16(currBit) << (15 - i)
    }
    
    return reversed
}

func reverseBits(_ n: UInt8) -> UInt8 {
    var reversed: UInt8 = 0
    
    for i in 0..<8 {
        let mask = UInt8(1 << i)
        let currBit = (n & mask) != 0 ? 1 : 0
        reversed += UInt8(currBit) << (7 - i)
    }
    
    return reversed
}
