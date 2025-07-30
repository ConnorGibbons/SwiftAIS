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

// Constants
let MIN_BUFFER_LEN = 16000

class RuntimeState {
    // Args
    var debugOutput: Bool = false
    var offlineTest: Bool = false
    var outputValidSentencesToConsole: Bool = false
    var useDigitalAGC: Bool = false
    var setupTCPServer: Bool = false
    var tcpServerPort: UInt16 = 50050
    var bandwidth: Int = 72000
    var sdrDeviceIndex: Int = 0
    var sdrHost: String? = nil
    var sdrPort: UInt16? = nil
    var maxBitFlips: Int = 0
    
    // State
    var outputServer: TCPServer?
    var validSentences: [AISSentence] = []
    var invalidSentences: [AISSentence] = []
    var bitErrorsCorrected: Int = 0
    var shouldExit: Bool = false
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
            print("Debug output: Enabled.")
            runtimeState.debugOutput = true
            
        case .offlineDecodingTest:
            print("Performing offline decoding test...")
            runtimeState.offlineTest = true
            
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
                    print("Bandwidth \(userBandwidth) out of range ([1000, 200000]), using default")
                    continue
                }
                runtimeState.bandwidth = userBandwidth
            }
            
        case .deviceIndex:
            currArgIndex += 1
            if let userDeviceIndex = nextArgument {
                if(userDeviceIndex.contains(":")) {
                    let split = userDeviceIndex.split(separator: ":")
                    if(split.count != 2) {
                        print("The provided host/port combo for rtl-sdr device was invalid.")
                        continue
                    }
                    runtimeState.sdrHost = String(split[0])
                    runtimeState.sdrPort = UInt16(split[1])!
                }
                else {
                    let indexAsInt: Int? = Int(userDeviceIndex)
                    if(indexAsInt == nil) {
                        print("The provided index for rtl-sdr device was invalid, defaulting to 0")
                        continue
                    }
                    runtimeState.sdrDeviceIndex = indexAsInt!
                }
            }
            
        case .tcpServer:
            currArgIndex += 1
            if let serverPort = Int(nextArgument ?? "failPlaceholder") {
                if(serverPort < 1 || serverPort > 65535) {
                    print("The provided TCP server port (\(serverPort)) was invalid, must be greater than 1 and less than 65535")
                    continue
                }
                runtimeState.setupTCPServer = true
                runtimeState.tcpServerPort = UInt16(serverPort)
            }
        
        case .errorCorrection:
            currArgIndex += 1
            if let userSpecifiedBitFlips = Int(nextArgument ?? "failPlaceholder") {
                if(userSpecifiedBitFlips < 0 || userSpecifiedBitFlips > 15) {
                    print("The provided number of bitflips (\(userSpecifiedBitFlips)) was invalid, must be between 0 and 15")
                    continue
                }
                runtimeState.maxBitFlips = userSpecifiedBitFlips
            }
            
        default:
            print("Unrecognized argument: \(String(describing: argument))")
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
    if(state.offlineTest) {
        offlineTesting()
        exit(0)
    }
    if(state.setupTCPServer) {
        print("Starting TCP Server for AIS data...")
        state.outputServer = try TCPServer(port: UInt16(state.tcpServerPort), actionOnNewConnection: { newConnection in
            print("New connection to AIS server: \(newConnection.connectionName)")
        })
        state.outputServer?.startServer()
    }
    
    let sdr: RTLSDR = try {
        if state.sdrHost != nil {
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
    let channelAReciever = try AISReceiver(inputSampleRate: DEFAULT_SAMPLE_RATE, channel: .A, errorCorrectBits: state.maxBitFlips, debugOutput: state.debugOutput)
    let channelBReciever = try AISReceiver(inputSampleRate: DEFAULT_SAMPLE_RATE, channel: .B, errorCorrectBits: state.maxBitFlips, debugOutput: state.debugOutput)
    
    var inputBuffer: [DSPComplex] = []
    
    sdr.asyncReadSamples(callback: { (inputData) in
        guard inputData.count > 16 else {
            if(state.debugOutput) {
                print("inputData too short, skipping")
            }
            return
        }
        var timer = TimeOperation(operationName: "handleInput")
        inputBuffer.append(contentsOf: inputData)
        if(inputBuffer.count >= MIN_BUFFER_LEN) {
            inputDataToRecievers(inputBuffer, receiverA: channelAReciever, receiverB: channelBReciever, state: state)
            inputBuffer = []
        }
        if(state.debugOutput) {
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

func inputDataToRecievers(_ inputData: [DSPComplex], receiverA: AISReceiver, receiverB: AISReceiver, state: RuntimeState) {
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

func registerSignalHandler() {
    signal(SIGINT) { _ in
        exit(0)
    }
}
