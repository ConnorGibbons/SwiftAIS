//
//  RTLTCPRelayServer.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 10/20/25.
//
import Networking
import Foundation

/// **Note: Functionality of this now limited as RTLSDRWrapper has been replaced.**
class RTLTCPRelayServer {
    var server: TCPServer?
//    var sdr: RTLSDR_TCP?
    var port: UInt16
    
    init(port: UInt16) {
        self.port = port
        self.server = nil
//        self.sdr = nil
    }
    
//    func associateSDR(sdr: RTLSDR_TCP) {
//        self.sdr = sdr
//    }
    
    func handleSDRData(data: Data) {
        guard let server = server else { return }
        server.broadcast(data: data)
    }
    
    func handleCommand(data: Data) {
//        guard let sdr = sdr else { return }
        return
        do {
//            try sdr.sendRawData(data)
        }
        catch {
            print("RelayServer: Failed to send command to SDR: \(error)")
        }
    }
    
    @Sendable func printNewConnection(connection: TCPConnection) -> Void {
        print("New relay server connection: \(connection.connectionName)")
    }
    
    func start() throws {
        if server != nil { return }
        self.server = try TCPServer(port: port, maxConnections: 5, actionOnNewConnection: printNewConnection, actionOnReceive: { name,data in self.handleCommand(data: data)})
    }
    
}
