//
//  SequentialIDGenerator.swift
//  SwiftAIS
//
//  Created by Connor Gibbons  on 8/11/25.
//
//  For generating Sequential ID's included in NMEA output. Required for payloads >82 chars.

import Foundation

class SequentialIDGenerator {
    var currentSequentialID: Int = 0
    var lock: NSLock = NSLock()
    
    init() {}
    
    func getNextSequentialID() -> Int {
        lock.lock()
        defer {
            self.currentSequentialID += 1
            if currentSequentialID >= 10 {
                self.currentSequentialID = 0
            }
            lock.unlock()
        }
        return self.currentSequentialID
    }
    
}
