//
//  UnregisterEndpointRequest.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 29/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

internal final class UnregisterEndpointRequest {
    
    var reason: String!
    var userEndpointId: String!
    var userId: String!
    
    init(reason: String, userEndpointId: String, userId: String) {
        self.reason = reason
        self.userEndpointId = userEndpointId
        self.userId = userId
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if reason != nil {
            dictionary["reason"] = reason
        }
        
        if userEndpointId != nil {
            dictionary["userEndpointId"] = userEndpointId
        }
        
        if userId != nil {
            dictionary["userId"] = userId
        }
        
        return dictionary
    }
}
