//
//  RTCPeerConnectionContainer.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 16/01/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

internal final class RTCPeerConnectionContainer: CustomStringConvertible {
    
    var connection: RTCPeerConnection!
    var streamId: String!
    var endpointId: String!
    var userId: String!
    var iceCandidates: [RTCIceCandidate] = [RTCIceCandidate]()
    var streamType: StreamType!
    var isLocal: Bool = false
    var callId: String?
    
    var description: String {
        return "Stream id \(String(describing: streamId)) - Call id \(String(describing: callId)) - isLocal \(isLocal)"
    }
    
    init(conn: RTCPeerConnection, streamId: String, endpointId: String, userId: String, type: StreamType, isLocal: Bool) {
        self.connection = conn
        self.streamId = streamId
        self.endpointId = endpointId
        self.userId = userId
        self.streamType = type
        self.isLocal = isLocal
    }
    
}
