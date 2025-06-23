//
//  FrameDecoder.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/17/25.
//

// Extracts bit-level info from AIS packet samples.

class PacketDecoder {
    var sampleRate: Int
    var samplesPerSymbol: Int {
        sampleRate / 9600
    }
    
    var debugOutput: Bool
    
    init(sampleRate: Int, debugOutput: Bool = false) {
        self.sampleRate = sampleRate
        self.debugOutput = debugOutput
    }
    
    func decodeBitsFromAngleOverTime(_ angle: [Float], nrziStartHigh: Bool = true) -> ([UInt8] , [(Float, Int)]) {
        var bits: [UInt8] = []
        var certaintyToIndexMap: [(Float, Int)] = []
        var currBitBoundaryBeginning = 0
        var previousVIsHigh: Bool = nrziStartHigh
        while(currBitBoundaryBeginning + samplesPerSymbol < angle.count) {
            let angleDiffAbsolute = abs(angle[currBitBoundaryBeginning + samplesPerSymbol] - angle[currBitBoundaryBeginning])
            let currentVIsHigh = angle[currBitBoundaryBeginning + samplesPerSymbol] > angle[currBitBoundaryBeginning]
            if(currentVIsHigh == previousVIsHigh) {
                bits.append(1)
            }
            else {
                bits.append(0)
                previousVIsHigh = currentVIsHigh
            }
            certaintyToIndexMap.append((angleDiffAbsolute, bits.count - 1))
            currBitBoundaryBeginning += samplesPerSymbol
        }
        certaintyToIndexMap.sort { $0.0 < $1.0 }
        return (bits, certaintyToIndexMap)
    }
    
    func removeStuffingBitsAndFind0x7e(bits: [UInt8]) -> (bitsWithoutStuffing: [UInt8], startBytePosition: Int, endBytePosition: Int, stuffBitCount: Int) {
        var consecutiveOnes = 0
        var startBytePosition = -1
        var endBytePosition = -1
        var stuffBitCount = 0
        var bitsWithoutStuffing: [UInt8] = []
        bitsWithoutStuffing.reserveCapacity(bits.count)

        for i in 0..<bits.count {
            let currentPositionInCompleteBitstring = i - stuffBitCount

            if bits[i] == 1 {
                consecutiveOnes += 1
            } else {
                if consecutiveOnes == 5 {
                    consecutiveOnes = 0
                    stuffBitCount += 1
                    continue
                }
                else if consecutiveOnes == 6 {
                    if startBytePosition == -1 {
                        startBytePosition = currentPositionInCompleteBitstring - 7
                    } else {
                        endBytePosition = currentPositionInCompleteBitstring - 7
                        // A second flag indicates the end of the frame.
                        // Malformed messages might hit this prematurely.
                        break
                    }
                }
                consecutiveOnes = 0
            }
            bitsWithoutStuffing.append(bits[i])
        }
        
        return (bitsWithoutStuffing, startBytePosition, endBytePosition, stuffBitCount)
    }
    
    func AISBitsToASCIIAndFillBits(_ bits: [UInt8]) -> (String, Int) {
        var workingBitsCopy = bits
        let paddingBitCount = (bits.count % 8 == 0) ? 0 : 8 - bits.count % 8
        debugPrint("Bitstring needs \(paddingBitCount) more bits to be split into bytes.")
        let paddingBits: [UInt8] = .init(repeating: 0, count: paddingBitCount)
        workingBitsCopy.append(contentsOf: paddingBits)
        var bitsWithReversedBytes = [UInt8]()
        var index = 0
        while(index + 8 <= workingBitsCopy.count) {
            let currByte = workingBitsCopy[index..<index+8].reversed()
            bitsWithReversedBytes.append(contentsOf: currByte)
            index += 8
        }
        let asciiPaddingBitCount = (bitsWithReversedBytes.count % 6 == 0) ? 0 : 6 - bitsWithReversedBytes.count % 6
        debugPrint("Bitstring needs \(asciiPaddingBitCount) more bits to be converted to 6-bit ASCII.")
        let asciiPaddingBits: [UInt8] = .init(repeating: 0, count: asciiPaddingBitCount)
        bitsWithReversedBytes.append(contentsOf: asciiPaddingBits)
        
        var asciiString = ""
        index = 0
        while(index + 6 <= bitsWithReversedBytes.count) {
            let asciiBits = Array(bitsWithReversedBytes[index..<index+6])
            asciiString.append(binaryToASCIITable[asciiBits.interpretAsBinary()] ?? "_")
            index += 6
        }
        return (asciiString, asciiPaddingBitCount)
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print(str)
        }
    }
    
}
