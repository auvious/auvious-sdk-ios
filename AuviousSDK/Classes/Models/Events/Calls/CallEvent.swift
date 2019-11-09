//
//  CallEvent.swift
//  AuviousSDK
//
//  Created by Jace on 04/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public class CallEvent: NSObject {
    
    public var aggregate: String!
    public var aggregateId: String!
    public var aggregateVersion: Int!
    public var callId: String!
    public var id: String!
    public var timestamp: String!
    public var type: CallEventType!
    public var userEndpointId: String!
    public var userId: String!
    
    internal init(fromJson json: JSON!){
        if json == JSON.null {
            return
        }
        
        aggregate = json["aggregate"].stringValue
        aggregateId = json["aggregateId"].stringValue
        aggregateVersion = json["aggregateVersion"].intValue
        callId = json["callId"].stringValue
        id = json["id"].stringValue
        timestamp = json["timestamp"].stringValue
        type = CallEventType(rawValue: json["type"].stringValue)
        userEndpointId = json["userEndpointId"].stringValue
        userId = json["userId"].stringValue
    }
}
