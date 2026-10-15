//
//  SendEventRequest.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import Foundation

/// Sends a user event to another user's endpoint via `rtc-api/users/endpoints/sendEvent`.
internal final class SendEventRequest {
    
    /// The target user id (username or 'sub' claim)
    var userId: String
    
    /// The target endpoint id. When nil, the event is delivered to all of the target user's active endpoints.
    var userEndpointId: String?
    
    /// The event payload, must contain at least `type` and `timestamp`
    var event: [String: Any]
    
    init(userId: String, userEndpointId: String?, event: [String: Any]) {
        self.userId = userId
        self.userEndpointId = userEndpointId
        self.event = event
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        dictionary["userId"] = userId
        dictionary["userEndpointId"] = userEndpointId ?? NSNull()
        dictionary["event"] = event
        return dictionary
    }
}
