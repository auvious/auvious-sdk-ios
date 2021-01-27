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
    var password: String!
    var username: String!
    var params: [String: String]?
    
    init(clientId: String, username: String, password: String, params: [String: String]?) {
        self.clientId = clientId
        self.username = username
        self.password = password
        self.params = params
    }
}
