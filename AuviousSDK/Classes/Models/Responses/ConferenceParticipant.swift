//
//  ConferenceParticipant.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public final class ConferenceParticipant {
    
    public var id: String!
    public var endpoints: [ParticipantEndpoint]!
    
    init(fromJson json: JSON!) {
        if json == JSON.null {
            return
        }
        
        id = json["id"].stringValue
        let tmpEndpoints = json["endpoints"].arrayValue
        endpoints = [ParticipantEndpoint]()
        for item in tmpEndpoints {
            endpoints.append(ParticipantEndpoint(fromJson: item))
        }
    }
}
