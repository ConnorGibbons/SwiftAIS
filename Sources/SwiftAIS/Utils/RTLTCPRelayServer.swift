//
//  RTLTCPRelayServer.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 10/20/25.
//
import TCPUtils
import RTLSDRWrapper
import Foundation

class RTLTCPRelayServer {
    var server: TCPServer?
    var sdr: RTLSDR_TCP?
    var port: UInt16
    
    init(port: UInt16) {
        self.port = port
        self.server = nil
        self.sdr = nil
    }
    
    func associateSDR(sdr: RTLSDR_TCP) {
        self.sdr = sdr
    }
    
    func handleSDRData(data: Data) {
        guard let server = server else { return }
        do {
            try server.broadcastMessage(data)
        }
        catch {
            print("RelayServer: Failed to broadcast data: \(error)")
        }
    }
    
    func handleCommand(data: Data) {
        guard let sdr = sdr else { return }
        do {
            try sdr.sendRawData(data)
        }
        catch {
            print("RelayServer: Failed to send command to SDR: \(error)")
        }
    }
    
    func start() throws {
        if server != nil { return }
        self.server = try TCPServer(port: port, maxConnections: 5, actionOnReceive: { name,data in self.handleCommand(data: data) } )
        server?.startServer()
    }
    
}
