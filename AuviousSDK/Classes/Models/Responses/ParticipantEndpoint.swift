//
//  ParticipantEndpoint.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 07/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

public final class ParticipantEndpoint {

    public var id: String!
    public var streams: [ParticipantEndpointStream]!
    
    public init(endpointId: String){
        self.id = endpointId
        streams = [ParticipantEndpointStream]()
    }
    
    init(fromJson json: JSON!) {
        if json == JSON.null {
            return
        }
        
        id = json["id"].stringValue
        let tmpStreams = json["streams"].arrayValue
        streams = [ParticipantEndpointStream]()
        for item in tmpStreams {
            streams.append(ParticipantEndpointStream(fromJson: item))
        }
    }
}
