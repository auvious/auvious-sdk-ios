//
//  API2.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 7/3/25.
//

import Foundation
import SwiftyJSON
import os

/// Types adopting the `URLRequestConvertible` protocol can be used to construct URL requests.
public protocol URLRequestConvertible2 {
    /// Returns a URL request or throws if an `Error` was encountered.
    ///
    /// - throws: An `Error` if the underlying `URLRequest` is `nil`.
    ///
    /// - returns: A URL request.
    func asURLRequest() throws -> URLRequest
}

internal final class API2 {
    
    static let sharedInstance = API2()
    
    //URLSession
    var session: URLSession
    
    //Cached tasks
    var cachedTasks: [TransactionElementNew] = []
    
    //Auth tokens
    var tokenRefreshTimer: Timer!
    var authenticationToken = ""
    var refreshToken: String?
    
    //Token refresh related
    var isRefreshing = false
    var refreshTokenAttempts = 0
    
    typealias TransactionElementNew = (request: URLRequestConvertible2, onSuccess: (JSON?)->(), onFailure: (Error)->(), needsToken: Bool)
    
    init() {
        let cookies = HTTPCookieStorage.shared
        cookies.removeCookies(since: Date())
        
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = cookies
        cfg.httpMaximumConnectionsPerHost = 10
        cfg.timeoutIntervalForRequest = 24.0

        session = URLSession(configuration: cfg)
//        let apiRequestHandler = APIRequestHandler()
//        sessionManager.adapter = apiRequestHandler
//        sessionManager.retrier = apiRequestHandler
    }
    
    private func synced(_ lock: AnyObject, closure: () -> ()) {
        objc_sync_enter(lock)
        closure()
        objc_sync_exit(lock)
    }
    
    // MARK: Token Refresh
    
    //Refreshes the OAuth token and consumes pending transactions
    private func refreshToken(_ completion: ((Bool) -> Void)? = nil) {
//        guard let refreshToken = refreshToken else {
//            refreshTokenDidFail({ (_) in
//                completion?(false)
//            })
//            
//            return
//        }
//        
//        self.isRefreshing = true
//        self.refreshAuthToken(refreshToken, onSuccess: { (json) -> () in
//            self.isRefreshing = false
//            self.refreshTokenAttempts = 0
//            
//            //Keep a copy of the new tokens
//            if let data = json {
//                self.authenticationToken = data["access_token"].stringValue
//                self.refreshToken = data["refresh_token"].stringValue
//                self.authTokenExpiresIn = data["expires_in"].intValue
//                
//                //Trigger a reconnect by disconnecting
//                ServerConfiguration.mqttPass = self.authenticationToken
//                MQTTModule.sharedInstance.disconnect()
//                
//                self.consumePendingTransactions()
//                completion?(true)
//            }
//            
//            completion?(false)
//        }, onFailure: { (error)  -> () in
//            self.refreshTokenDidFail({ (_) in
//                completion?(false)
//            })
//        })
    }
    
    //Refresh token failure handler
    private func refreshTokenDidFail(_ completion: ((Bool) -> Void)? = nil) {
        self.isRefreshing = false
        self.cachedTasks.removeAll(keepingCapacity: false)
        completion?(false)
    }
    
    private func fireRequest(_ transaction: TransactionElementNew) {
        
        let cachedRequest = transaction
//        if self.isRefreshing && transaction.needsToken == true {
//            synced(self, closure: {
//                self.cachedTasks.append(cachedRequest)
//            })
//
//            return
//        }
        
        do {
            let request = try transaction.request.asURLRequest()
    
            let task = session.dataTask(with: request) { (data, response, error) in
                var responseCode = 0
                if let httpResponse = response as? HTTPURLResponse {
                    responseCode = httpResponse.statusCode
                }
                
                // Check for error
//                if let errorReply = APIErrorHelper.sharedInstance.checkForError(response: response) {
//                
//                    switch errorReply {
//                    case AuviousSDKError.unauthorizedRequest:
//                        // Session expired
//                        if transaction.needsToken == true {
//                            self.synced(self, closure: {
//                                self.cachedTasks.append(cachedRequest)
//                            })
//                            
//                            //Only attempt to refresh token if we've successfully logged in before
//                            if self.isRefreshing == false && self.refreshTokenAttempts < 3 && !self.authenticationToken.isEmpty {
//                                self.refreshTokenAttempts += 1
//                                
//                                self.refreshToken({ (success) in
//                                    guard !success else {
//                                        return
//                                    }
//                                    
//                                    transaction.onFailure(errorReply)
//                                })
//                                
//                                return
//                            }
//                        }
//                    default:
//                        transaction.onFailure(errorReply)
//                        return
//                    }
//                    
//                    transaction.onFailure(errorReply)
//                    return
//                }
                
//                if response.error != nil {
//                    os_log("response error: %@", log: Log.api, type: .error, String(describing: response.error))
//                }
                
                DispatchQueue.main.async {
                    if let responseData = data {
                        
                        do {
                            let jsonResponse = try JSON(data: responseData)
                            //Logger.log(level: .debug, message: "RESPONSE SUCCESS \(jsonResponse)")
                            //print("RESPONSE SUCCESS \(jsonResponse)")
                            
                            transaction.onSuccess(jsonResponse)
                            return
                        } catch {
                            //Handle empty responses, like KeepAlive
                            if responseCode == 200 || responseCode == 204 {
                                transaction.onSuccess(JSON())
                                return
                            }
                        }
                    }
                    
                    let error = AuviousSDKError.httpError(code: responseCode)
                    transaction.onFailure(error)
                }
            }
                
            // Start the request
            task.resume()
            
        } catch let error {
            print("API2 INVALID URLREQUEST")
        }
    }
    
    // MARK: API Implementation
    
    func loginUser(_ object: LoginRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.loginUserOAuth(object: object), onSuccess, onFailure, false)
        fireRequest(transaction)
    }
    
    func createEndpoint(_ object: CreateEndpointRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.createEndpoint(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
}
