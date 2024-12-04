//
//  ParticipantEndpointStream.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public final class ParticipantEndpointStream {
    
    public var id: String!
    public var type: StreamType!
    public var portraitMode: Bool = false
    
    public init(id: String, type: StreamType) {
        self.id = id
        self.type = type
    }

    init(fromJson json: JSON!) {
        if json == JSON.null {
            return
        }
        
        id = json["id"].stringValue
        type = StreamType(rawValue: json["type"].stringValue.uppercased())
        portraitMode = json["metadata"]["portraitMode"].boolValue
    }
}
