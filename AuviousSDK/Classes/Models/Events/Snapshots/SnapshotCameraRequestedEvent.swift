//
//  SnapshotCameraRequestedEvent.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 30/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public class SnapshotCameraRequestedEvent: SnapshotEvent {
    
    var cameraRequestType: CameraRequestType!
    var snapshotCameraRequestId: String!
    var targetUserEndpointId: String!
    var targetUserId: String!
    
    /// Initialiser using a JSON object
    internal override init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        cameraRequestType = CameraRequestType(rawValue: json["cameraRequestType"].stringValue)
        snapshotCameraRequestId = json["snapshotCameraRequestId"].stringValue
        targetUserEndpointId = json["targetUserEndpointId"].stringValue
        targetUserId = json["targetUserId"].stringValue
    }
}
