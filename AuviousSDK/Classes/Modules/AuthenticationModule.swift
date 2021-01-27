//
//  AuthenticationModule.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 14/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON
import os

internal class AuthenticationModule {
    
    /// Singleton instance
    internal static let sharedInstance = AuthenticationModule()
    
    /// The login response from the server
    internal var loginResponse: LoginResponse?
    
    /// Determines whether there's an active session
    internal var isLoggedIn: Bool = false
    
    /**
     Performs a login using the configuration settings provided and returns the endpoint and conference id(optional)
     */
    
    internal func login(params: [String: String]?, username: String, password: String, onSuccess: @escaping (String?, String?)->(), onFailure: @escaping (Error)->()) {
        
        if isLoggedIn && UserEndpointModule.sharedInstance.userEndpointId != nil {
            onSuccess(UserEndpointModule.sharedInstance.userEndpointId, loginResponse?.conferenceId)
            return
        }
        
        let loginRequest = LoginRequest(clientId: ServerConfiguration.clientId, username: username, password: password, params: params)
        
        API.sharedInstance.loginUser(loginRequest, onSuccess: {(json) in
            if let data = json {
                self.loginResponse = LoginResponse(fromJson: data)
                
                if let userId = self.loginResponse?.userId {
                    self.isLoggedIn = true
                    
                    os_log("Logged in as user id %@", log: Log.auth, type: .debug, userId)
                    
                    //Create an endpoint
                    UserEndpointModule.sharedInstance.createEndpoint(newEndpointId: UUID().uuidString, userId: userId, onSuccess: {(newEndpointId) in
                        
                        //Obtain RTC server configuration
                        API.sharedInstance.getIceServers(onSuccess: {json in
                            for iceServer in json!["iceServers"].array! {
                                let urlStrings = iceServer["urls"].array?.map({ (url) -> String in
                                    url.stringValue
                                }) ?? []
                                let username = iceServer["username"].stringValue
                                let credential = iceServer["credential"].stringValue
                                ServerConfiguration.iceServers.append(
                                    RTCIceServer(urlStrings: urlStrings,
                                                 username: username,
                                                 credential: credential)
                                )
                            }
                            onSuccess(newEndpointId, self.loginResponse?.conferenceId)
                        }, onFailure: {error in
                            os_log("error getting ice servers %@", log: Log.auth, type: .error, error.localizedDescription)
                            onFailure(error)
                        })
                    }, onFailure: {(error) in
                        os_log("CreateEndpoint failed: Error %@", log: Log.auth, type: .error, error.localizedDescription)
                        onFailure(error)
                    })
                }
            }
        }, onFailure: {(error) in
            onFailure(error)
        })
    }
}
