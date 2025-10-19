//
//  main.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/5/25.
//

import Foundation
import Accelerate
import RTLSDRWrapper
import SignalTools
import Network
import Darwin
import TCPUtils

// Constants
let MIN_BUFFER_LEN = 16000

class RuntimeState {
    // Args
    var debugConfig: DebugConfiguration = DebugConfiguration(debugOutput: false, saveDirectoryPath: nil)
    var offlineSamples: [DSPComplex]? = nil
    var offlineCenterFrequency: Int? = nil
    var offlineSampleRate: Int? = nil
    var outputValidSentencesToConsole: Bool = false
    var useDigitalAGC: Bool = false
    var bandwidth: Int = 72000
    var sdrDeviceIndex: Int = 0
    var sdrHost: String? = nil
    var sdrPort: UInt16? = nil
    var maxBitFlips: Int = 0
    
    // State
    var outputServer: TCPServer?
    var outputFile: FileHandle?
    var validSentences: [AISSentence] = []
    var invalidSentences: [AISSentence] = []
    let seqIDGenerator = SequentialIDGenerator()
    var bitErrorsCorrected: Int = 0
    var shouldExit: Bool = false
}

struct DebugConfiguration {
    let debugOutput: Bool
    let saveDirectoryPath: String?  // Each unsuccessful decoding attempt will result in a .aisDebug file created in this directory, if non-nil. More info in Utils/Files.swift
}

enum LaunchArgument: String {
    case debugOutput = "-d"
    case offlineDecodingTest = "-ot"
    case outputValidSentencesToConsole = "-n"
    case useDigitalAGC = "-agc"
    case tcpServer = "-tcp"
    case bandwidth = "-b"
    case deviceIndex = "-di"
    case errorCorrection = "-ec"
    case saveFile = "-s"
    case help = "-h"
}

func showHelp() {
    print("SwiftAIS - AIS Demodulator")
    print("Usage: SwiftAIS [options]")
    print("")
    print("Options:")
    print("  -h              Show this help message")
    print("  -d <file path>  Enable debug output, saves .aisDebug files to specified directory. Each file contains information about a failed demodulation attempt.")
    print("  -ot <file path, center frequency, sample rate> Perform offline decoding test using specified file as input, must be 16-bit WAV where IQ samples are interleaved")
    print("  -n              Print valid NMEA sentences to console")
    print("  -agc            Enable digital AGC")
    print("  -tcp <port>     Start TCP server on specified port (1-65535)")
    print("  -b <bandwidth>  Set tuner bandwidth in Hz (1000-200000)")
    print("  -di <index>     Set SDR device index or host:port for TCP connection")
    print("  -ec <bits>      Enable error correction (0-3 bit flips) -- NOTE: Anything above 0 (<=2 is recommended) can cause false positive 'corrections'. Use with caution!")
    print("  -s <file path>  Save decoded sentences to file")
    print("")
    print("Examples:")
    print("  SwiftAIS -d ./debugOutput -n   Run with debug output and console printing")
    print("  SwiftAIS -tcp 50050            Start TCP server on port 50050")
    print("  SwiftAIS -di 192.168.1.1:1234  Connect to remote SDR via TCP")
}

func mapCLIArgsToVariables() -> RuntimeState {
    let args = CommandLine.arguments
    let runtimeState = RuntimeState()
    let argCount = args.count
    var currArgIndex = 1
    while currArgIndex < argCount {
        var argument = LaunchArgument(rawValue: args[currArgIndex])
        guard argument != nil else {
            print("Unrecognized argument: \(args[currArgIndex])")
            currArgIndex += 1
            continue
        }
        argument = argument!
        let nextArgument: String? = (currArgIndex + 1) < argCount ? args[currArgIndex + 1] : nil
        currArgIndex += 1
        
        switch argument {
        case .debugOutput:
            currArgIndex += 1
            guard directoryExists(nextArgument ?? "failPlaceholder") else {
                print("Directory provided (\(nextArgument ?? "[none]")) for debug output doesn't exist or is not accessible.")
                exit(64)
            }
            runtimeState.debugConfig = DebugConfiguration.init(debugOutput: true, saveDirectoryPath: nextArgument)
            
        case .offlineDecodingTest:
            currArgIndex += 1
            guard FileManager.default.fileExists(atPath: nextArgument ?? "failPlaceholder") else {
                print("File (\(nextArgument ?? "[none]")) provided for offline testing doesn't exist of is not accessible.")
                exit(64)
            }
            do {
                let samples = try readIQFromWAV16Bit(filePath: nextArgument ?? "failPlaceholder")
                guard let centerFrequency = Int(args[currArgIndex]) else {
                    print("Center frequency provided for offline test (\(args[currArgIndex])) was not parsable to an integer.")
                    exit(64)
                }
                currArgIndex = currArgIndex + 1
                guard currArgIndex < argCount else {
                    print("Offline Decoding Test did not recieve enough arguments (file path, center frequency <Int>, sample rate <Int> required.")
                    exit(64)
                }
                guard let sampleRate = Int(args[currArgIndex]) else {
                    print("Sample rate provided for offline test (\(args[currArgIndex])) was not parsable to an integer.")
                    exit(64)
                }
                currArgIndex = currArgIndex + 1
                runtimeState.offlineSampleRate = sampleRate
                runtimeState.offlineCenterFrequency = centerFrequency
                runtimeState.offlineSamples = samples
            }
            catch {
                print("Unable to open file for offline testing, \(error.localizedDescription)")
                exit(64)
            }
            
        case .outputValidSentencesToConsole:
            print("Printing valid NMEA sentences to console: Enabled.")
            runtimeState.outputValidSentencesToConsole = true
            
        case .useDigitalAGC:
            print("Digital AGC: Enabled.")
            runtimeState.useDigitalAGC = true
            
        case .bandwidth:
            currArgIndex += 1
            if let userBandwidth = Int(nextArgument ?? "failPlaceholder") {
                if(userBandwidth > 200000 || userBandwidth < 1000) {
                    print("Bandwidth \(userBandwidth) out of range ([1000, 200000]), using default (\(runtimeState.bandwidth))")
                    continue
                }
                runtimeState.bandwidth = userBandwidth
            }
            else {
                print("-b argument requires an integer value be provided.")
                exit(64)
            }
            
        case .deviceIndex:
            currArgIndex += 1
            if let userDeviceIndex = nextArgument {
                if(userDeviceIndex.contains(":")) {
                    let split = userDeviceIndex.split(separator: ":")
                    if(split.count != 2) {
                        print("The provided host/port combo for rtl-sdr device was invalid.")
                        exit(64)
                    }
                    runtimeState.sdrHost = String(split[0])
                    runtimeState.sdrPort = UInt16(split[1])!
                }
                else {
                    let indexAsInt: Int? = Int(userDeviceIndex)
                    if(indexAsInt == nil) {
                        print("The provided index for rtl-sdr device was invalid.")
                        exit(64)
                    }
                    runtimeState.sdrDeviceIndex = indexAsInt!
                }
            }
            else {
                print("-di must be accompanied with a device index, either an integer (USB), or an IP/port combo (e.g. 192.168.1.100:12345).")
                exit(64)
            }
            
        case .tcpServer:
            currArgIndex += 1
            if let serverPort = Int(nextArgument ?? "failPlaceholder") {
                if(serverPort < 1 || serverPort > 65535) {
                    print("The provided TCP server port (\(serverPort)) was invalid, must be greater than 1 and less than 65535")
                    exit(64)
                }
                let port = UInt16(serverPort)
                do {
                    runtimeState.outputServer = try TCPServer(port: port, actionOnNewConnection: { newConnection in
                        print("New connection to AIS server: \(newConnection.connectionName)")
                    })
                }
                catch {
                    print("Failed to setup TCP server: \(error)")
                    exit(1)
                }
            }
            else {
                print("-tcp must be accompanied with an integer (1-65535), specifying the port to listen on.")
                exit(64)
            }
        
        case .errorCorrection:
            currArgIndex += 1
            if let userSpecifiedBitFlips = Int(nextArgument ?? "failPlaceholder") {
                if(userSpecifiedBitFlips < 0 || userSpecifiedBitFlips > 3) {
                    print("The provided number of bitflips (\(userSpecifiedBitFlips)) was invalid, must be between 0 and 3")
                    continue
                }
                runtimeState.maxBitFlips = userSpecifiedBitFlips
            }
            else {
                print("-ec must be accompanied with an integer (0-3), specifying max number of bits to flip durring correction.")
                exit(64)
            }
            
        case .help:
            showHelp()
            exit(0)
            
        case .saveFile:
            currArgIndex += 1
            if let filePath = nextArgument {
                do {
                    let fileExists = FileManager.default.fileExists(atPath: filePath)
                    if(!fileExists) {
                        let wasSuccessful = FileManager.default.createFile(atPath: filePath, contents: nil)
                        if(!wasSuccessful) {
                            print("Unable to create file at path: \(filePath)")
                            exit(64)
                        }
                    }
                    let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
                    fileHandle.seekToEndOfFile()
                    runtimeState.outputFile = fileHandle
                }
                catch {
                    print("Unable to open file for writing: \(error.localizedDescription), path: \(filePath)")
                    exit(64)
                }
            }
            else {
                print("-s must be accompanied with a file path (e.g. -s path/to/file.txt)")
                exit(64)
            }
            
        default:
            print("Unrecognized argument: \(String(describing: argument))")
            exit(64)
        }
    }
    return runtimeState
}


let state = mapCLIArgsToVariables()
do {
    try main(state: state)
}
catch {
    print(error.localizedDescription)
}

func main(state: RuntimeState) throws {
    if state.offlineSamples != nil {
        try offlineTesting(state: state)
        exit(0)
    }

    if(state.outputServer != nil) {
        print("Starting TCP Server for AIS data...")
        state.outputServer?.startServer()
    }
    
    let sdr: RTLSDR = try {
        if state.sdrHost != nil && state.sdrPort != nil {
            return try RTLSDR_TCP(host: state.sdrHost!, port: state.sdrPort!)
        }
        return try RTLSDR_USB(deviceIndex: state.sdrDeviceIndex)
    }()
    
    defer {
        sdr.stopAsyncRead()
    }
    
    try sdr.setCenterFrequency(AIS_CENTER_FREQUENCY)
    try sdr.setDigitalAGCEnabled(state.useDigitalAGC)
    try sdr.setSampleRate(DEFAULT_SAMPLE_RATE)
    try? sdr.setTunerBandwidth(state.bandwidth) // This won't work on RTLSDR_TCP because it's not implemented yet
    let channelAReceiver = try AISReceiver(inputSampleRate: DEFAULT_SAMPLE_RATE, channel: .A, errorCorrectBits: state.maxBitFlips, seqIDGenerator: state.seqIDGenerator, debugConfig: state.debugConfig)
    let channelBReceiver = try AISReceiver(inputSampleRate: DEFAULT_SAMPLE_RATE, channel: .B, errorCorrectBits: state.maxBitFlips, seqIDGenerator: state.seqIDGenerator, debugConfig: state.debugConfig)
    
    var inputBuffer: [DSPComplex] = []
    
    sdr.asyncReadSamples(callback: { (inputData) in
        guard inputData.count > 16 else {
            if(state.debugConfig.debugOutput) {
                print("inputData too short, skipping")
            }
            return
        }
        var timer = TimeOperation(operationName: "handleInput")
        inputBuffer.append(contentsOf: inputData)
        if(inputBuffer.count >= MIN_BUFFER_LEN) {
            inputDataToReceivers(inputBuffer, receiverA: channelAReceiver, receiverB: channelBReceiver, state: state)
            inputBuffer = []
        }
        if(state.debugConfig.debugOutput) {
            print(timer.stop() + "(\(inputData.count) samples)")
        }
    })
    
    registerSignalHandler()
    atexit_b { // Like 'atexit' but allows for capturing context. who knew?
        print("Number of valid sentences received: \(state.validSentences.count)")
        print("Number of invalid sentences received: \(state.invalidSentences.count)")
        print("Number of bit errors corrected: \(state.bitErrorsCorrected)")
    }
    
    let mainThreadBlockingSemaphore = DispatchSemaphore(value: 0)
    let checkStopConditionsLoop = AsyncTimedLoop() {
        if !sdr.isActive {
            mainThreadBlockingSemaphore.signal()
        }
    }
    checkStopConditionsLoop.startTimedLoop(interval: 0.5)
    mainThreadBlockingSemaphore.wait()
}

func inputDataToReceivers(_ inputData: [DSPComplex], receiverA: AISReceiver, receiverB: AISReceiver, state: RuntimeState) {
    var channelABuffer: [DSPComplex] = .init(repeating: DSPComplex(real: 0, imag: 0), count: inputData.count)
    var channelBBuffer: [DSPComplex] = .init(repeating: DSPComplex(real: 0, imag: 0), count: inputData.count)
    shiftFrequencyToBasebandHighPrecision(rawIQ: inputData, result: &channelABuffer, frequency: Float(CHANNEL_A_OFFSET), sampleRate: DEFAULT_SAMPLE_RATE)
    shiftFrequencyToBasebandHighPrecision(rawIQ: inputData, result: &channelBBuffer, frequency: Float(CHANNEL_B_OFFSET), sampleRate: DEFAULT_SAMPLE_RATE)
    let channelASentences = receiverA.processSamples(channelABuffer)
    let channelBSentences = receiverB.processSamples(channelBBuffer)
    for sentence in channelASentences {
        handleSentence(sentence, state: state)
    }
    for sentence in channelBSentences {
        handleSentence(sentence, state: state)
    }
}

func handleSentence(_ sentence: AISSentence, state: RuntimeState) {
    guard sentence.packetIsValid else {
        state.invalidSentences.append(sentence)
        return
    }
    state.validSentences.append(sentence)
    if(state.outputValidSentencesToConsole) {
        print(sentence)
    }
    if let outputFile = state.outputFile {
        writeSentenceToFile(sentence, file: outputFile)
    }
    
//    if(sentence.errorCorrectedBitsCount != 0) {
//        print("corrected \(sentence.errorCorrectedBitsCount) bits")
//        print("checksum: \(sentence.checksumAsHex())")
//        state.bitErrorsCorrected += sentence.errorCorrectedBitsCount
//    }
    
    if let server = state.outputServer {
        do {
            try server.broadcastMessage(sentence.description)
        }
        catch {
            print("Failed to broadcast message: \(error)")
        }
    }
}

// Required for atexit block to be called when closed via Ctrl+C
func registerSignalHandler() {
    signal(SIGINT) { _ in
        exit(0)
    }
}
