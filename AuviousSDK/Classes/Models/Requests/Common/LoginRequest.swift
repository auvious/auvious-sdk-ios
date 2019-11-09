//
//  LoginRequest.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 27/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation

internal final class LoginRequest {
    
    var clientId: String!
    var organization: String!
    var password: String!
    var username: String!
    var useOAuth: Bool = false
    
    init(clientId: String, organization: String, username: String, password: String, useOAuth: Bool = false) {
        self.clientId = clientId
        self.organization = organization
        self.username = username
        self.password = password
        self.useOAuth = useOAuth
    }
    
}
