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
    var authTokenExpiresIn: Int? {
        didSet {
            startTokenRefreshTimer()
        }
    }
    
    //Token refresh related
    var isRefreshing = false
    var refreshTokenAttempts = 0
    
    typealias TransactionElementNew = (request: URLRequestConvertible2, onSuccess: (JSON?)->(), onFailure: (Error)->(), needsToken: Bool)
    
    init() {
        let cookies = HTTPCookieStorage.shared
        cookies.removeCookies(since: Date())
        
        let userAgent = Utilities.generateCustomUserAgent()
        
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = cookies
        cfg.httpMaximumConnectionsPerHost = 10
        cfg.timeoutIntervalForRequest = 24.0
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent]

        session = URLSession(configuration: cfg)
    }
    
    private func synced(_ lock: AnyObject, closure: () -> ()) {
        objc_sync_enter(lock)
        closure()
        objc_sync_exit(lock)
    }
    
    // MARK: Token Refresh
    
    func startTokenRefreshTimer() {
        var executeIn: Int = 3
        if authTokenExpiresIn! - 40 > executeIn {
            executeIn = authTokenExpiresIn! - 40
        }
        
        tokenRefreshTimer = Timer.scheduledTimer(timeInterval: Double(executeIn), target: self, selector: #selector(self.handleTokenRefresh), userInfo: nil, repeats: false)
    }
    
    @objc func handleTokenRefresh() {
        self.refreshToken()
    }
    
    //Refreshes the OAuth token and consumes pending transactions
    private func refreshToken(_ completion: ((Bool) -> Void)? = nil) {
        guard let refreshToken = refreshToken else {
            refreshTokenDidFail({ (_) in
                completion?(false)
            })
            
            return
        }
        
        self.isRefreshing = true
        self.refreshAuthToken(refreshToken, onSuccess: { (json) -> () in
            print("REFRESHED TOKEN!")
            self.isRefreshing = false
            self.refreshTokenAttempts = 0
            
            //Keep a copy of the new tokens
            if let data = json {
                self.authenticationToken = data["access_token"].stringValue
                self.refreshToken = data["refresh_token"].stringValue
                self.authTokenExpiresIn = data["expires_in"].intValue
                
                //Trigger a reconnect by disconnecting
                ServerConfiguration.mqttPass = self.authenticationToken
                MQTTModule2.sharedInstance.disconnect()
                
                //self.consumePendingTransactions()
                completion?(true)
            }
            
            completion?(false)
        }, onFailure: { (error)  -> () in
            self.refreshTokenDidFail({ (_) in
                completion?(false)
            })
        })
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
            print("FIRING REQUEST \(request.debugDescription)")
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
                            print("RESPONSE SUCCESS \(jsonResponse)")
                            
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
    
    //Token refresh
    func refreshAuthToken(_ token: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.refreshToken(token: token), onSuccess, onFailure, false)
        fireRequest(transaction)
    }
    
    //IceSupport
    func getIceServers(onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getIceServers(()), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    //Calls
    func call(_ object: CallRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.call(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func answerCall(_ object: CallAnswerRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.answerCall(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func rejectCall(_ object: CallRejectRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.rejectCall(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func callRinging(_ object: CallRingingRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.callRinging(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func callHangup(_ object: CallHangupRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.callHangup(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func callCancel(_ object: CallCancelRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.callCancel(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func addCallIceCandidates(_ object: CallIceCandidatesRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.addCallIceCandidates(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    //Conferences
    func getConferences(onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getConferences(()), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func getConferenceDetails(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getConferenceDetails(id: id), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func getConferenceSimpleView(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getConferenceSimpleView(id: id), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func getConferenceSummary(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getConferenceSummary(id: id), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func addPublishStreamIceCandidates(_ object: PublishStreamIceCandidatesRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.addPublishStreamIceCandidates(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func addViewStreamIceCandidates(_ object: ViewStreamIceCandidatesRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.addViewStreamIceCandidates(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func createConference(_ object: CreateConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.createConference(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func endConference(_ object: EndConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.endConference(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func joinConference(_ object: JoinConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.joinConference(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func leaveConference(_ object: LeaveConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.leaveConference(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func publishStream(_ object: PublishStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.publishStream(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func stopViewStream(_ object: StopViewStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.stopViewStream(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func unpublishStream(_ object: UnpublishStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.unpublishStream(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func viewStream(_ object: ViewStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.viewStream(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func updateConferenceMetadata(_ object: UpdateMetadataRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.updateConferenceMetadata(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    //Endpoints
    func getEndpoints(onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getEndpoints(()), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func createEndpoint(_ object: CreateEndpointRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.createEndpoint(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func getEndpointDetails(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.getEndpointDetails(id:id), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func keepAlive(_ object: KeepAliveRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.keepAlive(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
    
    func unregisterEndpoint(_ object: UnregisterEndpointRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction: TransactionElementNew = (Router.unregisterEndpoint(object: object), onSuccess, onFailure, true)
        fireRequest(transaction)
    }
}
