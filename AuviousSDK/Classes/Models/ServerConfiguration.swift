//
//  ServerUrls.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 26/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

/**
 This struct defines the server configuration. Will be removed.
 */
public struct ServerConfiguration {
    //REST
    static var baseRTC = "https://rtc-demo.stg.auvious.com/"
    static var baseMeeting = "https://staging-meeting.auvious.com"
    static let httpClientId = "staging-meeting"
    //MQTT
    static var mqttHost = "wss://events.stg.auvious.com/ws"
    static var mqttUser = ""
    static let mqttPass = ""
    //RTC
    static var iceServers : [RTCIceServer] = []
}
