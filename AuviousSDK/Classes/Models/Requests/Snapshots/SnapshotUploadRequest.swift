//
//  SnapshotUploadRequest.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 03/06/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

class SnapshotUploadRequest {
    
    var snapshot: UIImage!
    var snapshotId: String!
    var snapshotSuffix: String!
    var snapshotType: String!
    var userEndpointId: String!
    var userId: String!
    
    init(snapshot: UIImage, id: String, suffix: String, type: String, userEndpointId: String, userId: String) {
        self.snapshot = snapshot
        self.snapshotId = id
        self.snapshotSuffix = suffix
        self.snapshotType = type
        self.userEndpointId = userEndpointId
        self.userId = userId
    }
    
}
