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

// Args
var debugOutput: Bool = false
var offlineTest: Bool = false
var outputValidSentencesToConsole: Bool = false
var useDigitalAGC: Bool = false
var setupTCPServer: Bool = false
var tcpServerPort: UInt16 = 50050
var bandwidth: Int = 72000
var sdrDeviceIndex: Int = 0
var validSentences: [AISSentence] = []
var invalidSentences: [AISSentence] = []

var outputServer: TCPServer?


@MainActor func mapCLIArgsToVariables() {
    for argument in CommandLine.arguments.dropFirst() {
        if(argument.hasPrefix("-d")) {
            print("Debug output: Enabled.")
            debugOutput = true
        }
        else if(argument.hasPrefix("-ot")) {
            print("Performing offline decoding test...")
            offlineTest = true
        }
        else if(argument.hasPrefix("-n")) {
            print("Printing valid NMEA sentences to console: Enabled.")
            outputValidSentencesToConsole = true
        }
        else if(argument.hasPrefix("-agc")) {
            print("Digital AGC: Enabled.")
            useDigitalAGC = true
        }
        else if(argument.hasPrefix("-b")) {
            let inputSplit = argument.split(separator: " ")
            if(inputSplit.count < 1 || Int(inputSplit[1]) == nil || Int(inputSplit[1])! < 3000 || Int(inputSplit[1])! > 200000) {
                print("Bandwidth out of range ([3000, 200000]), using default \(bandwidth)")
                continue
            }
            bandwidth = Int(inputSplit[1])!
        }
        else if(argument.hasPrefix("-di")) {
            let inputSplit = argument.split(separator: " ")
            if(inputSplit.count < 1 || Int(inputSplit[1]) == nil) {
                print("The provided rtl-sdr device index was invalid")
                continue
            }
            sdrDeviceIndex = Int(inputSplit[1])!
        }
        else if(argument.hasPrefix("-tcp")) {
            let inputSplit = argument.split(separator: " ")
            if(inputSplit.count < 1 || Int(inputSplit[1]) == nil) {
                print("The provided TCP server port was invalid.")
                continue
            }
            setupTCPServer = true
            tcpServerPort = UInt16(inputSplit[1])!
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
        outputServer = try TCPServer(port: UInt16(tcpServerPort), actionOnNewConnection: { newConnection in
            print("New connection to AIS server: \(newConnection.connectionName)")
        })
    }
    
    let sdr = try RTLSDR(deviceIndex: sdrDeviceIndex)
    try sdr.setCenterFrequency(AIS_CENTER_FREQUENCY)
    try sdr.setDigitalAGC(useDigitalAGC)
    try sdr.setSampleRate(DEFAULT_SAMPLE_RATE)
    try sdr.setTunerBandwidth(bandwidth)
    let channelAReciever = try AISReceiver(inputSampleRate: DEFAULT_SAMPLE_RATE, channel: .A, debugOutput: debugOutput)
    let channelBReciever = try AISReceiver(inputSampleRate: DEFAULT_SAMPLE_RATE, channel: .B, debugOutput: debugOutput)
    
    sdr.asyncReadSamples(callback: { (inputData) in
        let t0_handleSamples = Date().timeIntervalSinceReferenceDate
        inputDataToRecievers(inputData, receiverA: channelAReciever, receiverB: channelBReciever)
        let t1_handleSamples = Date().timeIntervalSinceReferenceDate
        if(debugOutput) {
            print("Processing buffer (\((Double(inputData.count) / Double(DEFAULT_SAMPLE_RATE)))s) took \(t1_handleSamples - t0_handleSamples) seconds")
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
    if(sentence.packetIsValid && outputValidSentencesToConsole) {
        print(sentence)
    }
    if let server = outputServer {
        do {
            try server.broadcastMessage(sentence.description)
        }
        catch {
            print("Failed to broadcast NMEA sentence: \(error)")
        }
    }
}
