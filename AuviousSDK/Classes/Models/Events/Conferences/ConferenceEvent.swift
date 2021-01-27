//
//  ConferenceEvent.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

/**
    Base class for all conference events.
*/
public class ConferenceEvent: NSObject {
    
    /// Conference id
    public var conferenceId: String!
    
    /// Conference version
    internal var conferenceVersion: Int?
    
    /// Event id
    public var id: String!
    
    /// Event timestamp
    public var timestamp: Date!
    
    /// Event type
    public var type: ConferenceEventType!
    
    /// Event type, as returned from the API
    public var typeDescription: String!
    
    /// The endpoint of the user that initiated this event
    public var userEndpointId: String!
    
    /// The user id that initiated this event
    public var userId: String!
    
    /// Used internally to check the number of times we have attempted to process this event
    internal var processedTimes: Int = 0
    
    /// Initialiser using a JSON object
    internal init(fromJson json: JSON!){
        if json == JSON.null {
            return
        }
        
        conferenceId = json["conferenceId"].stringValue
        conferenceVersion = json["conferenceVersion"].int
        id =  json["id"].stringValue
        
        let tmpDate = json["timestamp"].stringValue
        if let obj = Utilities.eventDateFormatter.date(from: tmpDate) {
            timestamp = obj
        }
        
        typeDescription = json["type"].stringValue
        if let tempType = ConferenceEventType(rawValue: json["type"].stringValue) {
            type = tempType
        } else {
            type = .conferenceUnknownEvent
        }
        
        userEndpointId = json["userEndpointId"].stringValue
        userId = json["userId"].stringValue
    }
}
