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

// Constants
let MIN_BUFFER_LEN = 16000

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
var validSentences: [AISSentence] = []
var invalidSentences: [AISSentence] = []

var outputServer: TCPServer?


@MainActor func mapCLIArgsToVariables() {
    let args = CommandLine.arguments
    let argCount = args.count
    var currArgIndex = 1
    while currArgIndex < argCount {
        let argument = args[currArgIndex]
        let nextArgument: String? = (currArgIndex + 1) < argCount ? args[currArgIndex + 1] : nil
        currArgIndex += 1
        switch true {
        case argument.hasPrefix("-d "):
            print("Debug output: Enabled.")
            debugOutput = true
            
        case argument.hasPrefix("-ot"):
            print("Performing offline decoding test...")
            offlineTest = true
            
        case argument.hasPrefix("-n"):
            print("Printing valid NMEA sentences to console: Enabled.")
            outputValidSentencesToConsole = true
            
        case argument.hasPrefix("-agc"):
            print("Digital AGC: Enabled.")
            useDigitalAGC = true
            
        case argument.hasPrefix("-b"):
            currArgIndex += 1
            if let userBandwidth = Int(nextArgument ?? "failPlaceholder") {
                if(userBandwidth > 200000 || userBandwidth < 1000) {
                    print("Bandwidth \(userBandwidth) out of range ([1000, 200000]), using default")
                    continue
                }
                bandwidth = userBandwidth
            }
            
        case argument.hasPrefix("-di"):
            currArgIndex += 1
            if let userDeviceIndex = nextArgument {
                if(userDeviceIndex.contains(":")) {
                    let split = userDeviceIndex.split(separator: ":")
                    if(split.count != 2) {
                        print("The provided host/port combo for rtl-sdr device was invalid.")
                        continue
                    }
                    sdrHost = String(split[0])
                    sdrPort = UInt16(split[1])!
                }
                else {
                    let indexAsInt: Int? = Int(userDeviceIndex)
                    if(indexAsInt == nil) {
                        print("The provided index for rtl-sdr device was invalid, defaulting to 0")
                        continue
                    }
                    sdrDeviceIndex = indexAsInt!
                }
            }
            
        case argument.hasPrefix("-tcp"):
            currArgIndex += 1
            if let serverPort = Int(nextArgument ?? "failPlaceholder") {
                if(serverPort < 1 || serverPort > 65535) {
                    print("The provided TCP server port (\(serverPort)) was invalid, must be greater than 1 and less than 65535")
                    continue
                }
                setupTCPServer = true
                tcpServerPort = UInt16(serverPort)
            }
            
        default:
            print("Unrecognized argument: \(argument)")
        }
    }
}

if #available(macOS 15.0, *) {
    mapCLIArgsToVariables()
    do {
        try main()
    }
    catch {
        print(error.localizedDescription)
    }
}
else {
    print("SwiftAIS is only available on macOS 15.0 or newer.")
}

@available(macOS 15.0, *)
@MainActor func main() throws {
    
    if(offlineTest) {
        offlineTesting()
        exit(0)
    }
    if(setupTCPServer) {
        print("Starting TCP Server for AIS data...")
        outputServer = try TCPServer(port: UInt16(tcpServerPort), actionOnNewConnection: { newConnection in
            print("New connection to AIS server: \(newConnection.connectionName)")
        })
        outputServer?.startServer()
    }
    
    let sdr: RTLSDR = try {
        if sdrHost != nil {
            return try RTLSDR_TCP(host: sdrHost!, port: sdrPort!)
        }
        return try RTLSDR_USB(deviceIndex: sdrDeviceIndex)
    }()
    defer {
        sdr.stopAsyncRead()
    }
    
    try sdr.setCenterFrequency(AIS_CENTER_FREQUENCY)
    try sdr.setDigitalAGCEnabled(useDigitalAGC)
    try sdr.setSampleRate(DEFAULT_SAMPLE_RATE)
    try? sdr.setTunerBandwidth(bandwidth) // This won't work on RTLSDR_TCP because it's not implemented yet
    let channelAReciever = try AISReceiver(inputSampleRate: DEFAULT_SAMPLE_RATE, channel: .A, debugOutput: debugOutput)
    let channelBReciever = try AISReceiver(inputSampleRate: DEFAULT_SAMPLE_RATE, channel: .B, debugOutput: debugOutput)
    
    var inputBuffer: [DSPComplex] = []
    
    sdr.asyncReadSamples(callback: { (inputData) in
        guard inputData.count > 16 else {
            if(debugOutput) {
                print("inputData too short, skipping")
            }
            return
        }
        var timer = TimeOperation(operationName: "handleInput")
        inputBuffer.append(contentsOf: inputData)
        if(inputBuffer.count >= MIN_BUFFER_LEN) {
            inputDataToRecievers(inputBuffer, receiverA: channelAReciever, receiverB: channelBReciever)
            inputBuffer = []
        }
        if(debugOutput) {
            print(timer.stop() + "(\(inputData.count) samples)")
        }
    })
    
    while(true) {
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
        if input.lowercased() == "q" {
            sdr.stopAsyncRead()
            exit(0)
        }
    }
}

@MainActor func inputDataToRecievers(_ inputData: [DSPComplex], receiverA: AISReceiver, receiverB: AISReceiver) {
    var channelABuffer: [DSPComplex] = .init(repeating: DSPComplex(real: 0, imag: 0), count: inputData.count)
    var channelBBuffer: [DSPComplex] = .init(repeating: DSPComplex(real: 0, imag: 0), count: inputData.count)
    shiftFrequencyToBasebandHighPrecision(rawIQ: inputData, result: &channelABuffer, frequency: Float(CHANNEL_A_OFFSET), sampleRate: DEFAULT_SAMPLE_RATE)
    shiftFrequencyToBasebandHighPrecision(rawIQ: inputData, result: &channelBBuffer, frequency: Float(CHANNEL_B_OFFSET), sampleRate: DEFAULT_SAMPLE_RATE)
    let channelASentences = receiverA.processSamples(channelABuffer)
    let channelBSentences = receiverB.processSamples(channelBBuffer)
    for sentence in channelASentences {
        handleSentence(sentence)
    }
    for sentence in channelBSentences {
        handleSentence(sentence)
    }
}

@MainActor func handleSentence(_ sentence: AISSentence) {
    guard sentence.packetIsValid else { return }
    
    if(outputValidSentencesToConsole) {
        print(sentence)
    }
    
    if let server = outputServer {
        do {
            try server.broadcastMessage(sentence.description)
        }
        catch {
            print("Failed to broadcast message: \(error)")
        }
    }
}
