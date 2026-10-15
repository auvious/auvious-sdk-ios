//
//  CobrowseSessionController.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit
import SwiftyJSON
import os

/// Events exchanged with the agent's co-browse page (same names as the web widget)
private enum CobrowseEventName {
    static let displayCaptureAccept = "CobrowseDisplayCaptureAcceptEvent"
    static let displayCaptureDeny = "CobrowseDisplayCaptureDenyEvent"
}

/// Leave reason the agent maps to "the customer terminated the session"
private let customerTerminatedReason = "widgetScreenShareTerminated"

/**
 Runs one co-browse session:
 ticket → login → join as a display-capture participant → consent → ReplayKit screen share,
 plus the agent's requests, sketch annotations, masking and the app lifecycle.
 */
internal final class CobrowseSessionController: NSObject {

    var onStateChange: ((AuviousCobrowseState) -> Void)?
    var onFailure: ((AuviousSDKGenericError) -> Void)?
    var onEnd: ((AuviousCobrowseEndReason) -> Void)?

    private struct Agent {
        let userId: String
        let endpointId: String
        let name: String?
    }

    private let configuration: AuviousCobrowseConfiguration
    private let sdk = AuviousConferenceSDK.sharedInstance
    private let overlay = CobrowseOverlayViewController()
    private var window: CobrowseOverlayWindow?
    private var sketch: SketchSession?

    private var agent: Agent?
    /// Events to send once we know who the agent is
    private var pendingAgentEvent: String?

    private var state: AuviousCobrowseState = .idle {
        didSet {
            if oldValue != state {
                onStateChange?(state)
            }
        }
    }
    private var sharingSince: Date?
    private var isDrawing = false
    private var isEnding = false
    private var hasJoined = false
    /// Set while we stop the capture ourselves, so the resulting "stopped" callback is not treated as a failure
    private var isStoppingShare = false
    private var isInBackground = false
    private var resumeSharingOnForeground = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lifecycleObservers: [NSObjectProtocol] = []

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(configuration: AuviousCobrowseConfiguration) {
        self.configuration = configuration
        super.init()
    }

    //MARK: Start

    func start() {
        installOverlay()
        state = .connecting
        overlay.setPhase(.connecting)

        //SDK in co-browse mode
        sdk.isCobrowseActive = true
        sdk.joinProfile = .displayCapture(originUrl: "ios-app://" + (Bundle.main.bundleIdentifier ?? "unknown"),
                                          customerMetadata: configuration.customerMetadata)
        sdk.delegate = self
        sdk.cobrowseDelegate = self
        sdk.screenFrameProcessor = { sampleBuffer, pixelBuffer in
            return PixelBufferMasker.maskedFrame(sampleBuffer: sampleBuffer, pixelBuffer: pixelBuffer, registry: MaskRegistry.shared)
        }

        var uiConfiguration = AuviousConferenceConfiguration()
        uiConfiguration.cameraAvailable = false
        uiConfiguration.microphoneAvailable = false
        uiConfiguration.pipAvailable = false
        uiConfiguration.screenSharingAvailable = true
        sdk.setUIConfiguration(config: uiConfiguration)

        let ticket = configuration.ticket.trimmingCharacters(in: .whitespacesAndNewlines)
        sdk.configure(params: ["username": ticket, "password": "", "grant_type": "password"],
                      username: ticket,
                      password: "",
                      name: configuration.participantName,
                      clientId: configuration.clientId,
                      baseEndpoint: configuration.baseEndpoint,
                      mqttEndpoint: configuration.mqttEndpoint)

        observeLifecycle()

        sdk.login(onLoginSuccess: { [weak self] _, conferenceId in
            self?.resolveConference(conferenceId)
        }, onLoginFailure: { [weak self] error in
            self?.fail(with: error)
        })
    }

    private func installOverlay() {
        overlay.accentColor = configuration.accentColor
        overlay.annotationsEnabled = configuration.annotationsEnabled
        overlay.hints.showsHints = configuration.showsMaskHints
        overlay.loadViewIfNeeded()

        overlay.dock.onCancel = { [weak self] in
            self?.end(reason: .customerEnded)
        }
        overlay.dock.onDraw = { [weak self] in
            self?.setDrawing(true)
        }
        overlay.dock.onDone = { [weak self] in
            self?.setDrawing(false)
        }
        overlay.dock.onShare = { [weak self] in
            self?.requestShare()
        }
        overlay.pill.onShare = { [weak self] in
            self?.requestShare()
        }
        overlay.dock.onEnd = { [weak self] in
            self?.confirmEnd()
        }
        overlay.dock.onToolSelected = { [weak self] tool in
            self?.overlay.tool = tool
        }
        overlay.dock.onUndo = { [weak self] in
            self?.sketch?.undo()
        }
        overlay.dock.onClear = { [weak self] in
            self?.sketch?.clear()
        }

        if configuration.annotationsEnabled {
            let session = SketchSession(canvas: overlay.canvas, laser: overlay.laser)
            session.onInkColorChanged = { [weak self] _ in
                self?.overlay.inkColorChanged()
            }
            sketch = session
        }

        let window = CobrowseOverlayWindow.make(rootViewController: overlay)
        window.isHidden = false
        self.window = window

        MaskRegistry.shared.excludedWindow = window
        MaskRegistry.shared.onRegionsChanged = { [weak self] regions in
            self?.overlay.hints.update(regions: regions, debug: MaskRegistry.shared.debugHighlight)
        }
    }

    //MARK: Connecting

    /// The conference comes with the token (conference_id); fall back to the ticket's properties
    private func resolveConference(_ conferenceId: String?) {
        guard !isEnding else { return }

        if let id = conferenceId, !id.isEmpty {
            join(id)
            return
        }

        API2.sharedInstance.getTicket(configuration.ticket, onSuccess: { [weak self] json in
            guard let self = self else { return }
            if let id = json?["properties"]["conference_id"].string, !id.isEmpty {
                self.join(id)
            } else {
                self.fail(with: AuviousSDKError.notInConference)
            }
        }, onFailure: { [weak self] error in
            self?.fail(with: error)
        })
    }

    private func join(_ conferenceId: String) {
        sdk.joinConference(conferenceId: conferenceId, onSuccess: { [weak self] conference in
            guard let self = self, !self.isEnding else { return }
            guard let conference = conference else {
                self.fail(with: AuviousSDKError.notInConference)
                return
            }
            self.didJoin(conference)
        }, onFailure: { [weak self] error in
            self?.fail(with: error)
        })
    }

    private func didJoin(_ conference: ConferenceSimpleView) {
        hasJoined = true

        for participant in conference.participants ?? [] {
            for endpoint in participant.endpoints ?? [] where isAgent(endpoint.roles) {
                agentFound(userId: participant.id, endpointId: endpoint.id, name: endpoint.name)
            }
        }

        sketch?.applyJoinMetadata(sdk.joinedConferenceMetadata)
        askToShare()
    }

    private func isAgent(_ roles: [String]) -> Bool {
        return roles.contains("AGENT") && !roles.contains("GUEST_AGENT")
    }

    private func agentFound(userId: String?, endpointId: String?, name: String?) {
        guard let userId = userId, let endpointId = endpointId, !userId.isEmpty, !endpointId.isEmpty else { return }

        agent = Agent(userId: userId, endpointId: endpointId, name: name ?? agent?.name)
        overlay.pill.agentName = agent?.name

        if let pending = pendingAgentEvent {
            pendingAgentEvent = nil
            sendToAgent(pending)
        }
    }

    //MARK: Consent and sharing

    /// Explains what is shared, then asks iOS for permission
    private func askToShare() {
        guard !isEnding else { return }

        guard configuration.showsShareExplainer else {
            requestShare()
            return
        }

        state = .awaitingConsent
        overlay.setPhase(.awaitingConsent)

        let name = agent?.name
        var bullets = [CobrowseStrings.explainerAppOnly(name), CobrowseStrings.explainerPrivate]
        if configuration.annotationsEnabled {
            bullets.append(CobrowseStrings.explainerDraw)
        }
        let content = CobrowseSheetView.Content(iconSymbol: "iphone",
                                                title: CobrowseStrings.explainerTitle(name),
                                                body: nil,
                                                bullets: bullets,
                                                primaryTitle: CobrowseStrings.startSharing,
                                                secondaryTitle: CobrowseStrings.notNow,
                                                footnote: CobrowseStrings.explainerFootnote)
        overlay.showSheet(content, onPrimary: { [weak self] in
            self?.requestShare()
        }, onSecondary: { [weak self] in
            self?.shareDeclined()
        })
    }

    /// Shows the iOS screen recording prompt and publishes the screen once allowed
    private func requestShare() {
        guard !isEnding, hasJoined, state != .sharing else { return }

        state = .awaitingConsent
        overlay.setPhase(.awaitingConsent)

        //Masks must be in place before the first frame is captured
        MaskRegistry.shared.start()

        sdk.requestScreenSharePermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self, !self.isEnding else { return }
                if granted {
                    self.publishScreen()
                } else {
                    self.shareDeclined()
                }
            }
        }
    }

    private func publishScreen() {
        do {
            _ = try sdk.startPublishLocalStreamFlow(type: .screen)
        } catch {
            os_log("Co-browse publish failed %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
            shareFailed()
            return
        }

        let since = Date()
        sharingSince = since
        state = .sharing
        overlay.setPhase(.sharing(since: since))
        sendToAgent(CobrowseEventName.displayCaptureAccept)
    }

    private func shareDeclined() {
        stopCapture()
        sendToAgent(CobrowseEventName.displayCaptureDeny)
        state = .notSharing
        overlay.setPhase(.notSharing)
    }

    private func shareFailed() {
        stopSharing()
        overlay.showToast(style: .warning, title: nil, message: CobrowseStrings.shareFailed)
    }

    /// Stops the screen share, the session stays connected
    private func stopSharing() {
        isDrawing = false
        //Drawings belong to the shared screen; they go when it stops being shared
        sketch?.reset()
        overlay.canvas.removeAll()
        overlay.laser.clear()
        stopCapture()
        sharingSince = nil
        state = .notSharing
        overlay.setPhase(.notSharing)
    }

    private func stopCapture(completion: (() -> Void)? = nil) {
        MaskRegistry.shared.stop()
        isStoppingShare = true
        sdk.stopLocalScreenShare(completion: completion)
        isStoppingShare = false
    }

    private func setDrawing(_ drawing: Bool) {
        guard state == .sharing, let since = sharingSince else { return }
        isDrawing = drawing
        overlay.setPhase(drawing ? .drawing(since: since) : .sharing(since: since))
    }

    //MARK: Agent

    private func sendToAgent(_ eventType: String) {
        guard let agent = agent else {
            pendingAgentEvent = eventType
            return
        }

        let event: [String: Any] = ["type": eventType, "timestamp": CobrowseSessionController.timestampFormatter.string(from: Date())]
        API2.sharedInstance.sendEvent(SendEventRequest(userId: agent.userId, userEndpointId: agent.endpointId, event: event), onSuccess: { _ in
        }, onFailure: { error in
            os_log("Co-browse event %@ failed %@", log: Log.conferenceSDK, type: .error, eventType, error.localizedDescription)
        })
    }

    private func agentRequestedShare() {
        switch state {
        case .sharing:
            //Already sharing (we started on our own), just confirm
            sendToAgent(CobrowseEventName.displayCaptureAccept)
        case .notSharing:
            askToShare()
        default:
            break
        }
    }

    //MARK: Ending

    private func confirmEnd() {
        let content = CobrowseSheetView.Content(iconSymbol: nil,
                                                title: CobrowseStrings.endTitle,
                                                body: CobrowseStrings.endBody(agent?.name),
                                                bullets: [],
                                                primaryTitle: CobrowseStrings.endSession,
                                                secondaryTitle: CobrowseStrings.keepSharing,
                                                footnote: nil)
        overlay.showSheet(content, onPrimary: { [weak self] in
            self?.end(reason: .customerEnded)
        }, onSecondary: {})
    }

    private func fail(with error: Error) {
        guard !isEnding else { return }
        os_log("Co-browse failed %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
        onFailure?(genericError(for: error))
        end(reason: .failed)
    }

    func end(reason: AuviousCobrowseEndReason) {
        guard !isEnding else { return }
        isEnding = true

        overlay.dismissSheet()
        //Nothing is shared anymore, so no drawings either
        sketch?.reset()
        overlay.canvas.removeAll()
        overlay.laser.clear()

        let leaveReason = reason == .customerEnded ? customerTerminatedReason : ""
        stopCapture { [weak self] in
            guard let self = self else { return }
            if reason != .agentEnded, let conferenceId = self.sdk.currentConferenceId {
                self.sdk.leaveConference(conferenceId: conferenceId, reason: leaveReason, onSuccess: {
                    self.logout()
                }, onFailure: { _ in
                    self.logout()
                })
            } else {
                self.logout()
            }
        }

        resetSDK()
        stopObservingLifecycle()
        state = .ended

        //Let the customer know the screen is no longer shared before the overlay goes away
        if hasJoined && reason != .failed {
            overlay.setPhase(.notSharing)
            overlay.pill.isHidden = true
            overlay.dock.isHidden = true
            overlay.showToast(style: .ended, title: CobrowseStrings.sessionEnded, message: CobrowseStrings.sessionEndedBody(agent?.name), duration: 2.5) { [weak self] in
                self?.finish(reason: reason)
            }
        } else {
            finish(reason: reason)
        }
    }

    private func logout() {
        sdk.logout(onSuccess: {}, onFailure: { error in
            os_log("Co-browse logout failed %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
        })
    }

    private func resetSDK() {
        sdk.delegate = nil
        sdk.cobrowseDelegate = nil
        sdk.screenFrameProcessor = nil
        sdk.joinProfile = .stream
        sdk.isCobrowseActive = false

        MaskRegistry.shared.stop()
        MaskRegistry.shared.onRegionsChanged = nil
        MaskRegistry.shared.excludedWindow = nil
    }

    private func finish(reason: AuviousCobrowseEndReason) {
        window?.isHidden = true
        window = nil
        onEnd?(reason)
    }

    private func genericError(for error: Error) -> AuviousSDKGenericError {
        if let sdkError = error as? AuviousSDKError {
            switch sdkError {
            case .INVALID_TICKET(let ticketId):
                return .INVALID_TICKET(ticketId: ticketId)
            case .httpError(let code) where code == 401 || code == 404:
                return .INVALID_TICKET(ticketId: configuration.ticket)
            case .unauthorizedRequest:
                return .AUTHENTICATION_FAILURE
            case .noInternetConnection, .connectionError:
                return .NETWORK_ERROR
            case .notInConference:
                return .CONFERENCE_MISSING
            default:
                return .UNKNOWN_FAILURE
            }
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return .NETWORK_ERROR
        }
        return .UNKNOWN_FAILURE
    }

    //MARK: App lifecycle

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.didEnterBackground()
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.willEnterForeground()
            }
        ]
    }

    private func stopObservingLifecycle() {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers = []
    }

    /// ReplayKit in-app capture can't run in the background: stop sharing and pick up again on return
    private func didEnterBackground() {
        guard hasJoined, !isEnding else { return }

        isInBackground = true
        resumeSharingOnForeground = state == .sharing
        guard resumeSharingOnForeground else { return }

        isDrawing = false
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        stopCapture { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func willEnterForeground() {
        guard isInBackground, !isEnding else { return }
        isInBackground = false

        sdk.restoreCobrowseConnection(onSuccess: { [weak self] in
            guard let self = self, !self.isEnding else { return }
            if self.resumeSharingOnForeground {
                self.resumeSharingOnForeground = false
                self.requestShare()
            }
        }, onFailure: { [weak self] error in
            self?.fail(with: error)
        })
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

//MARK: - Conference SDK delegate

extension CobrowseSessionController: AuviousSDKConferenceDelegate {

    func auviousSDK(didReceiveConferenceEvent event: ConferenceEvent) {
        switch event.type {
        case .conferenceEnded?:
            end(reason: .agentEnded)

        case .conferenceJoined?:
            if let joined = event as? ConferenceJoinedEvent, isAgent(joined.roles) {
                agentFound(userId: joined.userId, endpointId: joined.userEndpointId, name: joined.name)
            }

        case .conferenceLeft?:
            if event.userEndpointId == agent?.endpointId {
                os_log("Co-browse agent endpoint left", log: Log.conferenceSDK, type: .debug)
            }

        default:
            break
        }
    }

    func auviousSDK(screenSharingStopped: Bool) {
        //The capture stopped without us asking (ICE failure, ReplayKit interruption)
        guard !isStoppingShare, !isEnding, !isInBackground, state == .sharing else { return }
        shareFailed()
    }

    func auviousSDK(onError error: AuviousSDKError) {
        os_log("Co-browse SDK error %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)

        if case .publishStreamFailure = error, state == .sharing {
            shareFailed()
        }
    }

    func auviousSDK(screenSharingStarted: Bool) {}
    func auviousSDK(trackUnmuted type: StreamType, endpointId: String) {}
    func auviousSDK(trackMuted type: StreamType, endpointId: String) {}
    func auviousSDK(conferenceOnHold flag: Bool) {}
    func auviousSDK(didRejoinConference conference: ConferenceSimpleView) {}
    func auviousSDK(recorderStateChanged toActive: Bool) {}
    func auviousSDK(didChangeState newState: StreamEventState, streamId: String, streamType: StreamType, endpointId: String) {}
    func auviousSDK(agentPortraitMode flag: Bool, endpointId: String) {}
    func auviousSDK(didReceiveRemoteStream stream: RTCMediaStream, streamId: String, endpointId: String, type: StreamType) {}
    func auviousSDK(didReceiveLocalStream stream: RTCMediaStream, streamId: String, type: StreamType) {}
}

//MARK: - Co-browse signalling

extension CobrowseSessionController: CobrowseSignallingDelegate {

    func cobrowseUserEventReceived(_ type: RtcUserEventType, json: JSON) {
        guard !isEnding else { return }

        switch type {
        case .cobrowseDisplayCaptureRequest:
            agentRequestedShare()
        case .cobrowseDisplayCaptureTerminate:
            if state == .sharing {
                stopSharing()
                overlay.showToast(style: .info, title: nil, message: CobrowseStrings.agentStoppedViewing(agent?.name))
            }
        case .sketchCanvasUpdated, .sketchUserJoined, .sketchAvailabilityChanged, .arPointerIndicated:
            sketch?.userEventReceived(type, json: json)
        }
    }

    func cobrowseMetadataChanged(_ event: ConferenceMetadataUpdatedEvent) {
        guard !isEnding else { return }
        sketch?.metadataChanged(key: event.key, operation: event.operation, rawValue: event.rawValue)
    }
}
