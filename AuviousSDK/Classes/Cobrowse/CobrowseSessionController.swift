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
    /// In a call, the customer stopping is sent like the agent's own terminate event
    static let displayCaptureTerminate = "CobrowseDisplayCaptureTerminateEvent"
}

/// Leave reason the agent maps to "the customer terminated the session"
private let customerTerminatedReason = "widgetScreenShareTerminated"

/**
 Runs one co-browse session:
 ticket → login → join as a display-capture participant → consent → ReplayKit screen share,
 plus the agent's requests, sketch annotations, masking and the app lifecycle.

 In a video call (`Mode.inCall`) the conference is already joined by `AuviousConferenceVCNew`: the session skips
 login and join, shares the screen from the call's own endpoint, and leaves the conference delegate to the call.
 */
internal final class CobrowseSessionController: NSObject {

    enum Mode {
        /// Its own session, redeeming a ticket
        case standalone(AuviousCobrowseConfiguration)
        /// Inside the video call that is already running
        case inCall
    }

    /// What the session needs from either configuration
    struct Options {
        var participantName: String?
        var showsShareExplainer = true
        var annotationsEnabled = true
        var showsMaskHints = true
        var accentColor: UIColor = CobrowseTheme.defaultAccent

        init(_ configuration: AuviousCobrowseConfiguration) {
            participantName = configuration.participantName
            showsShareExplainer = configuration.showsShareExplainer
            annotationsEnabled = configuration.annotationsEnabled
            showsMaskHints = configuration.showsMaskHints
            accentColor = configuration.accentColor
        }

        init(_ configuration: AuviousConferenceConfiguration) {
            participantName = configuration.participantName
            showsShareExplainer = configuration.cobrowseShowsShareExplainer
            annotationsEnabled = configuration.cobrowseAnnotationsEnabled
            showsMaskHints = configuration.cobrowseShowsMaskHints
        }
    }

    struct Agent {
        let userId: String
        let endpointId: String
        let name: String?
    }

    var onStateChange: ((AuviousCobrowseState) -> Void)?
    var onFailure: ((AuviousSDKGenericError) -> Void)?
    var onEnd: ((AuviousCobrowseEndReason) -> Void)?
    /// In a call: the screen started (true) or stopped (false) being shared
    var onSharingChanged: ((Bool) -> Void)?
    /// The session is ending and the screen is no longer captured (the ended toast may still show before `onEnd`)
    var onWillEnd: ((AuviousCobrowseEndReason) -> Void)?

    private let mode: Mode
    private let options: Options
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
    /// Ends without the "ended" toast (declined, or the call itself is going away)
    private var endsQuietly = false
    /// Standalone: the reason sent when leaving the conference
    private var leaveReason = ""

    private var isInCall: Bool {
        if case .inCall = mode {
            return true
        }
        return false
    }

    /// The agent's name, once known
    var agentName: String? {
        return agent?.name
    }

    /// True while the screen is shared
    var isSharing: Bool {
        return state == .sharing
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(configuration: AuviousCobrowseConfiguration) {
        self.mode = .standalone(configuration)
        self.options = Options(configuration)
        super.init()
    }

    /// A session inside the running video call
    init(inCallWith options: Options) {
        self.mode = .inCall
        self.options = options
        super.init()
    }

    //MARK: Start

    func start() {
        guard case .standalone(let configuration) = mode else {
            return
        }

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

        //Holds on to self, so a session ended while logging in still logs out
        sdk.login(onLoginSuccess: { _, conferenceId in
            self.resolveConference(conferenceId)
        }, onLoginFailure: { [weak self] error in
            self?.fail(with: error)
        })
    }

    /**
     Starts an in-call session after the agent asked to see the screen. The call owns the conference and its delegate.

     - Parameter agent: The agent who asked, if known (falls back to the conference's agent)
     - Parameter participants: The conference's participants, to find the agent and their name
     - Parameter metadata: Sketch / AR pointer metadata received before the session started
     */
    func startInCall(agent requester: Agent?, participants: [ConferenceParticipant], metadata: [ConferenceMetadataUpdatedEvent]) {
        guard isInCall else { return }

        installOverlay()
        hasJoined = true

        sdk.cobrowseDelegate = self
        sdk.screenStreamIsCobrowse = true
        sdk.screenFrameProcessor = { sampleBuffer, pixelBuffer in
            return PixelBufferMasker.maskedFrame(sampleBuffer: sampleBuffer, pixelBuffer: pixelBuffer, registry: MaskRegistry.shared)
        }

        //The requester, named from the participant list when the request didn't carry a name
        for participant in participants {
            for endpoint in participant.endpoints ?? [] {
                if let requester = requester, endpoint.id == requester.endpointId {
                    agentFound(userId: requester.userId, endpointId: requester.endpointId, name: requester.name ?? endpoint.name)
                } else if requester == nil, agent == nil, isAgent(endpoint.roles) {
                    agentFound(userId: participant.id, endpointId: endpoint.id, name: endpoint.name)
                }
            }
        }
        if let requester = requester, agent == nil {
            agentFound(userId: requester.userId, endpointId: requester.endpointId, name: requester.name)
        }

        sketch?.applyJoinMetadata(sdk.joinedConferenceMetadata)
        metadata.forEach { sketch?.metadataChanged(key: $0.key, operation: $0.operation, rawValue: $0.rawValue) }

        observeLifecycle()
        askToShare()
    }

    private func installOverlay() {
        overlay.accentColor = options.accentColor
        overlay.annotationsEnabled = options.annotationsEnabled
        overlay.hints.showsHints = options.showsMaskHints
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

        if options.annotationsEnabled {
            let session = SketchSession(canvas: overlay.canvas)
            session.onInkColorChanged = { [weak self] _ in
                self?.overlay.inkColorChanged()
            }
            sketch = session
        }

        let window = CobrowseOverlayWindow.make(rootViewController: overlay)
        window.isHidden = false
        self.window = window
        CobrowseOverlayWindow.holdsPortrait = true

        MaskRegistry.shared.excludedWindow = window
        MaskRegistry.shared.onRegionsChanged = { [weak self] regions in
            self?.overlay.hints.update(regions: regions, debug: MaskRegistry.shared.debugHighlight)
        }
    }

    //MARK: Connecting

    /// The conference comes with the token (conference_id); fall back to the ticket's properties
    private func resolveConference(_ conferenceId: String?) {
        guard case .standalone(let configuration) = mode else { return }
        //Ended while logging in: the teardown in end() ran before we were logged in
        guard !isEnding else {
            leaveAndLogout()
            return
        }

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
        //Holds on to self, so a session ended while joining still leaves
        sdk.joinConference(conferenceId: conferenceId, onSuccess: { conference in
            guard !self.isEnding else {
                self.leaveAndLogout()
                return
            }
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

        guard options.showsShareExplainer else {
            requestShare()
            return
        }

        state = .awaitingConsent
        overlay.setPhase(.awaitingConsent)

        let name = agent?.name
        var bullets = [CobrowseStrings.explainerAppOnly, CobrowseStrings.explainerPrivate]
        if isInCall {
            bullets.append(CobrowseStrings.explainerCallContinues)
        }
        if options.annotationsEnabled {
            bullets.append(CobrowseStrings.explainerDraw)
        }
        let content = CobrowseSheetView.Content(iconSymbol: "iphone",
                                                title: isInCall ? CobrowseStrings.inCallExplainerTitle(name) : CobrowseStrings.explainerTitle(name),
                                                body: nil,
                                                bullets: bullets,
                                                primaryTitle: isInCall ? CobrowseStrings.inCallStart : CobrowseStrings.startSharing,
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

        //In a call that is still reconnecting (back from the background), share once it's back
        if isInCall && sdk.currentConferenceId == nil {
            resumeSharingOnForeground = true
            state = .notSharing
            overlay.setPhase(.notSharing)
            return
        }

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
            sdkLog("Co-browse publish failed %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
            shareFailed()
            return
        }

        let since = Date()
        sharingSince = since
        state = .sharing
        overlay.setPhase(.sharing(since: since))
        sendToAgent(CobrowseEventName.displayCaptureAccept)
        onSharingChanged?(true)
    }

    private func shareDeclined() {
        stopCapture()
        sendToAgent(CobrowseEventName.displayCaptureDeny)

        //In a call there's nothing to stay connected to: the agent can ask again
        if isInCall && sharingSince == nil {
            endsQuietly = true
            end(reason: .customerEnded)
            return
        }

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
        stopCapture()
        sharingSince = nil
        state = .notSharing
        overlay.setPhase(.notSharing)
        onSharingChanged?(false)
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

    /// In a call: where the call's view goes while co-browsing, above the drawings and below the co-browse controls
    var callContainer: UIView {
        return overlay.callContainer
    }

    /// While the video call is full screen its own "Stop co-browsing" button replaces the dock
    func setDockHidden(_ hidden: Bool) {
        overlay.hidesDock = hidden
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
            sdkLog("Co-browse event %@ failed %@", log: Log.conferenceSDK, type: .error, eventType, error.localizedDescription)
        })
    }

    func agentRequestedShare() {
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

    func confirmEnd() {
        let content = CobrowseSheetView.Content(iconSymbol: nil,
                                                title: isInCall ? CobrowseStrings.inCallEndTitle : CobrowseStrings.endTitle,
                                                body: isInCall ? CobrowseStrings.inCallEndBody(agent?.name) : CobrowseStrings.endBody(agent?.name),
                                                bullets: [],
                                                primaryTitle: isInCall ? CobrowseStrings.inCallEndSession : CobrowseStrings.endSession,
                                                secondaryTitle: CobrowseStrings.keepSharing,
                                                footnote: nil)
        overlay.showSheet(content, onPrimary: { [weak self] in
            self?.end(reason: .customerEnded)
        }, onSecondary: {})
    }

    private func fail(with error: Error) {
        guard !isEnding else { return }
        sdkLog("Co-browse failed %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
        onFailure?(genericError(for: error))
        end(reason: .failed)
    }

    /**
     Ends the session.

     - Parameter quietly: Skip the "ended" toast, e.g. when the call itself is going away
     */
    func end(reason: AuviousCobrowseEndReason, quietly: Bool = false) {
        guard !isEnding else { return }
        isEnding = true
        endsQuietly = endsQuietly || quietly

        overlay.dismissSheet()
        //Nothing is shared anymore, so no drawings either
        sketch?.reset()
        overlay.canvas.removeAll()

        let wasSharing = sharingSince != nil
        sharingSince = nil

        switch mode {
        case .standalone:
            leaveReason = reason == .customerEnded ? customerTerminatedReason : ""
            //Holds on to self: finish() may release the session before the capture has stopped
            stopCapture {
                if reason != .agentEnded {
                    self.leaveAndLogout()
                } else {
                    self.logout()
                }
            }

        case .inCall:
            //The call goes on: only the screen stops, and the agent hears that the customer ended it
            stopCapture()
            if reason == .customerEnded && !endsQuietly {
                sendToAgent(CobrowseEventName.displayCaptureTerminate)
            }
        }

        resetSDK()
        stopObservingLifecycle()
        endBackgroundTask()
        state = .ended
        if wasSharing {
            onSharingChanged?(false)
        }
        onWillEnd?(reason)

        //Let the customer know the screen is no longer shared before the overlay goes away
        if hasJoined && reason != .failed && !endsQuietly {
            let title = isInCall ? CobrowseStrings.inCallEnded : CobrowseStrings.sessionEnded
            let body = isInCall ? CobrowseStrings.inCallEndedBody(agent?.name) : CobrowseStrings.sessionEndedBody(agent?.name)
            overlay.setPhase(.notSharing)
            overlay.pill.isHidden = true
            overlay.dock.isHidden = true
            overlay.showToast(style: .ended, title: title, message: body, duration: 2.5) { [weak self] in
                self?.finish(reason: reason)
            }
        } else {
            finish(reason: reason)
        }
    }

    private func leaveAndLogout() {
        guard let conferenceId = sdk.currentConferenceId else {
            logout()
            return
        }
        sdk.leaveConference(conferenceId: conferenceId, reason: leaveReason, onSuccess: {
            self.logout()
        }, onFailure: { _ in
            self.logout()
        })
    }

    private func logout() {
        sdk.logout(onSuccess: {}, onFailure: { error in
            sdkLog("Co-browse logout failed %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
        })
    }

    private func resetSDK() {
        //In a call the conference delegate and join profile belong to the call
        if !isInCall {
            sdk.delegate = nil
            sdk.joinProfile = .stream
            sdk.isCobrowseActive = false
        }
        sdk.cobrowseDelegate = nil
        sdk.screenFrameProcessor = nil
        sdk.screenStreamIsCobrowse = false

        MaskRegistry.shared.stop()
        MaskRegistry.shared.onRegionsChanged = nil
        MaskRegistry.shared.excludedWindow = nil
    }

    private func finish(reason: AuviousCobrowseEndReason) {
        window?.isHidden = true
        window = nil
        CobrowseOverlayWindow.holdsPortrait = false
        onEnd?(reason)
    }

    private func genericError(for error: Error) -> AuviousSDKGenericError {
        if let sdkError = error as? AuviousSDKError {
            switch sdkError {
            case .INVALID_TICKET(let ticketId):
                return .INVALID_TICKET(ticketId: ticketId)
            case .httpError(let code) where code == 401 || code == 404:
                if case .standalone(let configuration) = mode {
                    return .INVALID_TICKET(ticketId: configuration.ticket)
                }
                return .UNKNOWN_FAILURE
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

        //The call reconnects itself; sharing picks up once it's back (callResumed())
        if isInCall {
            if resumeSharingOnForeground {
                state = .notSharing
                overlay.setPhase(.notSharing)
                //With background audio the call never dropped, so it may have resumed before we got here
                if sdk.currentConferenceId != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.callResumed()
                    }
                }
            }
            return
        }

        sdk.restoreCobrowseConnection(onSuccess: { [weak self] in
            guard let self = self, !self.isEnding else { return }
            if self.resumeSharingOnForeground {
                self.resumeSharingOnForeground = false
                //The capture stopped in the background, the state still says sharing
                self.state = .notSharing
                self.overlay.setPhase(.notSharing)
                self.requestShare()
            }
        }, onFailure: { [weak self] error in
            self?.fail(with: error)
        })
    }

    /// In a call: the call is connected again after the app returned to the foreground
    func callResumed() {
        guard isInCall, !isEnding, !isInBackground, resumeSharingOnForeground else { return }
        resumeSharingOnForeground = false
        requestShare()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

//MARK: - Conference SDK delegate

//The SDK calls these from its signalling thread, everything here drives UI so it hops to main
extension CobrowseSessionController: AuviousSDKConferenceDelegate {

    func auviousSDK(didReceiveConferenceEvent event: ConferenceEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.conferenceEventReceived(event)
        }
    }

    private func conferenceEventReceived(_ event: ConferenceEvent) {
        switch event.type {
        case .conferenceEnded?:
            end(reason: .agentEnded)

        case .conferenceJoined?:
            if let joined = event as? ConferenceJoinedEvent, isAgent(joined.roles) {
                agentFound(userId: joined.userId, endpointId: joined.userEndpointId, name: joined.name)
            }

        case .conferenceLeft?:
            if event.userEndpointId == agent?.endpointId {
                sdkLog("Co-browse agent endpoint left", log: Log.conferenceSDK, type: .debug)
            }

        default:
            break
        }
    }

    func auviousSDK(screenSharingStopped: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.screenSharingStopped()
        }
    }

    func auviousSDK(onError error: AuviousSDKError) {
        sdkLog("Co-browse SDK error %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)

        DispatchQueue.main.async { [weak self] in
            self?.sdkError(error)
        }
    }

    /// The capture stopped. Main thread; the call forwards it in an in-call session.
    func screenSharingStopped() {
        //Stopped without us asking (ICE failure, ReplayKit interruption), not by going to the background
        guard !isStoppingShare, !isEnding, !isInBackground, state == .sharing,
              UIApplication.shared.applicationState != .background else { return }
        shareFailed()
    }

    /// An SDK error. Main thread; the call forwards it in an in-call session.
    func sdkError(_ error: AuviousSDKError) {
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

//Also called from the SDK's signalling thread
extension CobrowseSessionController: CobrowseSignallingDelegate {

    func cobrowseUserEventReceived(_ type: RtcUserEventType, json: JSON) {
        DispatchQueue.main.async { [weak self] in
            self?.userEventReceived(type, json: json)
        }
    }

    private func userEventReceived(_ type: RtcUserEventType, json: JSON) {
        guard !isEnding else { return }

        switch type {
        case .cobrowseDisplayCaptureRequest:
            agentRequestedShare()
        case .cobrowseDisplayCaptureTerminate:
            if isInCall {
                //In a call the agent stopping ends co-browsing; the call goes on
                end(reason: .agentEnded)
            } else if state == .sharing {
                stopSharing()
                overlay.showToast(style: .info, title: nil, message: CobrowseStrings.agentStoppedViewing(agent?.name))
            }
        case .sketchCanvasUpdated, .sketchUserJoined, .sketchAvailabilityChanged:
            sketch?.userEventReceived(type, json: json)
        case .arPointerIndicated, .arPointerFreezeFrameChanged:
            //No AR pointer on a co-browse screen, only sketch
            break
        }
    }

    func cobrowseMetadataChanged(_ event: ConferenceMetadataUpdatedEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isEnding else { return }
            self.sketch?.metadataChanged(key: event.key, operation: event.operation, rawValue: event.rawValue)
        }
    }
}
