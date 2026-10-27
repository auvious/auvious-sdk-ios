//
//  Log.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 28/10/20.
//

import os

private let subsystem = "AuviousSDK"

public struct Log {
    //Low level
    public static let api = OSLog(subsystem: subsystem, category: "API")
    public static let mqtt = OSLog(subsystem: subsystem, category: "MQTT")
    public static let rtc = OSLog(subsystem: subsystem, category: "RTC")
    public static let auth = OSLog(subsystem: subsystem, category: "Authentication")
    
    //SDK Level
    public static let conferenceSDK = OSLog(subsystem: subsystem, category: "Conference SDK")
    
    //UI Level
    public static let conferenceUI = OSLog(subsystem: subsystem, category: "Conference UI")
    public static let callUI = OSLog(subsystem: subsystem, category: "Conference UI")
    
    //Client level
    public static let conferenceApp = OSLog(subsystem: subsystem, category: "Conference App")
}
