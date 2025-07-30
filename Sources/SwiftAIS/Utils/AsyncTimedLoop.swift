//
//  AsyncTimedLoop.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 7/29/25.
//
import Foundation

class AsyncTimedLoop {
    private var timer: DispatchSourceTimer?
    private var callback: (() -> Void)
    
    
    init(callback: @escaping (() -> Void)) {
        self.callback = callback
    }
    
    func startTimedLoop(interval: TimeInterval) {
        let UUIDString = UUID().uuidString
        let loopQueue = DispatchQueue(label: "timedLoopQueue.\(UUIDString)")
        timer = DispatchSource.makeTimerSource(queue: loopQueue)
        timer?.schedule(deadline: .now(), repeating: interval)
        timer?.setEventHandler(handler: callback)
        timer?.resume()
    }
    
    func stopTimedLoop() {
        if let timer = timer {
            timer.cancel()
        }
    }
    
    deinit {
        if let timer = timer {
            timer.cancel()
        }
    }
    
}
