//
//  SnapshotApprovedEvent.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 30/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public class SnapshotApprovedEvent: SnapshotEvent {
    
    var snapshotId: String!
    var snapshotLocation: String!
    var snapshotType: String!
    
    /// Initialiser using a JSON object
    internal override init(fromJson json: JSON!){
        super.init(fromJson: json)
        
        snapshotId = json["snapshotId"].stringValue
        snapshotLocation = json["snapshotLocation"].stringValue
        snapshotType = json["snapshotType"].stringValue
    }
}
