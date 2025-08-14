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

final class TCPServer {
    let name: String
    let port: UInt16
    let listener: NWListener
    let maxConnections: UInt8
    let dedicatedQueue: DispatchQueue
    let queueKey: DispatchSpecificKey<Void>
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
        self.queueKey = DispatchSpecificKey<Void>()
        dedicatedQueue.setSpecific(key: queueKey, value: ())
        self.actionOnReceive = actionOnReceive
        
        listener.stateUpdateHandler = actionOnStateUpdate ?? getDefaultStateUpdateHandler()
        listener.newConnectionHandler = buildNewConnectionHandler(userDefinedHandler: actionOnNewConnection)
        listener.newConnectionLimit = Int(maxConnections)
        
    }
    
    /// Send a message to every connection in the connections list.
    /// To-do: Change this so that one message erroring out doesn't stop the whole thing.
    func broadcastMessage(_ message: String) throws {
        try onQueueSync {
            for connection in connections {
                try connection.value.sendData(message)
            }
        }
    }
    
    func sendMessage(connection: String, message: String) throws {
        try onQueueSync {
            guard let connection = connections[connection] else { throw TCPServerErrors.connectionNonexistent }
            try connection.sendData(message)
        }
    }
    
    func startServer() {
        onQueueSync {
            if(listener.state == .setup || listener.state == .cancelled) {
                listener.start(queue: dedicatedQueue)
            }
            else {
                print("Can't start server. Server is already running.")
            }
        }
    }
    
    func stopListening() {
        onQueueSync {
            listener.cancel()
        }
    }
    
    /// Closes connections, then stops listening.
    func stopServer() {
        onQueueSync {
            for connection in connections {
                connection.value.closeConnection()
            }
            self.stopListening()
        }
    }
    
    /// Lets the user define an action to be taken when a new connection is made.
    /// Wraps user-defined function (works with TCPConnection instance) in a function that can be used by TCPServer (works with new NWConnection)
    /// Potential footgun here: If user changes the stateUpdateHandler on the new connection, it won't properly remove itself from the server once closed.
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
    
    /// Builds the receive handler for a new TCPConnection.
    /// Simply calls user-defined callback w/ data. To facilitate writing callbacks that respond to a message, the connection name is pulled in, allowing a subsequent call to sendMessage.
    private func buildReceiveHandler(name: String) -> (@Sendable (Data) -> Void) {
        let rxAction = self.actionOnReceive ?? { _, _ in }
        return { data in
            rxAction(name, data)
        }
    }
    
    /// Builds state update handler for a new TCPConnection.
    /// Primary function being that the conncetion will remove itself from the server's list once closed.
    /// As noted above, user could break this by overwriting this within their newConnectionHandler
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
    
    /// Default state update handler for TCPServer's NWListener. Simply prints new state.
    private func getDefaultStateUpdateHandler() -> @Sendable (NWListener.State) -> Void {
        let name = self.name
        return { newState in
            print("\(name): listener state changed to \(newState)")
        }
    }
    
    func addConnection(connection: TCPConnection) {
        _ = onQueueSync {
            self.connections.updateValue(connection, forKey: connection.connectionName)
        }
    }
    
    func removeConnection(connectionName: String) {
        onQueueSync {
            print("\(self.name) removing connection: \(connectionName)")
            self.connections.removeValue(forKey: connectionName)
        }
    }
    
    private static func getServerName(port: UInt16) -> String {
        return "TCPServer:\(port)"
    }
    
    /// For ensuring inorder operations.
    /// Checks if being called on the dedicatedQueue already to prevent deadlock.
    private func onQueueSync<T>(_ execute: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: self.queueKey) != nil {
            return try execute()
        }
        return try self.dedicatedQueue.sync(execute: execute)
    }
    
    private func onQueueAsync(_ execute: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: self.queueKey) != nil {
            return execute()
        }
        self.dedicatedQueue.async(execute: execute)
    }
    
}
