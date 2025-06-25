//
//  AISReceiver.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/6/25.
//
import Accelerate
import RTLSDRWrapper
import SignalTools

enum AISErrors: Error {
    case inputSampleRateTooLow
    case sampleRateMismatch
}

enum AISChannel: String {
    case A = "A"
    case B = "B"
}

struct AISSentence: CustomStringConvertible {
    var fragmentCount: Int
    var fragmentNumber: Int
    var sequentialID: Int?
    var channel: AISChannel
    var payloadBitstring: [UInt8]
    var payloadASCII: String
    var fillBits: Int
    var packetChecksum: UInt16
    var sentenceChecksum: UInt8 {
        calculatePayloadChecksum()
    }
    var packetIsValid: Bool
    
    var description: String {
        return "!AIVDM,\(self.fragmentCount),\(self.fragmentNumber),\(self.sequentialID?.description ?? ""),\(self.channel),\(self.payloadASCII),\(self.fillBits)*\(self.sentenceChecksumAsHex())"
    }
    
    var sentenceForChecksumCalculation: String {
        return "AIVDM,\(self.fragmentCount),\(self.fragmentNumber),\(self.sequentialID?.description ?? ""),\(self.channel),\(self.payloadASCII),\(self.fillBits)"
    }
    
    func checksumAsHex() -> String {
        return String(format: "%02X", self.packetChecksum)
    }
    
    func sentenceChecksumAsHex() -> String {
        return String(format: "%02X", self.sentenceChecksum)
    }
    
    func calculatePayloadChecksum() -> UInt8 {
        let strippedSentence = self.sentenceForChecksumCalculation
        var checksum = UInt8(0)
        for char in strippedSentence {
            checksum^=UInt8(char.asciiValue!)
        }
        return checksum
    }
    
    
}

class AISReceiver {
    let energyDetector: EnergyDetector
    let preprocessor: SignalPreprocessor
    let processor: SignalProcessor
    let synchronizer: PacketSynchronizer
    let decoder: PacketDecoder
    let validator: PacketValidator
    let inputSampleRate: Int
    let internalSampleRate: Int
    let channel: AISChannel
    
    var debugOutput: Bool
    
    // Initializers
    
    init(inputSampleRate: Int, internalSampleRate: Int = 48000, channel: AISChannel, debugOutput: Bool = false) throws {
        guard inputSampleRate >= internalSampleRate else {
            throw AISErrors.inputSampleRateTooLow
        }
        guard inputSampleRate % internalSampleRate == 0 else {
            print("Input sample rate must be a multiple of internal sample rate.")
            throw AISErrors.sampleRateMismatch
        }
        guard internalSampleRate % 9600 == 0 else {
            print("Internal sample rate must be a multiple of 9600 (AIS Baud)")
            throw AISErrors.sampleRateMismatch
        }
        
        let energyDetector = EnergyDetector(sampleRate: internalSampleRate, bufferDuration: nil, windowSize: nil, debugOutput: debugOutput)
        let preprocessor = SignalPreprocessor(inputSampleRate: inputSampleRate, outputSampleRate: internalSampleRate, debugOutput: debugOutput)
        let processor = try SignalProcessor(sampleRate: internalSampleRate, debugOutput: debugOutput)
        let decoder = PacketDecoder(sampleRate: internalSampleRate, debugOutput: debugOutput)
        let synchronizer = PacketSynchronizer(sampleRate: internalSampleRate, decoder: decoder, debugOutput: debugOutput)
        let validator = PacketValidator(maxFlipAtttempts: 3, debugOutput: debugOutput)
        
        self.inputSampleRate = inputSampleRate
        self.internalSampleRate = internalSampleRate
        self.energyDetector = energyDetector
        self.preprocessor = preprocessor
        self.processor = processor
        self.decoder = decoder
        self.synchronizer = synchronizer
        self.validator = validator
        self.channel = channel
        
        self.debugOutput = debugOutput
    }
    
    // Sample Processing
    
    func processSamples(_ samples: [DSPComplex]) -> [AISSentence] {
        var samplesMutableCopy = samples
        let filteredResampledSignal = preprocessor.processAISSignal(&samplesMutableCopy)
        
       let collapsedTimes = getHighEnergyTimes(filteredResampledSignal)
        guard collapsedTimes.count > 0 else {
            debugPrint("Exited early due to not finding proper collapsed times.")
            return []
        }
        
        var sentences: [AISSentence] = []
        for times in collapsedTimes {
            let startingSampleIndex = timeToSampleIndex(times.0, sampleRate: self.internalSampleRate)
            let endingSampleIndex = timeToSampleIndex(times.1, sampleRate: self.internalSampleRate)
            if (startingSampleIndex < 0 || endingSampleIndex >= filteredResampledSignal.count) {
                continue
            }
            let rawIQ = Array(filteredResampledSignal[startingSampleIndex...endingSampleIndex])
            let sentence = try! analyzeSamples(rawIQ, sampleRate: internalSampleRate)
            if(sentence != nil) {
                sentences.append(sentence!)
            }
            debugPrint("\n\n\n")
        }
        return sentences
    }
    
    func analyzeSamples(_ samples: [DSPComplex], sampleRate: Int) throws -> AISSentence? {
        guard sampleRate % 9600 == 0 else { throw AISErrors.sampleRateMismatch }
        let samplesPerSymbol = sampleRate / 9600
        var filteredIQ = samples
        
        self.processor.filterRawSignal(&filteredIQ)
        let frequencyOverTime = self.processor.frequencyOverTime(filteredIQ)
        let angles = self.processor.angleOverTime(filteredIQ)
        
        
        let coarseStartingSample = synchronizer.getCoarseStartingSample(samples: filteredIQ, angleOverTime: angles, frequencyOverTime: frequencyOverTime)
        if(coarseStartingSample < 0) {
            debugPrint("Aborting early: couldn't find coarse starting sample.")
            return nil
        }
        
        let frequencyErrorEstimate = processor.estimateFrequencyError(preambleAngle: Array(angles[coarseStartingSample..<(coarseStartingSample+32*samplesPerSymbol)]))
        let correctedSignal = (abs(frequencyErrorEstimate) > 60) ? processor.correctFrequencyError(signal: samples, error: frequencyErrorEstimate) : filteredIQ
        let correctedAngles = processor.angleOverTime(correctedSignal)
        
        
        let (preciseStartingSample, reversePolarity) = synchronizer.getPreciseStartingSampleAndPolarity(angle: Array(correctedAngles[coarseStartingSample..<coarseStartingSample+(32 * samplesPerSymbol)]), offset: coarseStartingSample)
        
        guard preciseStartingSample != -1 else {
            debugPrint("Failed to find precise starting index, aborting early")
            return nil
        }
        
        var (bits, certaintyToIndexMap) = decoder.decodeBitsFromAngleOverTime(Array(correctedAngles[preciseStartingSample..<correctedAngles.count - 1]), nrziStartHigh: !reversePolarity)
        let (bitsWithoutStuffing, startBytePosition, endBytePosition, _) = decoder.removeStuffingBitsAndFind0x7e(bits: bits)
        guard startBytePosition != -1 && endBytePosition != -1 else {
            debugPrint("Aborting early: didn't find either start or end flag.")
            return nil
        }
        guard ((startBytePosition + 8) < (endBytePosition - 16)) else {
            debugPrint("Aborting early: startBytePosition too close to endBytePosition")
            return nil
        }
        
        certaintyToIndexMap = certaintyToIndexMap
        .map {
            ($0.0, $0.1 - (startBytePosition + 8)) // Doing this so each index is now relative to the start byte
        }
        .filter {
            $0.1 >= 0 && $0.1 < endBytePosition // Anything outside this range isn't relevant for error correction (it's either preamble or wind-down bits)
        }
        
        let bitsWithoutFlagsOrCRC = Array(bitsWithoutStuffing[(startBytePosition + 8)..<(endBytePosition - 16)])
        let bitsWithoutFlags = Array(bitsWithoutStuffing[(startBytePosition + 8)..<endBytePosition])
        let (asciiString, paddingBitCount) = decoder.AISBitsToASCIIAndFillBits(bitsWithoutFlagsOrCRC)
        let (crcPassed, calculatedCRC) = validator.verifyCRC(bitsWithoutFlags)
        
        return AISSentence(fragmentCount: 1, fragmentNumber: 1, sequentialID: nil, channel: self.channel, payloadBitstring: bitsWithoutFlags, payloadASCII: asciiString, fillBits: paddingBitCount, packetChecksum: calculatedCRC, packetIsValid: crcPassed)
    }
    
    // Misc utils
    
    private func getHighEnergyTimes(_ signal: [DSPComplex]) -> [(Double, Double)] {
        var samplesToProcess: [[DSPComplex]] = []
        if(signal.count > energyDetector.bufferSize) {
            samplesToProcess = splitArray(signal, sectionSize: energyDetector.bufferSize)
        }
        else {
            samplesToProcess.append(signal)
        }
        
        var highEnergyIndicies: [Int] = []
        var currentChunkNum = 0
        while(currentChunkNum < samplesToProcess.count) {
            var newHighEnergyIndicies = self.energyDetector.addSamples(samplesToProcess[currentChunkNum])
            addBufferOffsetToIndexArray(&newHighEnergyIndicies, currentChunkNum)
            highEnergyIndicies.append(contentsOf: newHighEnergyIndicies)
            currentChunkNum += 1
        }
        guard highEnergyIndicies.count > 1 else {
            debugPrint("Exited early due to not finding enough high energy indicies")
            return []
        }
        
        let highEnergyTimes = highEnergyIndicies.map { sampleIndexToTime($0, sampleRate: self.internalSampleRate) }
        return collapseTimeArray(highEnergyTimes, threshold: 0.01, addBuffer: -0.005)
    }
    
    private func addBufferOffsetToIndexArray(_ indexArray: inout [Int], _ bufferOffset: Int) {
        var index = 0
        let bufferIndexOffset = bufferOffset * self.energyDetector.bufferSize
        while index < indexArray.count {
            indexArray[index] += bufferIndexOffset
            index += 1
        }
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print(str)
        }
    }
    
}


