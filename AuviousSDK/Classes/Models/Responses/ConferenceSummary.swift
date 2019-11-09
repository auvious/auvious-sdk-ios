//
//  ConferenceSummary.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public final class ConferenceSummary {
    
    public var id: String!
    var mode: ConferenceMode!
    var version: Int!
    
    init(fromJson json: JSON!) {
        if json == JSON.null {
            return
        }
        
        id = json["id"].stringValue
        if let tempMode = ConferenceMode(rawValue: json["mode"].stringValue) {
            mode = tempMode
        } else {
            mode = ConferenceMode.unknown
        }
        
        version = json["version"].intValue
    }
}
