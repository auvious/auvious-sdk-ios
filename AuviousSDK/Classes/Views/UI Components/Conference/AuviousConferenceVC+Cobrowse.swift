//
//  AuviousConferenceVC+Cobrowse.swift
//  AuviousSDK
//
//  Created by Auvious on 22/10/26.
//

import UIKit
import SwiftyJSON

//In-call co-browse: the agent asks this endpoint to share its screen. The customer shares from the call's own
//endpoint, the call shrinks to PiP while sharing, and the co-browse overlay (pill, dock, glow, drawings) does the rest.
extension AuviousConferenceVCNew {

    /// Listens for the agent's co-browse requests, when the host app allows co-browse in the call
    func listenForCobrowse() {
        guard clientConfiguration.cobrowseAvailable else { return }
        AuviousConferenceSDK.sharedInstance.cobrowseDelegate = self
    }

    private func cobrowseRequested(_ json: JSON) {
        //A running session takes the request itself (it is the signalling delegate then)
        if let session = cobrowseSession {
            session.agentRequestedShare()
            return
        }
        guard conferenceJoined, let conference = currentConference else { return }

        //A regular screen share gives way to co-browse
        let sdk = AuviousConferenceSDK.sharedInstance
        if sdk.sharingMyScreen {
            sdk.stopLocalScreenShare()
            localScreenShareStreamId = nil
            stopScreenSharingButton.alpha = 0
            toggleSharingBorder(mode: false)
        }

        let session = CobrowseSessionController(inCallWith: CobrowseSessionController.Options(clientConfiguration))
        session.onSharingChanged = { [weak self] sharing in
            self?.cobrowseSharingChanged(sharing)
        }
        session.onWillEnd = { [weak self] _ in
            self?.cobrowseWillEnd()
        }
        session.onEnd = { [weak self] _ in
            self?.cobrowseEnded()
        }
        cobrowseSession = session

        MaskRegistry.shared.rules = clientConfiguration.cobrowseMasking
        refreshCobrowseChrome()

        session.startInCall(agent: requester(in: json), participants: conference.participants ?? [], metadata: pendingCobrowseMetadata)
        pendingCobrowseMetadata = []
    }

    /// The agent who sent the request (`originator`), so the replies go to them
    private func requester(in json: JSON) -> CobrowseSessionController.Agent? {
        let originator = json["originator"].exists() ? json["originator"] : json["payload"]["originator"]
        guard let userId = originator["username"].string, let endpointId = originator["endpoint"].string else {
            return nil
        }
        return CobrowseSessionController.Agent(userId: userId, endpointId: endpointId, name: nil)
    }

    /// The call is going away: co-browse ends with it, without restoring the call's layout or the ended toast
    func endCobrowseWithCall(_ reason: AuviousCobrowseEndReason) {
        screenModeBeforeCobrowse = nil
        cobrowseSession?.end(reason: reason, quietly: true)
    }

    private func cobrowseSharingChanged(_ sharing: Bool) {
        if sharing {
            if screenModeBeforeCobrowse == nil {
                screenModeBeforeCobrowse = screenMode
            }
            //The agent never sees the call: it moves to the co-browse overlay, which isn't part of the shared screen
            moveCallToCobrowseOverlay()
            //Out of the way, so the customer can use the app
            if screenMode == .fullScreen {
                minimizeToPiP()
            }
            if !didNotifyCobrowseStarted {
                didNotifyCobrowseStarted = true
                delegate?.onCobrowseStarted()
            }
        }
        refreshCobrowseChrome()
    }

    /// The screen is no longer shared: back to the call as it was
    private func cobrowseWillEnd() {
        //The host app shows the screen that hosts the call again, before the call moves back into it
        if didNotifyCobrowseStarted {
            didNotifyCobrowseStarted = false
            delegate?.onCobrowseEnded()
        }
        moveCallBackFromCobrowseOverlay()
        let previous = screenModeBeforeCobrowse
        screenModeBeforeCobrowse = nil

        guard conferenceJoined else { return }
        if previous == .fullScreen && screenMode != .fullScreen {
            expandToFullScreen()
        }
    }

    private func cobrowseEnded() {
        cobrowseSession = nil
        refreshCobrowseChrome()
        //Ready for the agent's next request
        if conferenceJoined {
            listenForCobrowse()
        }
        //An AR pointer may have started while co-browsing
        refreshArPointer()
    }

    private func moveCallToCobrowseOverlay() {
        guard callHostSuperview == nil, let session = cobrowseSession, let superview = view.superview else { return }

        let container = session.callContainer
        callHostSuperview = superview
        callHostIndex = superview.subviews.firstIndex(of: view)

        //Same place on screen, now in the overlay window
        let frame = superview.convert(view.frame, to: container)
        isMovingCallForCobrowse = true
        container.addSubview(view)
        isMovingCallForCobrowse = false
        view.frame = frame
    }

    private func moveCallBackFromCobrowseOverlay() {
        guard let superview = callHostSuperview else { return }
        callHostSuperview = nil

        let frame = view.superview?.convert(view.frame, to: superview) ?? superview.bounds
        //Back while the host screen is still appearing (onCobrowseEnded), UIKit cycles the call's appearance here
        isMovingCallForCobrowse = true
        superview.insertSubview(view, at: min(callHostIndex ?? superview.subviews.count, superview.subviews.count))
        isMovingCallForCobrowse = false
        view.frame = frame
        callHostIndex = nil
    }

    /// Call controls that change while co-browsing
    func refreshCobrowseChrome() {
        guard isViewLoaded, buttonContainerView != nil else { return }

        let session = cobrowseSession
        let isFullScreen = screenMode == .fullScreen

        //Full screen, the call's own "Stop co-browsing" button replaces the dock
        session?.setDockHidden(isFullScreen)
        stopScreenSharingButton.title = session != nil ? CobrowseStrings.stopCobrowsing : "Stop sharing"

        updateScreenShareButton()

        showsCallHiddenChip(session?.isSharing == true && isFullScreen, agentName: session?.agentName)
    }

    /// "<Agent> can't see the call", while sharing with the call full screen
    private func showsCallHiddenChip(_ shows: Bool, agentName: String?) {
        guard shows else {
            callHiddenChip?.removeFromSuperview()
            callHiddenChip = nil
            return
        }

        let label = UILabel()
        label.text = CobrowseStrings.callHidden(agentName)
        label.font = CobrowseTheme.font(12, .semibold)
        label.textColor = .white

        if let chip = callHiddenChip as? UIStackView {
            (chip.arrangedSubviews.last as? UILabel)?.text = label.text
            return
        }

        let icon = UIImageView(image: CobrowseTheme.symbol("eye.slash", size: 12, weight: .semibold))
        icon.tintColor = .white

        let chip = UIStackView(arrangedSubviews: [icon, label])
        chip.axis = .horizontal
        chip.spacing = 6
        chip.alignment = .center
        chip.isLayoutMarginsRelativeArrangement = true
        chip.layoutMargins = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 12)
        chip.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        chip.layer.cornerRadius = 14
        chip.isUserInteractionEnabled = false
        chip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chip)

        //Below the co-browse status pill
        NSLayoutConstraint.activate([
            chip.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: CobrowseTheme.pillTop + CobrowseTheme.pillHeight + 12),
            chip.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            chip.heightAnchor.constraint(equalToConstant: 28)
        ])
        callHiddenChip = chip
    }
}

//MARK: - Co-browse signalling

//Called from the SDK's signalling thread while no co-browse session is running
extension AuviousConferenceVCNew: CobrowseSignallingDelegate {

    func cobrowseUserEventReceived(_ type: RtcUserEventType, json: JSON) {
        guard type == .cobrowseDisplayCaptureRequest else { return }
        DispatchQueue.main.async { [weak self] in
            self?.cobrowseRequested(json)
        }
    }

    func cobrowseMetadataChanged(_ event: ConferenceMetadataUpdatedEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            //The agent can set up the sketch before asking; the session replays these when it starts
            self.pendingCobrowseMetadata.append(event)
            if self.pendingCobrowseMetadata.count > 20 {
                self.pendingCobrowseMetadata.removeFirst()
            }
        }
    }
}
