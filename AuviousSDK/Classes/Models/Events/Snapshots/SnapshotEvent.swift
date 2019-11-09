//
//  SnapshotEvent.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 30/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public class SnapshotEvent {
    
    var id: String!
    var userId: String!
    var userEndpointId: String!
    var timestamp: String!
    var type: SnapshotEventType!
    
    /// Initialiser using a JSON object
    internal init(fromJson json: JSON!){
        if json == JSON.null {
            return
        }
        
        id = json["id"].stringValue
        timestamp = json["timestamp"].stringValue
        type = SnapshotEventType(rawValue: json["type"].stringValue)  
        userEndpointId = json["userEndpointId"].stringValue
        userId = json["userId"].stringValue
    }
}
