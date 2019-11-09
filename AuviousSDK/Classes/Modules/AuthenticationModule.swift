//
//  AuthenticationModule.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 14/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation

internal class AuthenticationModule {
    
    /// Singleton instance
    internal static let sharedInstance = AuthenticationModule()
    
    /// The login response from the server
    internal var loginResponse: LoginResponse?
    
    /// Determines whether there's an active session
    internal var isLoggedIn: Bool = false
    
    /**
     Performs a login using the configuration settings provided and returns the endpoint
     */
    
    internal func login(oAuth:Bool = false, username: String, password: String, organization: String, onSuccess: @escaping (String?)->(), onFailure: @escaping (Error)->()) {
        
        if isLoggedIn && UserEndpointModule.sharedInstance.userEndpointId != nil {
            onSuccess(UserEndpointModule.sharedInstance.userEndpointId)
            return
        }
        
        let loginRequest = LoginRequest(clientId: ServerConfiguration.httpClientId, organization: organization, username: username, password: password, useOAuth: oAuth)
        
        API.sharedInstance.loginUser(loginRequest, onSuccess: {(json) in
            if let data = json {
                self.loginResponse = LoginResponse(fromJson: data)
                
                if let userId = self.loginResponse?.userId {
                    self.isLoggedIn = true
                    
                    print("Logged in as user id \(userId)")
                    
                    //Create an endpoint
                    UserEndpointModule.sharedInstance.createEndpoint(newEndpointId: UUID().uuidString, userId: userId, onSuccess: {(newEndpointId) in
                        
                        //Obtain RTC server configuration
                        API.sharedInstance.getIceServers(onSuccess: {json in
                            if let data = json {
                                ServerConfiguration.stunServer = data["stun"].stringValue
                                ServerConfiguration.turnServer = data["turn"].stringValue
                                ServerConfiguration.turnUsername = data["turnUsername"].stringValue
                                ServerConfiguration.turnPassword = data["turnPassword"].stringValue
                                
                                onSuccess(newEndpointId)
                            }
                        }, onFailure: {error in
                            print("error getting ice servers")
                            onFailure(error)
                        })
                    }, onFailure: {(error) in
                        print("CreateEndpoint failed: Error \(error)")
                        onFailure(error)
                    })
                }
            }
        }, onFailure: {(error) in
            onFailure(error)
        })
    }
}
