//
//  SwiftAISTests.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 6/27/25.
//
import XCTest
import Foundation
import SignalTools
import Accelerate
import Network
@testable import SwiftAIS
import RTLSDRWrapper

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

final class SwiftAISTests: XCTestCase {
    
    // Should make the sentence: !AIVDM,1,1,,B,E>k`HC0VTah9QTb:Pb2h0ab0P00=N97j<4dDP00000<020,4*6F without having to do any error correction.
    func testSentence1() {
        
        do {
            guard let sentence1Path = Bundle.module.url(forResource: "sentence1", withExtension: "wav")?.path() else {
                XCTFail("Failed to find sentence1.wav -- did you delete the TestData folder?")
                return
            }
            let sentence1IQData = try readIQFromWAV16Bit(filePath: sentence1Path)
            var sentence1Shifted: [DSPComplex] = .init(repeating: DSPComplex(real: 0.0, imag: 0.0), count: sentence1IQData.count)
            shiftFrequencyToBasebandHighPrecision(rawIQ: sentence1IQData, result: &sentence1Shifted, frequency: 33000, sampleRate: 240000)
            let seqIDGenerator = SequentialIDGenerator()
            let testReceiver = try AISReceiver(inputSampleRate: 240000, channel: .B, seqIDGenerator: seqIDGenerator)
            let preprocessed = testReceiver.preprocessor.processAISSignal(&sentence1Shifted)
            let sentence1 = try testReceiver.analyzeSamples(preprocessed, sampleRate: 48000)
            XCTAssertNotNil(sentence1)
            XCTAssertEqual(String(describing: sentence1!), "!AIVDM,1,1,,B,E>k`HC0VTah9QTb:Pb2h0ab0P00=N97j<4dDP00000<020,4*6F")
        }
        catch {
            XCTFail(String(describing: error))
            return
        }
        
    }
    
    func testEstablishTCPConnection() {
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
            XCTAssertTrue(connectionEstablished.getValue())
        }
        sem.wait()
    }
    
    func testTCPConnectionSend() {
        let sem = DispatchSemaphore(value: 0)
        let connectionEstablished = BoolWrapper(value: false)
        
        let stateUpdateHandler: @Sendable (NWConnection.State) -> Void = { newState in
            if(newState == .ready) {
                connectionEstablished.toggle()
                sem.signal()
            }
        }
        
        let sendHandler: @Sendable (NWError?) -> Void = { error in
            XCTAssertNil(error)
            sem.signal()
        }
        
        let connection = try! TCPConnection(hostname: "tcpbin.com", port: 4242, sendHandler: sendHandler, stateUpdateHandler: stateUpdateHandler)
        Task.init {
            try! await Task.sleep(nanoseconds: ONE_SECOND_IN_NANOSECONDS)
            XCTAssertTrue(connectionEstablished.getValue())
        }
        connection.startConnection()
        sem.wait()
        try! connection.sendData("Meow meow...")
        try! connection.sendData("Freak Pay!!!!")
        sem.wait()
        sem.wait()
    }
    
    func testTCPConnectionReceive() {
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
            XCTAssertNil(error, "Send failed with error: \(error!)")
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
        XCTAssertEqual(semResult, .success)
        
        try! connection.sendData("Meow meow...\n")
        let semResult_send1 = sem.wait(timeout: .now() + 2)
        XCTAssertEqual(semResult_send1, .success)
        
        let semResult_receive1 = sem.wait(timeout: .now() + 5)
        XCTAssertEqual(semResult_receive1, .success)
        
        connection.closeConnection()
    }
    
    func testTCPServerAcceptsConnections() {
        let sem = DispatchSemaphore(value: 0)
        
        let receiveHandler: @Sendable (String, Data) -> Void = {
            print("\($0): \(String(data: $1, encoding: .utf8) ?? "Unreadable data")")
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
        XCTAssertEqual(connectionResult, .success)
        
        let serverAcceptConnectionResult = sem.wait(timeout: DispatchTime.now() + 0.5)
        XCTAssertEqual(serverAcceptConnectionResult, .success)
        XCTAssertEqual(server.connectionCount, 1)
        
        try! client.sendData("Hello server :)\n")
        let messageReceivedResult = sem.wait(timeout: DispatchTime.now() + 0.5)
        XCTAssertEqual(messageReceivedResult, .success)
        
        client.closeConnection()
        server.stopServer()
    }
    
    func testCombinationsBySize() {
        let n = 20
        let k = 10
        let result = combinationsBySize(n: n, k: k)
        var currLayer = 0
        while(currLayer < k) {
            let currKValue = currLayer + 1
            let count = result[currLayer].count
            let desiredCount = factorial(n) / (factorial(currKValue)*factorial(n-currKValue))
            print("Layer \(currLayer): \(count)   (target: \(desiredCount))")
            XCTAssertEqual(count, desiredCount)
            XCTAssertTrue(elementsAreUnique(result[currLayer]))
            currLayer += 1
        }
    }
    
    func testNrziFlipBits() {
        let testBits: [UInt8] = [0,0,0,0,1]
        // nrzi bit flip should also flip every subsequent bit
        let flipped = nrziFlipBits(bits: testBits, positions: [0])
        XCTAssertEqual(flipped, [1,1,1,1,0])
        // nrzi bit flip is its own inverse
        XCTAssertEqual(nrziFlipBits(bits: flipped, positions: [0]), testBits)
        
        let testBits2: [UInt8] = [0,1,1,1,0]
        // Again, its own inverse so should do nothing if flipping same position twice
        let flipped2 = nrziFlipBits(bits: testBits2, positions: [0,0])
        XCTAssertEqual(testBits2, flipped2)
        
        let testBits3: [UInt8] = [0,0,0,0,0,0,0]
        let flipped3 = nrziFlipBits(bits: testBits3, positions: [0,3])
        XCTAssertEqual(flipped3, [1,1,1,0,0,0,0])
    }
    
    func testErrorCorrection() {
        let maxBitFlipCount = 5
        let testValidator = PacketValidator(maxBitFlipCount: maxBitFlipCount, debugOutput: true)
        
        // Corresponds to sentence: !AIVDM,1,1,,A,H52d3RPAD<f0AD<d00000000000,2*3C
        // Flipped bit must be in top (PacketValidator.cutoff -- currently 20) most likely candidates for correction to work.
        let correctPayloadBits: [UInt8] = [0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1]
        let certaintyMap: [(Float, Int)] = [(0.49211884, 98), (0.50839996, 134), (0.5321541, 158), (0.53243256, 114), (0.53507614, 94), (0.5393486, 96), (0.53982544, 82), (0.5493736, 143), (0.55163956, 83), (0.55182266, 132), (0.5518837, 156), (0.55537796, 124), (0.5573158, 135), (0.5585861, 47), (0.5703049, 66), (0.57457733, 123), (0.59033585, 108), (0.59371567, 2), (0.59664536, 68), (0.59881973, 29), (0.60250854, 8), (0.60271835, 146), (0.6089096, 95), (0.609745, 110), (0.61003876, 138), (0.6101074, 45), (0.61133194, 120), (0.6132927, 60), (0.6174431, 99), (0.6179085, 128), (0.620842, 67), (0.6249466, 144), (0.6252289, 46), (0.62561035, 142), (0.62564087, 149), (0.6314926, 133), (0.63396454, 84), (0.6356392, 136), (0.63734055, 28), (0.63739395, 129), (0.6390724, 148), (0.639904, 31), (0.6412468, 3), (0.6524544, 106), (0.657711, 126), (0.6581497, 122), (0.6601219, 32), (0.6637001, 155), (0.6638527, 115), (0.6640396, 118), (0.66635513, 116), (0.66722107, 16), (0.6703644, 97), (0.6719017, 7), (0.6741829, 130), (0.6752701, 140), (0.6777153, 145), (0.6790123, 10), (0.683403, 15), (0.6894798, 107), (0.6906395, 113), (0.6926613, 139), (0.6943474, 49), (0.6962776, 119), (0.69712067, 111), (0.6994705, 0), (0.7029495, 150), (0.70328903, 105), (0.7037964, 157), (0.70422363, 50), (0.7045708, 152), (0.7052345, 117), (0.70812225, 65), (0.7107239, 1), (0.7178917, 104), (0.72049713, 30), (0.7229233, 33), (0.7248268, 131), (0.7319336, 9), (0.7349129, 121), (0.73732376, 127), (0.73975754, 76), (0.7411308, 75), (0.74318695, 64), (0.743618, 147), (0.74370575, 137), (0.74929047, 100), (0.75988007, 102), (0.7671242, 69), (0.7679672, 101), (0.76893616, 112), (0.7735672, 42), (0.78134155, 48), (0.7832756, 87), (0.7885208, 125), (0.8035011, 154), (0.81230545, 103), (0.8135605, 38), (0.8233528, 141), (0.83319473, 109), (0.8405113, 151), (0.84825134, 153), (0.8706627, 88), (0.9625931, 41), (0.9763756, 77), (0.98770523, 20), (1.036686, 63), (1.0450401, 14), (1.0571823, 4), (1.063488, 92), (1.0744667, 61), (1.0799065, 74), (1.0835495, 17), (1.0852966, 36), (1.0864105, 81), (1.0884972, 35), (1.0898972, 44), (1.0905533, 91), (1.0934982, 51), (1.1104088, 89), (1.1120148, 19), (1.1134453, 159), (1.1175842, 43), (1.1177673, 58), (1.1186409, 70), (1.1443901, 72), (1.1455116, 55), (1.1489754, 27), (1.1553802, 57), (1.1595955, 37), (1.1626511, 53), (1.1647072, 22), (1.1665268, 11), (1.1764793, 39), (1.1783638, 85), (1.1798553, 93), (1.1882477, 21), (1.1889153, 86), (1.1922302, 40), (1.1968994, 59), (1.1978531, 34), (1.2021446, 79), (1.2068214, 6), (1.2177811, 12), (1.2201958, 73), (1.226448, 13), (1.2286949, 54), (1.2331047, 24), (1.2337914, 78), (1.2380257, 23), (1.2531662, 52), (1.5378189, 56), (1.541172, 5), (1.5489464, 26), (1.5566025, 18), (1.5900612, 25), (1.6197662, 80), (1.6240044, 62), (1.6246071, 71), (1.7783394, 90)]
        
        for i in 0...maxBitFlipCount {
            let errorIndicies = (0..<20).shuffled().prefix(i).map{ certaintyMap[$0].1 }
            var timer = TimeOperation(operationName: "Correcting \(i) bit errors")
            let erroredPayload = nrziFlipBits(bits: correctPayloadBits, positions: errorIndicies)
            let errorCorrectionResult = testValidator.correctErrors(bitsWithoutFlags: erroredPayload, certainties: certaintyMap)
            print(timer.stop())
            XCTAssertTrue(errorCorrectionResult.3)
            XCTAssertEqual(errorCorrectionResult.2, i)
            XCTAssertEqual(errorCorrectionResult.0, correctPayloadBits)
        }
        
    }
    
    func testSentenceSplitting() {
        // Example of a real multi-sentence AIS message.
        // This was **not** captured by SwiftAIS. I have yet to encounter one during testing, they seem to be rare.
        // !AIVDM,2,1,9,B,53nFBv01SJ<thHp6220H4heHTf2222222222221?50:454o<`9QSlUDp,0*09
        // !AIVDM,2,2,9,B,888888888888880,2*2E
        // The receiver that produced this seems to split at 76 characters instead of the maximum 82. I am unaware of the reason why.
        let longPayload = "53nFBv01SJ<thHp6220H4heHTf2222222222221?50:454o<`9QSlUDp888888888888880"
        let newSentence = AISSentence(sequentialID: 0, channel: .B, payloadBitstring: [], payloadASCII: longPayload, fillBits: 2, errorCorrectedBitsCount: 0, packetChecksum: 0, packetIsValid: true)
        let newSentenceNMEAOutput = newSentence.description
        let sentencesSplit = newSentenceNMEAOutput.split(separator: "\n")
        XCTAssertEqual(sentencesSplit.count, 2)
        XCTAssertTrue(sentencesSplit[0].count <= 82)
        XCTAssertTrue(sentencesSplit[1].count <= 82)
    }
    
    
    
}
