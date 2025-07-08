//
//  TCPConnection.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 7/3/25.
//
import Foundation
import Network

enum TCPConnectionErrors: Error {
    case invalidIP
    case invalidPort
    case connectionNotReady
}

struct IPv4Address {
    let ip: String
    
    init(ip: String) throws {
        self.ip = ip
        guard checkValidity() else { throw TCPConnectionErrors.invalidIP }
    }
    
    func checkValidity() -> Bool {
        let octets = ip.split(separator: ".")
        guard octets.count == 4 else { return false }
        for octet in octets {
            let octetValue = Int(octet) ?? -1
            if(octetValue < 0 || octetValue > 255) {
                return false
            }
        }
        return true
    }
    
}


struct TCPConnection {
    let ip: IPv4Address
    var hostDomain: String?
    private let connection: NWConnection
    private let endpoint: NWEndpoint
    private let parameters: NWParameters
    private let dedicatedQueue: DispatchQueue
    var sendHandler: @Sendable (NWError?) -> Void
    var receiveHandler: @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
    
    var state: NWConnection.State {
        return connection.state
    }
    
    init(ip: String, port: Int, sendHandler: (@Sendable (NWError?) -> Void)? = nil, receiveHandler: (@Sendable (Data) -> Void)? = nil, stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)? = nil) throws {
        let port = NWEndpoint.Port(rawValue: UInt16(port))
        let host = NWEndpoint.Host(ip)
        self.hostDomain = nil
        guard port != nil else {
            throw TCPConnectionErrors.invalidPort
        }
        var ipAddressTempVar: IPv4Address
        var hostDomainTempVar: String?
        
        do {
            ipAddressTempVar = try IPv4Address(ip: ip)
            self.ip = try IPv4Address(ip: ip)
        }
        catch {
            ipAddressTempVar = try! IPv4Address(ip: "0.0.0.0")
            self.ip = try! IPv4Address(ip: "0.0.0.0")
            self.hostDomain = host.debugDescription
            hostDomainTempVar = host.debugDescription
        }
        
        self.parameters = NWParameters.tcp
        self.endpoint = NWEndpoint.hostPort(host: host, port: port!)
        self.connection = NWConnection(to: endpoint, using: parameters)
        self.dedicatedQueue = DispatchQueue(label: "tcp.\(ip).\(port!)", qos: .userInitiated)
        
        let name = TCPConnection.getConnectionName(ip: ipAddressTempVar, hostDomain: hostDomainTempVar)
        
        if let txHandler = sendHandler {
            self.sendHandler = txHandler
        } else {
            self.sendHandler = TCPConnection.buildDefaultSendCompletion(name: name)
        }
        
        if let rxHandler = receiveHandler {
            self.receiveHandler = TCPConnection.buildReceiveCompletion(userDefinedHandler: rxHandler, name: name)
        } else {
            self.receiveHandler = TCPConnection.buildDefaultReceiveCompletion(name: name)
        }
        
        connection.start(queue: dedicatedQueue)
        connection.stateUpdateHandler = { [self] newState in
            switch newState {
            case .ready:
                print("TCPConnection (\(ip)) is ready.")
                setupReceive()
            case .failed(let error):
                print("TCPConnection (\(ip)) failed with error: \(error)")
                connection.cancel()
            case .cancelled:
                print("TCPConnection (\(ip)) was cancelled.")
            case .waiting(let error):
                print("TCPConnection (\(ip)) is waiting with error: \(error)")
            default:
                break
            }
        }
        if let stateHandler = stateUpdateHandler {
            setStateUpdateHandler(stateHandler)
        }
        
    }
    
    private static func getConnectionName(ip: IPv4Address, hostDomain: String?) -> String {
        return "tcp_\(ip.ip == "0.0.0.0" ? (hostDomain ?? "invalid") : ip.ip)"
    }
    
    func setStateUpdateHandler(_ handler: @escaping @Sendable (NWConnection.State) -> Void) {
        connection.stateUpdateHandler = handler
    }
    
    func sendData(_ string: String) throws {
        let data = string.data(using: .utf8)!
        guard state == .ready else { throw TCPConnectionErrors.connectionNotReady }
        connection.send(content: data, completion: .contentProcessed(sendHandler))
    }
    
    func closeConnection() {
        if state != .cancelled {
            connection.cancel()
        }
    }
    
    private static func buildReceiveCompletion(userDefinedHandler: @Sendable @escaping (Data) -> Void, name: String) -> @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void {
        let connectionName = name
        let newHandler: @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void = {rxData,context,isComplete,err in
            if let error = err {
                print("TCPConnection (\(connectionName) failed to send data: \(error)")
                return
            }
            if let data = rxData {
                userDefinedHandler(data)
            }
        }
        return newHandler
    }
    
    private static func buildDefaultReceiveCompletion(name: String) -> @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void {
        let connectionName = name
        let newHandler: @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void = {rxData,context,isComplete,err in
            if let error = err {
                print("TCPConnection (\(connectionName)) failed to send data: \(error)")
                return
            }
            if let data = rxData {
                print("TCPConnection (\(connectionName)) received data: \(String(data: data, encoding: .utf8) ?? "Unreadable data")")
                print("Context: \(String(describing: context)), complete: \(isComplete)")
            }
        }
        return newHandler
    }
    
    private func setupReceive() {
        connection.receiveMessage(completion: {content,contentContext,isComplete,error in
            self.receiveHandler(content, contentContext, isComplete, error)
            self.setupReceive()
        })
    }
    
    private static func buildDefaultSendCompletion(name: String) -> @Sendable (NWError?) -> Void {
        let connectionName = name
        return { error in
            if let error = error {
                print("TCPConnection (\(connectionName)) failed to send data: \(error)")
            }
        }
    }
    
}
