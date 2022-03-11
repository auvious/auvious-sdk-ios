//
//  API.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 27/11/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON
import os

/**
 This class is responsible for performing all HTTP requests.
 */
internal final class API {
    
    static let sharedInstance = API()
    
    typealias TransactionElement = (request: URLRequestConvertible, onSuccess: (JSON?)->(), onFailure: (Error)->(), needsToken: Bool)
    
    //Session manager
    var sessionManager: Alamofire.SessionManager
    
    //Auth tokens
    var tokenRefreshTimer: Timer!
    var authenticationToken = ""
    var refreshToken: String?
    var authTokenExpiresIn: Int? {
        didSet {
            startTokenRefreshTimer()
        }
    }
    
    //Cached tasks
    var cachedTasks: [TransactionElement] = []
    //Token refresh related
    var isRefreshing = false
    var refreshTokenAttempts = 0
    
    var oldRequest: Request!
    
    init() {
        let cookies = HTTPCookieStorage.shared
        cookies.removeCookies(since: Date())
        
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = cookies
        cfg.httpMaximumConnectionsPerHost = 10
        cfg.timeoutIntervalForRequest = 24.0

        sessionManager = Alamofire.SessionManager(configuration: cfg)
        let apiRequestHandler = APIRequestHandler()
        sessionManager.adapter = apiRequestHandler
        sessionManager.retrier = apiRequestHandler
    }
    
    func synced(_ lock: AnyObject, closure: () -> ()) {
        objc_sync_enter(lock)
        closure()
        objc_sync_exit(lock)
    }
    
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
    func refreshToken(_ completion: ((Bool) -> Void)? = nil) {
        guard let refreshToken = refreshToken else {
            refreshTokenDidFail({ (_) in
                completion?(false)
            })
            
            return
        }
        
        self.isRefreshing = true
        self.refreshAuthToken(refreshToken, onSuccess: { (json) -> () in
            self.isRefreshing = false
            self.refreshTokenAttempts = 0
            
            //Keep a copy of the new tokens
            if let data = json {
                self.authenticationToken = data["access_token"].stringValue
                self.refreshToken = data["refresh_token"].stringValue
                self.authTokenExpiresIn = data["expires_in"].intValue
                
                //Trigger a reconnect by disconnecting
                ServerConfiguration.mqttPass = self.authenticationToken
                MQTTModule.sharedInstance.disconnect()
                
                self.consumePendingTransactions()
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
    func refreshTokenDidFail(_ completion: ((Bool) -> Void)? = nil) {
        self.isRefreshing = false
        self.cachedTasks.removeAll(keepingCapacity: false)
        completion?(false)
    }
    
    func consumePendingTransactions() {
        let localCachedTasks = self.cachedTasks
        self.cachedTasks.removeAll(keepingCapacity: false)
        
        for i in 0..<localCachedTasks.count {
            startRequest(localCachedTasks[i])
        }
    }
    
    func purgeRunningTransactions(_ dataTasks: [URLSessionTask], uploadTasks: [URLSessionTask], downloadTasks: [URLSessionTask]) {
        
        // Cancel ALL running data tasks
        for task in dataTasks.filter({ (t) -> Bool in
            t.state == .running
        }) {
            task.cancel()
        }
        
        // Cancel ALL running upload tasks
        for task in uploadTasks.filter({ (t) -> Bool in
            t.state == .running
        }) {
            task.cancel()
        }
        
        // Cancel ALL running download tasks
        for task in downloadTasks.filter({ (t) -> Bool in
            t.state == .running
        }) {
            task.cancel()
        }
    }
    
    func cancelRequest(_ theRequest: Request){
        theRequest.cancel()
    }
    
    func startRequest(_ transaction: TransactionElement) {
        
        let cachedRequest = transaction
        if self.isRefreshing && transaction.needsToken == true {
            synced(self, closure: {
                self.cachedTasks.append(cachedRequest)
            })

            return
        }

        oldRequest = API.sharedInstance.sessionManager.request(transaction.request).response { response in
            
            // Check for error
            if let errorReply = APIErrorHelper.sharedInstance.checkForError(response: response) {
            
                switch errorReply {
                case AuviousSDKError.unauthorizedRequest:
                    // Session expired
                    if transaction.needsToken == true {
                        self.synced(self, closure: {
                            self.cachedTasks.append(cachedRequest)
                        })
                        
                        //Only attempt to refresh token if we've successfully logged in before
                        if self.isRefreshing == false && self.refreshTokenAttempts < 3 && !self.authenticationToken.isEmpty {
                            self.refreshTokenAttempts += 1
                            
                            self.refreshToken({ (success) in
                                guard !success else {
                                    return
                                }
                                
                                transaction.onFailure(errorReply)
                            })
                            
                            return
                        }
                    }
                default:
                    transaction.onFailure(errorReply)
                    return
                }
                
                transaction.onFailure(errorReply)
                return
            }
            
            if response.error != nil {
                os_log("response error: %@", log: Log.api, type: .error, String(describing: response.error))
            }
            
            if let responseData = response.data {
                
                do {
                    let jsonResponse = try JSON(data: responseData)
                    //Logger.log(level: .debug, message: "RESPONSE SUCCESS \(jsonResponse)")
                    //print("RESPONSE SUCCESS \(jsonResponse)")
                    
                    transaction.onSuccess(jsonResponse)
                    return
                } catch {
                    //Handle empty responses, like KeepAlive
                    if let code = response.response?.statusCode {
                        if code == 200 || code == 204 {
                            transaction.onSuccess(JSON())
                            return
                        }
                    }
                }
            }

            let error = AuviousSDKError.httpError(code: response.response?.statusCode ?? 0)
            transaction.onFailure(error)
        }
    }
    
    // MARK: API Implementation
    
    // Authentication
    func loginUser(_ object: LoginRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction = (APIRequest.Router.loginUserOAuth(object: object), onSuccess, onFailure, false)
        startRequest(transaction)
    }
    
    //Token refresh
    func refreshAuthToken(_ token: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.refreshToken(token: token), onSuccess, onFailure, false)
        startRequest(transaction)
    }
    
    //IceSupport
    func getIceServers(onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.getIceServers(()), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    //Calls
    func call(_ object: CallRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.call(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func answerCall(_ object: CallAnswerRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.answerCall(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func rejectCall(_ object: CallRejectRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.rejectCall(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func callRinging(_ object: CallRingingRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.callRinging(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func callHangup(_ object: CallHangupRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.callHangup(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func callCancel(_ object: CallCancelRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.callCancel(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func addCallIceCandidates(_ object: CallIceCandidatesRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.addCallIceCandidates(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    //Conferences
    func getConferences(onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.getConferences(()), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func getConferenceDetails(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.getConferenceDetails(id: id), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func getConferenceSimpleView(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.getConferenceSimpleView(id: id), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func getConferenceSummary(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.getConferenceSummary(id: id), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func addPublishStreamIceCandidates(_ object: PublishStreamIceCandidatesRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.addPublishStreamIceCandidates(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func addViewStreamIceCandidates(_ object: ViewStreamIceCandidatesRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.addViewStreamIceCandidates(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func createConference(_ object: CreateConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.createConference(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func endConference(_ object: EndConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.endConference(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func joinConference(_ object: JoinConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.joinConference(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func leaveConference(_ object: LeaveConferenceRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.leaveConference(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func publishStream(_ object: PublishStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.publishStream(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func stopViewStream(_ object: StopViewStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.stopViewStream(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func unpublishStream(_ object: UnpublishStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.unpublishStream(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func viewStream(_ object: ViewStreamRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.viewStream(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func updateConferenceMetadata(_ object: UpdateMetadataRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.updateConferenceMetadata(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    //Endpoints
    func getEndpoints(onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.getEndpoints(()), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func createEndpoint(_ object: CreateEndpointRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.createEndpoint(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func getEndpointDetails(_ id: String, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.getEndpointDetails(id:id), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func keepAlive(_ object: KeepAliveRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.keepAlive(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func unregisterEndpoint(_ object: UnregisterEndpointRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.unregisterEndpoint(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    //Snapshots
    func cameraRequestRespond(_ object: SnapshotCameraRQRPRequest, onSuccess: @escaping (JSON?)->(), onFailure: @escaping (Error)->()) {
        let transaction:TransactionElement = (APIRequest.Router.cameraRequestRespond(object: object), onSuccess, onFailure, true)
        startRequest(transaction)
    }
    
    func uploadSnapshot(_ object: SnapshotUploadRequest, onSuccess: @escaping ()->(), onFailure: @escaping (Error)->()) {
        let url = ServerConfiguration.baseRTC + "/rtc-api/snapshots/snapshotAcquire"
        
        os_log("Uploading snapshot to %@", log: Log.api, type: .debug, url)
        
        let headers: HTTPHeaders = [
            "Content-Type": "application/form-data",
            "Authorization" : "Bearer " + API.sharedInstance.authenticationToken
        ]
        
        Alamofire.upload(multipartFormData: { (multipartFormData) in
            
            multipartFormData.append(object.snapshotId.data(using: String.Encoding.utf8)!, withName: "snapshotId" as String)
            multipartFormData.append(object.snapshotSuffix.data(using: String.Encoding.utf8)!, withName: "snapshotSuffix" as String)
            multipartFormData.append(object.snapshotType.data(using: String.Encoding.utf8)!, withName: "snapshotType" as String)
            multipartFormData.append(object.userEndpointId.data(using: String.Encoding.utf8)!, withName: "userEndpointId" as String)
            multipartFormData.append(object.userId.data(using: String.Encoding.utf8)!, withName: "userId" as String)
            
            if let data = object.snapshot.jpegData(compressionQuality: 0.7) {
                multipartFormData.append(data, withName: "image", fileName: "jpeg", mimeType: "image/jpeg")
            }
            
        }, usingThreshold: UInt64.init(), to: url, method: .post, headers: headers) { (result) in
            switch result {
            case .success(let upload, _, _):
                upload.response { response in
                    
                    if let err = response.error {
                        os_log("Upload error is %@", log: Log.api, type: .error, err.localizedDescription)
                        onFailure(err)
                        return
                    }
                    
                    os_log("Succesfully uploaded", log: Log.api, type: .debug)
                    onSuccess()
                }
            case .failure(let error):
                os_log("Error in upload: %@", log: Log.api, type: .error, error.localizedDescription)
                onFailure(error)
            }
        }
    }
}
