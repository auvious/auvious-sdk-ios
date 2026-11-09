//
//  CobrowseOverlayWindow.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// A window above the host app that only keeps the touches that land on co-browse controls
/// (or on the canvas while drawing). Everything else falls through to the app underneath.
/// It is never made key, so it doesn't steal the first responder or the keyboard.
internal final class CobrowseOverlayWindow: UIWindow {

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    override var canBecomeKey: Bool {
        return false
    }

    /// Creates the window in the app's active scene
    static func make(rootViewController: UIViewController) -> CobrowseOverlayWindow {
        let window: CobrowseOverlayWindow
        if let scene = activeWindowScene() {
            window = CobrowseOverlayWindow(windowScene: scene)
        } else {
            window = CobrowseOverlayWindow(frame: UIScreen.main.bounds)
        }
        window.windowLevel = UIWindow.Level.alert + 1
        window.backgroundColor = .clear
        window.rootViewController = rootViewController
        return window
    }

    /// True while a co-browse session shows its overlay: the app is held in portrait
    /// (see `AuviousCobrowse.supportedInterfaceOrientations(otherwise:)`)
    static var holdsPortrait = false {
        didSet {
            guard holdsPortrait != oldValue else { return }
            updateOrientation()
        }
    }

    /// Asks UIKit to apply the supported orientations again: to portrait when the session starts,
    /// back to the app's own (and the device's orientation) once it ends
    private static func updateOrientation() {
        if #available(iOS 16.0, *) {
            guard let scene = activeWindowScene() else { return }
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            if holdsPortrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }
}

/// A view that never handles touches itself, only its interactive subviews do
internal final class CobrowsePassthroughView: UIView {

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/**
 Hosts and lays out the co-browse chrome: edge glow, status pill, dock, sketch canvas, mask hints,
 sheets and toasts. There is no AR pointer while co-browsing, only sketch.
 */
internal final class CobrowseOverlayViewController: UIViewController {

    enum Phase: Equatable {
        case connecting
        case awaitingConsent
        case sharing(since: Date)
        case drawing(since: Date)
        case notSharing
    }

    enum DockEdge {
        case top
        case bottom
    }

    let glow = CobrowseEdgeGlowView()
    let pill = CobrowseStatusPillView()
    let dock = CobrowseDockView()
    let canvas = SketchCanvasView()
    let hints = CobrowseMaskHintsView()
    /// In a video call, holds the call's PiP while co-browsing. Like the rest of this window it is never part of
    /// the shared screen, so the agent sees the app behind the call instead of a masked box.
    let callContainer = CobrowsePassthroughView()

    var accentColor: UIColor = CobrowseTheme.defaultAccent {
        didSet {
            glow.color = accentColor
            pill.accentColor = accentColor
            dock.accentColor = accentColor
        }
    }

    var annotationsEnabled = true

    /// Hides the dock while the video call is full screen; the call has its own "Stop co-browsing" button
    var hidesDock = false {
        didSet {
            if oldValue != hidesDock {
                applyPhase()
            }
        }
    }

    var tool: SketchTool = .pen {
        didSet {
            canvas.tool = tool
            applyPhase()
        }
    }

    private(set) var phase: Phase = .connecting
    private var dockEdge: DockEdge = .bottom
    private var keyboardFrame: CGRect = .zero
    private var dragOffset: CGFloat?
    private var sheet: CobrowseSheetView?

    override func loadView() {
        view = CobrowsePassthroughView()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        for fullScreen in [hints, canvas, callContainer, glow] as [UIView] {
            fullScreen.frame = view.bounds
            fullScreen.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(fullScreen)
        }

        view.addSubview(pill)
        view.addSubview(dock)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(dockPanned(_:)))
        dock.addGestureRecognizer(pan)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        glow.alpha = 0
        applyPhase()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    //MARK: Host app appearance

    /// The host app's top view controller, so the overlay keeps the app's status bar and orientations
    private var hostViewController: UIViewController? {
        let windows = (view.window?.windowScene?.windows ?? UIApplication.shared.windows).filter { !($0 is CobrowseOverlayWindow) && !$0.isHidden }
        var top = windows.first { $0.isKeyWindow }?.rootViewController ?? windows.first?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return hostViewController?.preferredStatusBarStyle ?? .default
    }

    override var prefersStatusBarHidden: Bool {
        return hostViewController?.prefersStatusBarHidden ?? false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return hostViewController?.supportedInterfaceOrientations ?? .all
    }

    //MARK: Phases

    func setPhase(_ phase: Phase) {
        self.phase = phase
        applyPhase()
    }

    private func applyPhase() {
        guard isViewLoaded else { return }

        let showsChrome = phase != .awaitingConsent
        pill.isHidden = !showsChrome
        dock.isHidden = !showsChrome || hidesDock

        //"Private" hints only make sense while the screen is shared
        switch phase {
        case .sharing, .drawing:
            hints.isHidden = false
        default:
            hints.isHidden = true
        }

        switch phase {
        case .connecting:
            glow.setVisible(false, animated: true)
            pill.setMode(.connecting)
            dock.setMode(.connecting)
            canvas.isDrawingEnabled = false

        case .awaitingConsent:
            glow.setVisible(false, animated: true)
            canvas.isDrawingEnabled = false

        case .sharing(let since):
            glow.setVisible(true, animated: true)
            pill.setMode(.sharing(since: since))
            dock.setMode(.sharing(canDraw: annotationsEnabled))
            canvas.isDrawingEnabled = false

        case .drawing:
            glow.setVisible(true, animated: true)
            pill.setMode(.drawing)
            dock.setMode(.drawing(tool: tool, inkColor: canvas.inkColor))
            canvas.isDrawingEnabled = true

        case .notSharing:
            glow.setVisible(false, animated: true)
            pill.setMode(.notSharing)
            dock.setMode(.notSharing)
            canvas.isDrawingEnabled = false
        }

        view.setNeedsLayout()
        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    /// Re-renders the drawing tools after the ink color changes
    func inkColorChanged() {
        if case .drawing = phase {
            dock.setMode(.drawing(tool: tool, inkColor: canvas.inkColor))
        }
    }

    //MARK: Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPill()
        if dragOffset == nil {
            layoutDock()
        }
    }

    private func layoutPill() {
        let size = pill.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let width = min(size.width, view.bounds.width - 32)
        pill.frame = CGRect(x: (view.bounds.width - width) / 2, y: view.safeAreaInsets.top + CobrowseTheme.pillTop, width: width, height: CobrowseTheme.pillHeight)
    }

    private func dockFrame(for edge: DockEdge) -> CGRect {
        let size = dock.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let width = min(size.width, view.bounds.width - 24)
        let x = (view.bounds.width - width) / 2

        switch edge {
        case .top:
            return CGRect(x: x, y: pill.frame.maxY + 10, width: width, height: size.height)
        case .bottom:
            var bottom = view.bounds.height - max(view.safeAreaInsets.bottom, CobrowseTheme.dockMargin) - CobrowseTheme.dockMargin
            //Stay above the keyboard
            let keyboard = view.convert(keyboardFrame, from: view.window?.screen.coordinateSpace ?? UIScreen.main.coordinateSpace)
            if !keyboardFrame.isEmpty && keyboard.minY < view.bounds.height {
                bottom = min(bottom, keyboard.minY - CobrowseTheme.dockMargin)
            }
            return CGRect(x: x, y: bottom - size.height, width: width, height: size.height)
        }
    }

    private func layoutDock() {
        dock.frame = dockFrame(for: dockEdge)
    }

    @objc private func dockPanned(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: view)
        switch gesture.state {
        case .began:
            dragOffset = location.y - dock.frame.minY
        case .changed:
            guard let offset = dragOffset else { return }
            let minY = pill.frame.maxY + 4
            let maxY = view.bounds.height - dock.frame.height - 4
            dock.frame.origin.y = min(max(location.y - offset, minY), maxY)
        default:
            dragOffset = nil
            let velocity = gesture.velocity(in: view).y
            let projected = dock.frame.midY + velocity * 0.15
            dockEdge = projected < view.bounds.height / 2 ? .top : .bottom
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: {
                self.layoutDock()
            })
        }
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        keyboardFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        animateWithKeyboard(note)
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        keyboardFrame = .zero
        animateWithKeyboard(note)
    }

    private func animateWithKeyboard(_ note: Notification) {
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        UIView.animate(withDuration: duration) {
            self.layoutDock()
        }
    }

    //MARK: Sheets and toasts

    var isShowingSheet: Bool {
        return sheet != nil
    }

    func showSheet(_ content: CobrowseSheetView.Content, onPrimary: @escaping () -> Void, onSecondary: @escaping () -> Void) {
        dismissSheet()

        let sheet = CobrowseSheetView(content: content, accentColor: accentColor)
        sheet.onPrimary = { [weak self] in
            self?.dismissSheet()
            onPrimary()
        }
        sheet.onSecondary = { [weak self] in
            self?.dismissSheet()
            onSecondary()
        }
        sheet.present(in: view)
        self.sheet = sheet
    }

    func dismissSheet() {
        sheet?.dismiss()
        sheet = nil
    }

    func showToast(style: CobrowseToastView.Style, title: String?, message: String, duration: TimeInterval = 4, completion: (() -> Void)? = nil) {
        let toast = CobrowseToastView(style: style, title: title, message: message)
        if pill.isHidden {
            toast.show(in: view, below: view.safeAreaLayoutGuide.topAnchor, duration: duration, completion: completion)
        } else {
            //The pill is laid out with frames; anchor to its bottom through a guide
            let guide = UILayoutGuide()
            view.addLayoutGuide(guide)
            guide.topAnchor.constraint(equalTo: view.topAnchor, constant: pill.frame.maxY).isActive = true
            toast.show(in: view, below: guide.topAnchor, duration: duration, completion: { [weak self, weak guide] in
                if let guide = guide {
                    self?.view.removeLayoutGuide(guide)
                }
                completion?()
            })
        }
    }
}
