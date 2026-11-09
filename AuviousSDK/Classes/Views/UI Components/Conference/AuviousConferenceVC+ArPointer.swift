//
//  AuviousConferenceVC+ArPointer.swift
//  AuviousSDK
//
//  Created by Auvious on 22/10/26.
//

import UIKit
import SwiftyJSON
import os

//AR pointer: an agent points and draws on one of the call's streams. On a camera (ours or another customer's)
//the target tile takes the focus slot, with an [Annotate] dock at the bottom of it; on our regular screen share the
//points and ink are drawn over the whole app, in an overlay window above it.
extension AuviousConferenceVCNew {

    /// Listens for the agent's AR pointer and sketch, when the host app allows it
    func listenForArPointer() {
        guard clientConfiguration.arPointerAvailable else { return }
        AuviousConferenceSDK.sharedInstance.annotationDelegate = self

        arPointer.onChange = { [weak self] in
            self?.arPointerChanged()
        }
        arPointer.onInkColorChanged = { [weak self] _ in
            self?.applyArPointerTools()
        }
    }

    /// Picks up an AR pointer that started before we joined
    func arPointerConferenceJoined() {
        guard clientConfiguration.arPointerAvailable else { return }
        arPointer.applyJoinMetadata(AuviousConferenceSDK.sharedInstance.joinedConferenceMetadata)
    }

    /// The tile the AR pointer points at, which takes the focus slot
    var arPointerFocusView: StreamView? {
        guard let tile = arPointerTile, arPointer.target?.isScreen == false else { return nil }
        //Its participant may have just left: the tile is out of the call until refreshArPointer() lets go of it
        guard tile === localView || renderedRemoteViews.contains(where: { $0 === tile }) else { return nil }
        return tile
    }

    /// The tile in the focus slot: the AR pointer's target, else the agent's screen share
    var focusedView: StreamView? {
        return arPointerFocusView ?? shareScreenContainerView
    }

    /// While our own camera is pointed at, the camera stays as it is (same as the web)
    var isArPointerOnOurCamera: Bool {
        return arPointerFocusView === localView
    }

    /// Removes the AR pointer's views when the call ends
    func tearDownArPointer() {
        arPointer.detach()
        hideScreenAnnotation()
        removeArPointerFromTile()
    }

    //MARK: Session changes

    private func arPointerChanged() {
        let wasActive = arPointerTile != nil || screenAnnotationOverlay != nil
        refreshArPointer()
        let isActive = arPointerTile != nil || screenAnnotationOverlay != nil

        if isActive != wasActive {
            showNotification(with: isActive ? CobrowseStrings.laserActivated : CobrowseStrings.laserDeactivated, subtitle: nil, image: CobrowseTheme.laserIcon(stroke: 2))
        }
    }

    /// Places the session on the tile or screen it targets, once that stream is here. Called again when streams come and go.
    func refreshArPointer() {
        guard clientConfiguration.arPointerAvailable else {
            createConstraints()
            return
        }

        let target = arPointer.target
        let sdk = AuviousConferenceSDK.sharedInstance
        let me = sdk.userEndpointId

        //Our regular screen share
        if let target = target, target.isScreen, target.endpointId == me, sdk.sharingMyScreen, cobrowseSession == nil,
           [localScreenShareStreamId, sdk.localScreenStreamId].contains(target.correlationId) {
            removeArPointerFromTile()
            showScreenAnnotation()
        } else if let target = target, let tile = tile(for: target) {
            hideScreenAnnotation()
            showArPointer(on: tile)
        } else {
            hideScreenAnnotation()
            removeArPointerFromTile()
        }

        if let target = target {
            os_log("AR pointer on %@ %@ (%@): %@", log: Log.conferenceUI, type: .debug, target.endpointId, target.streamType, target.correlationId,
                   arPointerTile != nil ? "tile" : (screenAnnotationOverlay != nil ? "screen overlay" : "target not shown yet"))
        }

        updateFrozenBadge()
        applyArPointerControls()
        createConstraints()
    }

    private func tile(for target: ArPointerSession.Target) -> StreamView? {
        let sdk = AuviousConferenceSDK.sharedInstance

        //We publish a single camera stream, so any camera target on our endpoint is our tile
        //(its id may have changed since, e.g. after a rejoin)
        if target.endpointId == sdk.userEndpointId {
            return target.isScreen ? nil : localView
        }

        let candidates = target.isScreen ? [shareScreenContainerView].compactMap { $0 } : remoteViews
        return candidates.first { tile in
            guard let endpoint = tile.participantEndpoint, endpoint.id == target.endpointId else { return false }
            let streams = endpoint.streams ?? []
            //A tile without stream ids yet is matched on its endpoint alone
            return streams.isEmpty || streams.contains { stream in
                stream.id == target.correlationId || sdk.correlationId(ofRemoteStream: stream.id) == target.correlationId
            }
        }
    }

    //MARK: Camera tile

    private func showArPointer(on tile: StreamView) {
        //Already drawn there, unless a new pointer replaced the previous one (the session then let go of the surface)
        if arPointerTile === tile, let surface = arPointerTileSurface, arPointer.surface === surface {
            return
        }
        removeArPointerFromTile()

        //The agent wants to be seen: no PiP while pointing at a camera
        if screenMode != .fullScreen {
            expandToFullScreen()
        }

        let surface = AnnotationSurfaceView()
        //Camera sketches are mirrored on the web clients' views; our tiles show the video unmirrored
        surface.isSketchMirrored = arPointer.target?.isScreen == false
        tile.installAnnotationSurface(surface)
        arPointerTile = tile
        arPointerTileSurface = surface
        isArPointerAnnotating = false
        arPointerTool = .laser
        arPointer.attach(surface)

        let dock = CobrowseDockView()
        dock.showsLaser = true
        dock.translatesAutoresizingMaskIntoConstraints = false
        //Drawn above our tile too, which renders above its siblings (zPosition); bringSubviewToFront() only orders the touches
        dock.layer.zPosition = localView.layer.zPosition + 1
        dock.onDraw = { [weak self] in
            self?.setArPointerAnnotating(true)
        }
        dock.onDone = { [weak self] in
            self?.setArPointerAnnotating(false)
        }
        dock.onToolSelected = { [weak self] tool in
            self?.arPointerTool = tool
            self?.applyArPointerTools()
        }
        dock.onUndo = { [weak self] in
            self?.arPointer.undo()
        }
        dock.onClear = { [weak self] in
            self?.arPointer.clear()
        }
        //Next to the tile, not in it: placed by createConstraints() (arPointerDockConstraints)
        streamContainerView.addSubview(dock)
        arPointerDock = dock
        applyArPointerTools()
    }

    /// The [Annotate] dock at the bottom of the AR pointer tile's space. Given with the layout's constraints, so a tile shaped
    /// like its video (fitTilesToVideo) has the dock at the bottom of the space around it, off the video.
    /// Hidden while the layout doesn't place the tile (PiP).
    func arPointerDockConstraints(layout: [NSLayoutConstraint]) -> [NSLayoutConstraint] {
        guard let dock = arPointerDock, let tile = arPointerTile else { return [] }
        let placed = tile.superview === dock.superview && layout.contains { $0.firstItem === tile || $0.secondItem === tile }
        dock.isHidden = !placed
        guard placed else { return [] }
        dock.superview?.bringSubviewToFront(dock)
        return [
            dock.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            dock.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -12),
            dock.widthAnchor.constraint(lessThanOrEqualTo: tile.widthAnchor, constant: -16)
        ]
    }

    private func removeArPointerFromTile() {
        guard let tile = arPointerTile else { return }

        if arPointer.surface === arPointerTileSurface {
            arPointer.detach()
        }
        tile.removeAnnotationSurface()
        arPointerDock?.removeFromSuperview()
        arPointerFreezeBadge?.removeFromSuperview()
        arPointerDock = nil
        arPointerFreezeBadge = nil
        arPointerTileSurface = nil
        arPointerTile = nil
        isArPointerAnnotating = false
    }

    private func setArPointerAnnotating(_ annotating: Bool) {
        isArPointerAnnotating = annotating
        if annotating {
            arPointerTool = .laser
        }
        applyArPointerTools()
    }

    private func applyArPointerTools() {
        let ink = arPointer.inkColor
        if let surface = arPointerTileSurface {
            surface.tool = arPointerTool
            surface.isAnnotating = isArPointerAnnotating
            surface.canvas.inkColor = ink
        }
        arPointerDock?.setMode(isArPointerAnnotating ? .drawing(tool: arPointerTool, inkColor: ink) : .annotate)
        screenAnnotationOverlay?.inkColor = ink
    }

    /// "Frame paused by agent", while the agent froze the target's frame
    private func updateFrozenBadge() {
        guard let tile = arPointerTile, arPointer.isFrozen else {
            arPointerFreezeBadge?.removeFromSuperview()
            arPointerFreezeBadge = nil
            return
        }
        guard arPointerFreezeBadge == nil else { return }

        let badge = UIView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        badge.layer.cornerRadius = 15
        badge.isUserInteractionEnabled = false

        let icon = UIImageView(image: CobrowseTheme.symbol("snowflake", size: 13))
        icon.tintColor = .white
        let label = UILabel()
        label.text = CobrowseStrings.framePaused
        label.font = CobrowseTheme.font(13, .medium)
        label.textColor = .white

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(stack)
        tile.addSubview(badge)

        NSLayoutConstraint.activate([
            badge.heightAnchor.constraint(equalToConstant: 30),
            badge.topAnchor.constraint(equalTo: tile.topAnchor, constant: 12),
            badge.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])
        arPointerFreezeBadge = badge
    }

    /// Our camera can't change while it is pointed at, and there is no screen sharing during a pointer session
    func applyArPointerControls() {
        guard !isConferenceOnHold else { return }
        let cameraLocked = isArPointerOnOurCamera
        for button in [buttonContainerView.cameraButton, buttonContainerView.cameraSwitchButton] {
            button.alpha = cameraLocked ? 0.5 : 1
            button.isUserInteractionEnabled = !cameraLocked
        }
        updateScreenShareButton()
    }

    //MARK: Screen share overlay

    private func showScreenAnnotation() {
        if let overlay = screenAnnotationOverlay {
            //A new pointer replaced the previous one: draw it on the same overlay
            if arPointer.surface !== overlay.surface {
                overlay.setAnnotating(false)
                arPointer.attach(overlay.surface)
                overlay.inkColor = arPointer.inkColor
            }
            return
        }

        let overlay = ScreenAnnotationOverlayViewController()
        overlay.onUndo = { [weak self] in
            self?.arPointer.undo()
        }
        overlay.onClear = { [weak self] in
            self?.arPointer.clear()
        }
        let window = CobrowseOverlayWindow.make(rootViewController: overlay)
        window.isHidden = false
        overlay.loadViewIfNeeded()
        screenAnnotationWindow = window
        screenAnnotationOverlay = overlay

        arPointer.attach(overlay.surface)
        overlay.inkColor = arPointer.inkColor
    }

    private func hideScreenAnnotation() {
        guard let overlay = screenAnnotationOverlay else { return }

        if arPointer.surface === overlay.surface {
            arPointer.detach()
        }
        screenAnnotationWindow?.isHidden = true
        screenAnnotationWindow = nil
        screenAnnotationOverlay = nil
    }
}

extension AuviousConferenceVCNew: AnnotationSignallingDelegate {

    func annotationUserEventReceived(_ type: RtcUserEventType, json: JSON) {
        DispatchQueue.main.async { [weak self] in
            self?.arPointer.userEventReceived(type, json: json)
        }
    }

    func annotationMetadataChanged(_ event: ConferenceMetadataUpdatedEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.arPointer.metadataChanged(key: event.key, operation: event.operation, rawValue: event.rawValue)
        }
    }
}
