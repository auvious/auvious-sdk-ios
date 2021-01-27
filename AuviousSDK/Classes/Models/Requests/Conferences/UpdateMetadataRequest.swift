//
//  UpdateMetadataRequest.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 28/9/20.
//

import Foundation

public enum MetadataRequestOperation: String {
    case set = "SET"
    case remove = "REMOVE"
}

public enum MetadataRequestType: String {
    case audio, video
}

internal final class UpdateMetadataRequest {
    
    //The related conference
    var conferenceId: String!
    //The stream id we're updating metadata for
    var streamId: String!
    //The user's endpoint
    var userEndpointId: String!
    //The operation we're performing
    var operation: MetadataRequestOperation!
    //The type of stream we're modifying
    var type: MetadataRequestType!
    //Needed by the backend
    var value: String!
    
    init(conferenceId: String, streamId: String, userEndpointId: String, operation: MetadataRequestOperation, type: MetadataRequestType, value: String!) {
        self.conferenceId = conferenceId
        self.streamId = streamId
        self.userEndpointId = userEndpointId
        self.operation = operation
        self.type = type
        self.value = value
    }
    
    func toDictionary() -> [String: Any] {
        var dictionary = [String: Any]()
        
        if conferenceId != nil {
            dictionary["conferenceId"] = conferenceId
        }
        
        if userEndpointId != nil {
            dictionary["userEndpointId"] = userEndpointId
        }
        
        if operation != nil {
            dictionary["operation"] = operation.rawValue
        }

        dictionary["key"] = "TRACK_MUTED/" + type.rawValue + "/" + streamId

        if value != nil {
            dictionary["value"] = value
        }

        return dictionary
    }
}
