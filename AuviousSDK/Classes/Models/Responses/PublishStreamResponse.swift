//
//  PublishStreamResponse.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 13/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

final class PublishStreamResponse {
    
    var streamId: String!
    var sdpAnswer: String!
    
    init(fromJson json: JSON!) {
        if json == JSON.null {
            return
        }
        
        streamId = json["streamId"].stringValue
        sdpAnswer = json["sdpAnswer"].stringValue
    }
    
}
