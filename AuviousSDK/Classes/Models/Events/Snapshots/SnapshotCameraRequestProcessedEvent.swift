//
//  SnapshotCameraRequestProcessedEvent.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 30/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public class SnapshotCameraRequestProcessedEvent: SnapshotEvent {
    
    var additionalInformation: String!
    var snapshotCameraRequestId: String!
    var succeeded: Bool!
    
    /// Initialiser using a JSON object
    internal override init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        additionalInformation = json["additionalInformation"].stringValue
        snapshotCameraRequestId = json["snapshotCameraRequestId"].stringValue
        succeeded = json["succeeded"].boolValue
    }
}
