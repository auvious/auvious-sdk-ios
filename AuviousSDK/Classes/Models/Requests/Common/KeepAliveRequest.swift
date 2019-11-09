//
//  KeepAliveRequest.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 29/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

internal final class KeepAliveRequest {
    
    var userEndpointId: String!
    var userId: String!
    
    init(userEndpointId: String, userId: String) {
        self.userEndpointId = userEndpointId
        self.userId = userId
    }
    
    func toDictionary() -> [String:Any] {
        var dictionary = [String:Any]()
        
        if userEndpointId != nil {
            dictionary["userEndpointId"] = userEndpointId
        }
        
        if userId != nil {
            dictionary["userId"] = userId
        }
        
        return dictionary
    }
}
