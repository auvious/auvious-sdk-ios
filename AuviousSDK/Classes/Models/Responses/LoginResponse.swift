//
//  LoginResponse.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 28/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

internal final class LoginResponse {
    
    var accessToken: String!
    var organization: String!
    var jti: String!
    var scope: String!
    var refreshToken: String!
    var expiresIn: Int!
    var userId: String!
    var deviceId: String!
    
    init(fromJson json: JSON!) {
        if json == JSON.null {
            return
        }
        
        accessToken = json["access_token"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        organization = json["organization"].stringValue
        jti = json["jti"].stringValue
        scope = json["scope"].stringValue
        refreshToken = json["refresh_token"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        expiresIn = json["expires_in"].intValue
        userId = json["userId"].stringValue
        deviceId = json["DEVICE_ID"].stringValue
        
        API.sharedInstance.authenticationToken = accessToken
        API.sharedInstance.refreshToken = refreshToken
        ServerConfiguration.mqttUser = accessToken
        
        print("mqtt user \(accessToken)")
    }
}
