//
//  Log.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 28/10/20.
//

import os

private let subsystem = "AuviousSDK"

struct Log {
    //Low level
    static let api = OSLog(subsystem: subsystem, category: "API")
    static let mqtt = OSLog(subsystem: subsystem, category: "MQTT")
    static let rtc = OSLog(subsystem: subsystem, category: "RTC")
    static let auth = OSLog(subsystem: subsystem, category: "Authentication")
    static let callObserver = OSLog(subsystem: subsystem, category: "Call Observer")
    
    //SDK Level
    static let conferenceSDK = OSLog(subsystem: subsystem, category: "Conference SDK")
    static let callSDK = OSLog(subsystem: subsystem, category: "Call SDK")
    
    //UI Level
    static let conferenceUI = OSLog(subsystem: subsystem, category: "Conference UI")
    static let callUI = OSLog(subsystem: subsystem, category: "Conference UI")
    
    //Client level
    static let conferenceApp = OSLog(subsystem: subsystem, category: "Conference App")
    static let callApp = OSLog(subsystem: subsystem, category: "Call App")
}
