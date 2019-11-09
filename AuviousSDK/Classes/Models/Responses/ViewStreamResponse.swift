//
//  ViewStreamResponse.swift
//  AuviousSDK_Foundation
//
//  Created by Macis on 03/01/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import UIKit
import SwiftyJSON

final class ViewStreamResponse: NSObject {
    
    var viewerId: String!
    var sdpAnswer: String!
    
    init(fromJson json: JSON!) {
        if json == JSON.null {
            return
        }
        
        viewerId = json["viewerId"].stringValue
        sdpAnswer = json["sdpAnswer"].stringValue
    }

}
