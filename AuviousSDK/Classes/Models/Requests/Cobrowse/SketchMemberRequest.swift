//
//  SketchMemberRequest.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import Foundation

/// Body used to join an existing sketch (`PUT api/sketch/{id}`).
internal final class SketchMemberRequest {
    
    var userId: String
    var userEndpointId: String
    
    init(userId: String, userEndpointId: String) {
        self.userId = userId
        self.userEndpointId = userEndpointId
    }
    
    func toDictionary() -> [String:Any] {
        return ["userId": userId, "userEndpointId": userEndpointId]
    }
}
