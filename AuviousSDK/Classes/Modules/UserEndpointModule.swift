//
//  UserEndpointModule.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 14/05/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import os

internal protocol UserEndpointDelegate {
    
    /**
     Called when an error is received.
     
     - Parameter error: The error object
     */
    func userEndpoint(onError error: AuviousSDKError)
}

internal class UserEndpointModule {
    
    /// Singleton instance
    internal static let sharedInstance = UserEndpointModule()
    
    /// Configuration setting for the keep alive timer
    private let keepAliveSeconds: Double = 15
    
    /// Endpoint keep alive timer
    internal var keepAliveTimer: Timer?
    
    /// Endpoint HTTP request, to be used by the timer
    internal var keepAliveRequest: KeepAliveRequest?
    
    /// The user endpoint Id, as created by the server
    internal var userEndpointId: String?
    
    internal var callDelegate: UserEndpointDelegate?
    internal var conferenceDelegate: UserEndpointDelegate?
    
    /**
     Creates the specified endpoint for the given userId.
     */
    internal func createEndpoint(newEndpointId: String, userId: String, onSuccess: @escaping (String)->(), onFailure: @escaping (Error)->()){
        let ceRequest = CreateEndpointRequest(keepAliveSeconds: Int(self.keepAliveSeconds), userEndpointId: newEndpointId, userId: userId)
        
        API.sharedInstance.createEndpoint(ceRequest, onSuccess: {(json) in
            
            if let data = json {
                self.userEndpointId = data["id"].stringValue
                
                //Reset the keep alive request, as we might be coming back from an application resume and need to create a new request, for the new endpoint
                self.keepAliveRequest = nil
                self.startKeepAliveTimer()
                
                onSuccess(self.userEndpointId!)
            }
            
        }, onFailure: {(error) in
            os_log("CreateEndpoint failed: Error %@", log: Log.auth, type: .error, error.localizedDescription)
            onFailure(error)
        })
    }
    
    internal func destroyEndpoint(endpointId: String, userId: String, onSuccess: @escaping ()->(), onFailure: @escaping (Error)->()) {
        let uRequest = UnregisterEndpointRequest(reason: "User logout", userEndpointId: endpointId, userId: userId)
        API.sharedInstance.unregisterEndpoint(uRequest, onSuccess: {(json) in
            
            self.stopKeepAliveTimer()
            onSuccess()
            
        }, onFailure: {(error) in
            
            //We still stop the timer and disconnect from mqtt, regardless of the http failure
            self.stopKeepAliveTimer()
            onFailure(error)
        })
    }
    
    //Schedules the keep alive timer
    internal func startKeepAliveTimer() {
        let interval = keepAliveSeconds - 5
        keepAliveTimer = Timer(timeInterval: interval, target: self, selector: #selector(onKeepAliveTick), userInfo: nil, repeats: true)
        RunLoop.current.add(keepAliveTimer!, forMode: .common)
    }
    
    //Stops the keep alive timer
    internal func stopKeepAliveTimer() {
        os_log("Stopped keep alive timer", log: Log.auth, type: .debug)
        keepAliveTimer?.invalidate()
    }
    
    //Keep alive timer tick
    @objc private func onKeepAliveTick(timer: Timer) {
        guard let userEndpointId = userEndpointId, let loginResponse = AuthenticationModule.sharedInstance.loginResponse else {
            return
        }
        
        if let request = keepAliveRequest {
            fireKeepAliveRequest(request)
        } else {
            self.keepAliveRequest = KeepAliveRequest(userEndpointId: userEndpointId, userId: loginResponse.userId)
            fireKeepAliveRequest(self.keepAliveRequest!)
        }
    }
    
    //Fires the keep alive rest call
    private func fireKeepAliveRequest(_ request: KeepAliveRequest) {
        API.sharedInstance.keepAlive(request, onSuccess: {(json) in
            if let _ = json {
                //os_log("Keep Alive Success", log: Log.auth, type: .debug)
            }
        }, onFailure: {(error) in
            os_log("Keep Alive failed: Error %@", log: Log.auth, type: .error, error.localizedDescription)
            self.callDelegate?.userEndpoint(onError: AuviousSDKError.connectionError)
            self.conferenceDelegate?.userEndpoint(onError: AuviousSDKError.connectionError)
        })
    }
}
