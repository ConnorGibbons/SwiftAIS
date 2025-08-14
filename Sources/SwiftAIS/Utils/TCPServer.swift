//
//  TCPServer.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 7/9/25.
//

import Network
import Foundation

enum TCPServerErrors: Error {
    case portNotAvailable
    case connectionNonexistent
}

class TCPServer {
    let name: String
    let port: UInt16
    let listener: NWListener
    let maxConnections: UInt8
    let dedicatedQueue: DispatchQueue
    private var connections: [String: TCPConnection]
    var connectionCount: Int {
        return connections.count
    }
    
    let actionOnReceive: (@Sendable (String, Data) -> Void)?
    
    init(port: UInt16, maxConnections: UInt8 = 10, actionOnReceive: (@Sendable (String, Data) -> Void)? = nil, actionOnStateUpdate: (@Sendable (NWListener.State) -> Void)? = nil, actionOnNewConnection: (@Sendable (TCPConnection) -> Void)? = nil) throws {
        
        let params = NWParameters.tcp
        let options = params.defaultProtocolStack.transportProtocol as! NWProtocolTCP.Options
        options.enableKeepalive = true
        options.keepaliveIdle = 3
        options.keepaliveInterval = 1
        options.keepaliveCount = 5
        
        guard let port = NWEndpoint.Port(rawValue: port) else { throw TCPServerErrors.portNotAvailable }
        let listener = try NWListener(using: params, on: port)
        
        self.connections = [:]
        self.listener = listener
        self.port = port.rawValue
        self.maxConnections = maxConnections
        self.name = TCPServer.getServerName(port: port.rawValue)
        self.dedicatedQueue = DispatchQueue(label: "\(name).dedicatedQueue")
        self.actionOnReceive = actionOnReceive
        
        listener.stateUpdateHandler = actionOnStateUpdate ?? getDefaultStateUpdateHandler()
        listener.newConnectionHandler = buildNewConnectionHandler(userDefinedHandler: actionOnNewConnection)
        listener.newConnectionLimit = Int(maxConnections)
        
    }
    
    func broadcastMessage(_ message: String) throws {
        for connection in connections {
            try connection.value.sendData(message)
        }
    }
    
    func sendMessage(connection: String, message: String) throws {
        guard let connection = connections[connection] else { throw TCPServerErrors.connectionNonexistent }
        try connection.sendData(message)
    }
    
    func startServer() {
        if(listener.state == .setup || listener.state == .cancelled) {
            listener.start(queue: dedicatedQueue)
        }
        else {
            print("Can't start server. Server is already running.")
        }
    }
    
    func stopListening() {
        listener.cancel()
    }
    
    func stopServer() {
        dedicatedQueue.sync {
            for connection in connections {
                connection.value.closeConnection()
            }
        }
        self.stopListening()
    }
    
    private func buildNewConnectionHandler(userDefinedHandler: (@Sendable (TCPConnection) -> Void)?) -> (@Sendable (NWConnection) -> Void) {
        return { connection in
            let connectionName = TCPConnection.getConnectionName(endpoint: connection.endpoint)
            let newConnection = TCPConnection(connection: connection, receiveHandler: self.buildReceiveHandler(name: connectionName), stateUpdateHandler: self.buildConnectionStateUpdateHandler(name: connectionName, serverName: self.name))
            newConnection.startConnection()
            self.addConnection(connection: newConnection)
            if let userHandler = userDefinedHandler {
                userHandler(newConnection)
            }
        }
    }
    
    private func buildReceiveHandler(name: String) -> (@Sendable (Data) -> Void) {
        let rxAction = self.actionOnReceive ?? { _, _ in }
        return { data in
            rxAction(name, data)
        }
    }
    
    private func buildConnectionStateUpdateHandler(name: String, serverName: String) -> @Sendable (NWConnection.State) -> Void {
        return { state in
            switch state {
            case .cancelled:
                self.removeConnection(connectionName: name)
            case .failed(let err):
                print("TCPServer (\(serverName)): \(name): connection failed with error \(err)")
            default:
                break
            }
        }
    }
    
    private func getDefaultStateUpdateHandler() -> @Sendable (NWListener.State) -> Void {
        let name = self.name
        return { newState in
            print("\(name): listener state changed to \(newState)")
        }
    }
    
    func addConnection(connection: TCPConnection) {
        self.connections.updateValue(connection, forKey: connection.connectionName)
    }
    
    func removeConnection(connectionName: String) {
        print("\(self.name) removing connection: \(connectionName)")
        self.connections.removeValue(forKey: connectionName)
    }
    
    private static func getServerName(port: UInt16) -> String {
        return "TCPServer:\(port)"
    }
    
}
