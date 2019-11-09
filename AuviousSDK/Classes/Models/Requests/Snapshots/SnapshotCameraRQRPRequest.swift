//
//  SnapshotCameraRQRPRequest.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 31/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

internal final class SnapshotCameraRQRPRequest {
    
    var additionalInformation: String!
    var snapshotCameraRequestId: String!
    var succeeded: Bool!
    var userEndpointId: String!
    var userId: String!
    
    init(info: String, snapshotCameraRequestId: String, succeeded: Bool, userEndpointId: String, userId: String) {
        self.additionalInformation = info
        self.snapshotCameraRequestId = snapshotCameraRequestId
        self.succeeded = succeeded
        self.userEndpointId = userEndpointId
        self.userId = userId
    }
    
    func toDictionary() -> [String: Any] {
        var dictionary = [String: Any]()
        
        if additionalInformation != nil {
            dictionary["additionalInformation"] = additionalInformation
        }
        
        if snapshotCameraRequestId != nil {
            dictionary["snapshotCameraRequestId"] = snapshotCameraRequestId
        }
        
        if succeeded != nil {
            dictionary["succeeded"] = succeeded
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
