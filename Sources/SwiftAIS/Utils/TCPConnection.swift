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
    case unsupportedData
}

final class TCPConnection {
    private let connection: NWConnection
    private let endpoint: NWEndpoint
    private let dedicatedQueue: DispatchQueue
    
    let connectionName: String
    
    var sendHandler: @Sendable (NWError?) -> Void
    var receiveHandler: @Sendable (Data?) -> Void
    
    var state: NWConnection.State {
        return connection.state
    }
    
    var connectionActive: Bool {
        return state == .preparing || state == .ready
    }
    
    init(hostname: String, port: Int, sendHandler: (@Sendable (NWError?) -> Void)? = nil, receiveHandler: (@Sendable (Data) -> Void)? = nil, stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)? = nil) throws {
        
        let port = NWEndpoint.Port(rawValue: UInt16(port))
        let host = NWEndpoint.Host(hostname)
        
        guard port != nil else {
            throw TCPConnectionErrors.invalidPort
        }
        let endpoint = NWEndpoint.hostPort(host: host, port: port!)
        
        let parameters = NWParameters.tcp
        self.endpoint = endpoint
        self.connection = NWConnection(to: endpoint, using: parameters)
        self.dedicatedQueue = DispatchQueue(label: "tcp.\(hostname).\(port!)", qos: .userInitiated)
        self.connectionName = TCPConnection.getConnectionName(endpoint: endpoint)
        
        if let txHandler = sendHandler {
            self.sendHandler = txHandler
        } else {
            self.sendHandler = TCPConnection.buildDefaultSendCompletion(name: connectionName)
        }
        
        if let rxHandler = receiveHandler {
            self.receiveHandler = TCPConnection.buildReceiveCompletion(userDefinedHandler: rxHandler, name: connectionName)
        } else {
            self.receiveHandler = TCPConnection.buildDefaultReceiveCompletion(name: connectionName)
        }
        
        if let stateHandler = stateUpdateHandler {
            setStateUpdateHandler(stateHandler)
        } else {
            setStateUpdateHandler(TCPConnection.defaultStateUpdateHandler(name: connectionName))
        }
        
    }
    
    init(connection: NWConnection, sendHandler: (@Sendable (NWError?) -> Void)? = nil, receiveHandler: (@Sendable (Data) -> Void)? = nil, stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)? = nil) {
        self.connection = connection
        self.endpoint = connection.endpoint
        self.dedicatedQueue = DispatchQueue(label: "tcp.\(connection.endpoint)")
        self.connectionName = TCPConnection.getConnectionName(endpoint: connection.endpoint)
        
        if let txHandler = sendHandler {
            self.sendHandler = txHandler
        } else {
            self.sendHandler = TCPConnection.buildDefaultSendCompletion(name: connectionName)
        }
        
        if let rxHandler = receiveHandler {
            self.receiveHandler = TCPConnection.buildReceiveCompletion(userDefinedHandler: rxHandler, name: connectionName)
        } else {
            self.receiveHandler = TCPConnection.buildDefaultReceiveCompletion(name: connectionName)
        }
        
        if let stateHandler = stateUpdateHandler {
            setStateUpdateHandler(stateHandler)
        } else {
            setStateUpdateHandler(TCPConnection.defaultStateUpdateHandler(name: connectionName))
        }
        
    }
    
    func startConnection() {
        self.connection.start(queue: self.dedicatedQueue)
        setupReceive()
    }
    
    private func setupReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: .max, completion: { [weak self] content,contentContext,isComplete,error in
            guard let self = self else { return }
            self.receiveHandler(content)
            guard error == nil else {
                print("TCPConnection (\(self.connectionName)) Stopped receive loop due to error: \(String(describing: error))")
                return
            }
            guard isComplete == false else {
                print("TCPConnection (\(self.connectionName)) Stopped receive loop: final message received.")
                return
            }
            self.setupReceive()
        })
    }
    
    func setStateUpdateHandler(_ handler: @escaping @Sendable (NWConnection.State) -> Void) {
        connection.stateUpdateHandler = handler
    }
    
    func sendData(_ string: String) throws {
        if let data = string.data(using: .utf8) {
            guard state == .ready else { throw TCPConnectionErrors.connectionNotReady }
            connection.send(content: data, completion: .contentProcessed(sendHandler))
        }
        else {
            throw TCPConnectionErrors.unsupportedData
        }
    }
    
    func closeConnection() {
        if state != .cancelled {
            connection.cancel()
        }
    }
    
    private static func buildReceiveCompletion(userDefinedHandler: @Sendable @escaping (Data) -> Void, name: String) -> @Sendable (Data?) -> Void {
        let newHandler: @Sendable (Data?) -> Void = { rxData in
            if let data = rxData {
                userDefinedHandler(data)
            }
        }
        return newHandler
    }
    
    private static func buildDefaultReceiveCompletion(name: String) -> @Sendable (Data?) -> Void {
        let connectionName = name
        let newHandler: @Sendable (Data?) -> Void = { rxData in
            if(rxData != nil) {
                print("TCPConnection (\(connectionName)) received data: \(String(data: rxData!, encoding: .utf8) ?? "Unreadable data")")
            }
        }
        return newHandler
    }
    
    private static func defaultStateUpdateHandler(name: String) -> @Sendable (NWConnection.State) -> Void {
        { state in
            print("TCPConnection (\(name)) state updated to \(state)")
        }
    }
    
    private static func buildDefaultSendCompletion(name: String) -> @Sendable (NWError?) -> Void {
        let connectionName = name
        return { error in
            if let error = error {
                print("TCPConnection (\(connectionName)) failed to send data: \(error)")
            }
        }
    }
    
    static func getConnectionName(endpoint: NWEndpoint) -> String {
        let name = {
            return switch endpoint {
            case .hostPort(let host, let port):
                switch host {
                case .ipv4(let ipAddress):
                    "\(ipAddress):\(port)"
                case .ipv6(let ipAddress):
                    "[\(ipAddress)]:\(port)"
                case .name(let nx, _):
                    "\(nx):\(port)"
                default:
                    "Unknown host (\(String(describing: host))):\(port))"
                }
            case .service(_, _, _, _):
                "Unknown endpoint"
            case .unix(_):
                "Unknown endpoint"
            case .url( _):
                "Unknown endpoint"
            case .opaque(_):
                "Unknown endpoint"
            default:
                "Unknown endpoint"
            }
        }()
        return name
    }
    
    deinit {
        self.closeConnection()
    }
    
}
