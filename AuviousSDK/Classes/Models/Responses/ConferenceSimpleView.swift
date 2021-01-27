//
//  ConferenceSimpleView.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public final class ConferenceSimpleView: NSObject {
    
    public var id: String!
    var mode: ConferenceMode!
    public var participants: [ConferenceParticipant]!
    var version: Int!
    
    //Tracks that are initially muted
    var mutedVideoTracks: [String] = []
    var mutedAudioTracks: [String] = []
    //Conference on hold
    var onHold: Bool = false
    
    init(fromJson json: JSON!) {
        if json == JSON.null {
            return
        }
        
        id = json["id"].stringValue
        if let tempMode = ConferenceMode(rawValue: json["mode"].stringValue) {
            mode = tempMode
        } else {
            mode = ConferenceMode.unknown
        }
        
        let tmpParticipants = json["participants"].arrayValue
        participants = [ConferenceParticipant]()
        for item in tmpParticipants {
            participants.append(ConferenceParticipant(fromJson: item))
        }
        
        version = json["version"].intValue
        
        //Parse metadata
        for (key, subJson): (String, JSON) in json["metadata"] {
            if key.starts(with: "TRACK_MUTED") {
                let parts = key.split(separator: "/")
                if parts.count == 3 {
                    if parts[1] == "video" {
                        mutedVideoTracks.append(String(parts[2]))
                    } else {
                        mutedAudioTracks.append(String(parts[2]))
                    }
                }
            } else if key.starts(with: "ON_HOLD") {
                onHold = true
            }
        }
    }
}
