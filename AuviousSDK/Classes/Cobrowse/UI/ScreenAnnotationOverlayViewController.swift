//
//  ScreenAnnotationOverlayViewController.swift
//  AuviousSDK
//
//  Created by Auvious on 22/10/26.
//

import UIKit

/**
 The AR pointer over a regular screen share: the agent's points and ink over the whole app, and an
 [Annotate] dock that expands into the drawing tools. Shown in a `CobrowseOverlayWindow`, so touches
 reach the app underneath unless the customer is annotating.
 */
internal final class ScreenAnnotationOverlayViewController: UIViewController {

    let surface = AnnotationSurfaceView()
    let pill = CobrowseStatusPillView()
    let dock = CobrowseDockView()

    var onUndo: (() -> Void)?
    var onClear: (() -> Void)?

    var inkColor: UIColor = SketchGeometry.color(hex: SketchGeometry.fallbackColor)! {
        didSet {
            applyState()
        }
    }

    private(set) var isAnnotating = false
    private var tool: SketchTool = .laser

    override func loadView() {
        view = CobrowsePassthroughView()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        surface.frame = view.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(surface)
        view.addSubview(pill)
        view.addSubview(dock)

        dock.showsLaser = true
        dock.onDraw = { [weak self] in
            self?.setAnnotating(true)
        }
        dock.onDone = { [weak self] in
            self?.setAnnotating(false)
        }
        dock.onToolSelected = { [weak self] tool in
            self?.tool = tool
            self?.applyState()
        }
        dock.onUndo = { [weak self] in
            self?.onUndo?()
        }
        dock.onClear = { [weak self] in
            self?.onClear?()
        }
        pill.setMode(.drawing)
        applyState()
    }

    func setAnnotating(_ annotating: Bool) {
        isAnnotating = annotating
        if annotating {
            tool = .laser
        }
        applyState()
    }

    private func applyState() {
        guard isViewLoaded else { return }

        surface.tool = tool
        surface.isAnnotating = isAnnotating
        surface.canvas.inkColor = inkColor
        pill.isHidden = !isAnnotating
        dock.setMode(isAnnotating ? .drawing(tool: tool, inkColor: inkColor) : .annotate)

        view.setNeedsLayout()
        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let pillSize = pill.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let pillWidth = min(pillSize.width, view.bounds.width - 32)
        pill.frame = CGRect(x: (view.bounds.width - pillWidth) / 2, y: view.safeAreaInsets.top + CobrowseTheme.pillTop, width: pillWidth, height: CobrowseTheme.pillHeight)

        let dockSize = dock.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let dockWidth = min(dockSize.width, view.bounds.width - 24)
        let bottom = view.bounds.height - max(view.safeAreaInsets.bottom, CobrowseTheme.dockMargin) - CobrowseTheme.dockMargin
        dock.frame = CGRect(x: (view.bounds.width - dockWidth) / 2, y: bottom - dockSize.height, width: dockWidth, height: dockSize.height)
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
}
