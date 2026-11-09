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
    
    /// The roles of the endpoint's user (e.g. AGENT, CUSTOMER)
    public var roles: [String] = []
    
    /// The endpoint's display name, if any
    public var name: String?
    
    /// The endpoint type (e.g. participant, stream, displayCapture)
    public var endpointType: String?
    
    public init(endpointId: String){
        self.id = endpointId
        streams = [ParticipantEndpointStream]()
    }
    
    init(fromJson json: JSON!) {
        if json == JSON.null {
            return
        }
        
        id = json["id"].stringValue
        roles = json["metadata"]["roles"].arrayValue.map { $0.stringValue }
        name = json["metadata"]["name"].string
        endpointType = json["metadata"]["type"].string
        let tmpStreams = json["streams"].arrayValue
        streams = [ParticipantEndpointStream]()
        for item in tmpStreams {
            streams.append(ParticipantEndpointStream(fromJson: item))
        }
    }
}
