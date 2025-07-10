//
//  SwiftAISTests.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/27/25.
//
import Testing
import Foundation
import SignalTools
import Accelerate
import Network
@testable import SwiftAIS

let ONE_SECOND_IN_NANOSECONDS: UInt64 = 1_000_000_000

class BoolWrapper: @unchecked Sendable{
    
    var value: Bool = false
    
    init(value: Bool) {
        self.value = value
    }
    
    func toggle() {
        value.toggle()
    }
    
    func getValue() -> Bool {
        return value
    }
}

// Should make the sentence: !AIVDM,1,1,,B,E>k`HC0VTah9QTb:Pb2h0ab0P00=N97j<4dDP00000<020,4*6F without having to do any error correction.
@Test func testSentence1() {
    
    do {
        guard let sentence1Path = Bundle.module.url(forResource: "sentence1", withExtension: "wav")?.path() else {
            print("Failed to find sentence1.wav -- did you delete the TestData folder?")
            assert(false)
        }
        let sentence1IQData = try readIQFromWAV16Bit(filePath: sentence1Path)
        var sentence1Shifted: [DSPComplex] = .init(repeating: DSPComplex(real: 0.0, imag: 0.0), count: sentence1IQData.count)
        shiftFrequencyToBasebandHighPrecision(rawIQ: sentence1IQData, result: &sentence1Shifted, frequency: 33000, sampleRate: 240000)
        let testReceiver = try AISReceiver(inputSampleRate: 240000, channel: .B)
        let prepocessed = testReceiver.preprocessor.processAISSignal(&sentence1Shifted)
        let sentence1 = try testReceiver.analyzeSamples(prepocessed, sampleRate: 48000)
        assert(sentence1 != nil)
        assert(String(describing: sentence1!) == "!AIVDM,1,1,,B,E>k`HC0VTah9QTb:Pb2h0ab0P00=N97j<4dDP00000<020,4*6F")
    }
    catch {
        assert(false , error.localizedDescription)
    }
    
    assert(true)
}

@Test func testEstablishTCPConnection() {
    let sem = DispatchSemaphore(value: 0)
    let connectionEstablished = BoolWrapper(value: false)
    let connection = try! TCPConnection(hostname:"tcpbin.com", port: 4242, stateUpdateHandler: { newState in
        if(newState == .ready) {
            connectionEstablished.toggle()
            sem.signal()
        }
    })
    connection.startConnection()
    Task.init {
        try! await Task.sleep(nanoseconds: ONE_SECOND_IN_NANOSECONDS)
        if(!connectionEstablished.getValue()) {
            print("Establishing test connection timed out.")
            assert(false)
        }
    }
    sem.wait()
}

@Test func testTCPConnectionSend() {
    let sem = DispatchSemaphore(value: 0)
    let connectionEstablished = BoolWrapper(value: false)
    
    let stateUpdateHandler: @Sendable (NWConnection.State) -> Void = { newState in
        if(newState == .ready) {
            connectionEstablished.toggle()
            sem.signal()
        }
    }
    
    let sendHandler: @Sendable (NWError?) -> Void = { error in
        if let error = error {
            print("Error sending data: \(error)")
            assert(false)
        }
        sem.signal()
    }
    
    let connection = try! TCPConnection(hostname: "tcpbin.com", port: 4242, sendHandler: sendHandler, stateUpdateHandler: stateUpdateHandler)
    Task.init {
        try! await Task.sleep(nanoseconds: ONE_SECOND_IN_NANOSECONDS)
        if(!connectionEstablished.getValue()) {
            print("Establishing test connection timed out.")
            assert(false)
        }
    }
    connection.startConnection()
    sem.wait()
    try! connection.sendData("Meow meow...")
    try! connection.sendData("Freak Pay!!!!")
    sem.wait()
    sem.wait()
}

@Test func testTCPConnectionReceive() {
    let sem = DispatchSemaphore(value: 0)
    
    let stateUpdateHandler: @Sendable (NWConnection.State) -> Void = { newState in
        if newState == .ready {
            print("Connection is ready.")
            sem.signal()
        }
        else {
            print("State updated to: \(newState)")
        }
    }
    
    let sendHandler: @Sendable (NWError?) -> Void = { error in
        assert(error == nil, "Send failed with error: \(error!)")
        print("Send complete.")
        sem.signal()
    }
    
    let receiveHandler: @Sendable (Data) -> Void = { data in
        print("Received data: \(String(data: data, encoding: .utf8) ?? "Non-string data")")
        sem.signal()
    }
    
    let connection = try! TCPConnection(
        hostname: "tcpbin.com",
        port: 4242,
        sendHandler: sendHandler,
        receiveHandler: receiveHandler,
        stateUpdateHandler: stateUpdateHandler
    )
    
    
    connection.startConnection()
    let semResult = sem.wait(timeout: .now() + 5)
    if(semResult == .timedOut) {
        print("Connection establishment timed out.")
        assert(false)
    }
    
    try! connection.sendData("Meow meow...\n")
    let semResult_send1 = sem.wait(timeout: .now() + 2)
    if(semResult_send1 == .timedOut) {
        print("Send 1 timed out.")
        assert(false)
    }
    let semResult_receive1 = sem.wait(timeout: .now() + 5)
    if(semResult_receive1 == .timedOut) {
        print("Receive 1 timed out.")
        assert(false)
    }
    connection.closeConnection()
}

@Test func testTCPServerAcceptsConnections() {
    let sem = DispatchSemaphore(value: 0)
    
    let receiveHandler: @Sendable (String, Data) -> Void = {
        print("\($0): \($1)")
        sem.signal()
    }
    
    let newConnectionHandler: @Sendable (TCPConnection) -> Void = { newConnection in
        print("New connection: \(newConnection.connectionName)")
        sem.signal()
    }
    
    let server = try! TCPServer(port: 62965, actionOnReceive: receiveHandler, actionOnNewConnection: newConnectionHandler)
    server.startServer()
    
    let clientStateHandler: @Sendable (NWConnection.State) -> Void = { newState in
        print("New TCP Client State: \(newState)")
        if(newState == .ready) {
            sem.signal()
        }
        if(newState == .cancelled) {
            sem.signal()
        }
    }
    
    let client = try! TCPConnection(hostname: "localhost", port: 62965, stateUpdateHandler: clientStateHandler)
    client.startConnection()
    let connectionResult = sem.wait(timeout: DispatchTime.now() + 0.5)
    if(connectionResult == .timedOut) {
        print("Establishing connection to server timed out.")
        assert(false)
    }
    let serverAcceptConnectionResult = sem.wait(timeout: DispatchTime.now() + 0.5)
    if(serverAcceptConnectionResult == .timedOut) {
        print("Server did not accept connection.")
        assert(false)
    }
    
    assert(server.connectionCount == 1)
    
    try! client.sendData("Hello server :)\n")
    let messageReceivedResult = sem.wait(timeout: DispatchTime.now() + 0.5)
    if(messageReceivedResult == .timedOut) {
        print("Server didn't receive message from client.")
        assert(false)
    }
}
