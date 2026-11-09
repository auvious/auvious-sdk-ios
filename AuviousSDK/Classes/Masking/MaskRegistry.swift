//
//  MaskRegistry.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// A region to black out, in screen points
internal struct MaskRegion: Equatable {
    let rect: CGRect
    /// Which rule matched (shown by the debug highlight)
    let reason: String
    let isKeyboard: Bool
}

/// The latest masked regions, read from the capture queue
internal struct MaskSnapshot {
    /// Padded rects in screen points
    let rects: [CGRect]
    /// Screen size in points, in the current orientation
    let screenSize: CGSize
    /// `CACurrentMediaTime()` when the snapshot was taken
    let timestamp: CFTimeInterval
    /// True while a screen transition moves masked content: positions can't be trusted, frames are dropped
    var isUnsafe: Bool = false

    static let empty = MaskSnapshot(rects: [], screenSize: .zero, timestamp: 0)
}

/**
 The recent mask snapshots, so a captured frame can be masked with the layout it actually shows.

 ReplayKit hands frames over some milliseconds after they were rendered. While content moves (scrolling,
 transitions) the latest snapshot is already ahead of the frame, so masking with it leaves the real
 position uncovered. Instead every position a masked view had around the frame's timestamp is masked:
 the boxes stretch along the motion, but never miss.
 */
internal struct MaskHistory {

    /// How long snapshots are kept
    static let retention: CFTimeInterval = 1

    /// How far back from the frame timestamp the shown layout may be: the frame shows the layout committed
    /// on the previous refresh, so two 60 Hz refreshes cover it (four on ProMotion)
    static let lookBehind: CFTimeInterval = 0.034

    /// How far after the frame timestamp a snapshot may still describe it (snapshots trail layout by a refresh)
    static let lookAhead: CFTimeInterval = 0.017

    private(set) var snapshots: [MaskSnapshot] = []

    mutating func append(_ snapshot: MaskSnapshot) {
        snapshots.append(snapshot)
        let oldest = snapshot.timestamp - MaskHistory.retention
        if let firstKept = snapshots.firstIndex(where: { $0.timestamp >= oldest }), firstKept > 0 {
            snapshots.removeFirst(firstKept)
        }
    }

    mutating func removeAll() {
        snapshots.removeAll()
    }

    /// Every masked rect around `frameTime`, or nil when the history doesn't reach back to the frame
    func snapshot(forFrameAt frameTime: CFTimeInterval) -> MaskSnapshot? {
        guard let latest = snapshots.last else { return nil }

        let start = frameTime - MaskHistory.lookBehind
        let end = frameTime + MaskHistory.lookAhead
        var used = snapshots.filter { $0.timestamp >= start && $0.timestamp <= end }

        //The layout that was on screen when the window opened
        if let before = snapshots.last(where: { $0.timestamp < start }) {
            used.insert(before, at: 0)
        }

        //A frame from before our history: we can't tell what it shows
        guard !used.isEmpty else { return nil }

        return MaskSnapshot(rects: used.flatMap { $0.rects },
                            screenSize: latest.screenSize,
                            timestamp: used.map { $0.timestamp }.max() ?? latest.timestamp,
                            isUnsafe: used.contains { $0.isUnsafe })
    }
}

/**
 Finds the masked views on every display refresh and publishes their screen rects for the capture queue.

 Matching walks the app's windows each tick (no swizzling), so views that appear or get an identifier later
 are picked up on the next refresh.
 */
internal final class MaskRegistry {

    static let shared = MaskRegistry()

    /// Extra margin around every masked view, in points
    static let padding: CGFloat = 6

    var rules = AuviousMaskingRules()

    var debugHighlight = false {
        didSet {
            lastRegions = []
        }
    }

    /// Called on the main thread whenever the masked regions change (for the on-device hints)
    var onRegionsChanged: (([MaskRegion]) -> Void)?

    /// Our own overlay window, never masked or walked
    weak var excludedWindow: UIWindow?

    private(set) var isRunning = false

    private var displayLink: CADisplayLink?
    private let lock = NSLock()
    private var currentSnapshot = MaskSnapshot.empty
    private var history = MaskHistory()
    private var lastRegions: [MaskRegion] = []
    /// Whether the last snapshot taken outside a screen transition had anything masked
    private var lastStableSnapshotHadMasks = false
    private weak var focusedInput: UIView?
    private var keyboardFrame: CGRect = .zero
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// The latest snapshot. Thread safe.
    var snapshot: MaskSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return currentSnapshot
    }

    /// Every masked rect around the given frame time (`CACurrentMediaTime()` clock). Thread safe.
    func snapshot(forFrameAt frameTime: CFTimeInterval) -> MaskSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return history.snapshot(forFrameAt: frameTime)
    }

    //MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] note in
                self?.focusedInput = note.object as? UIView
            },
            center.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] note in
                self?.focusedInput = note.object as? UIView
            },
            center.addObserver(forName: UITextField.textDidEndEditingNotification, object: nil, queue: .main) { [weak self] note in
                if self?.focusedInput === note.object as? UIView {
                    self?.focusedInput = nil
                }
            },
            center.addObserver(forName: UITextView.textDidEndEditingNotification, object: nil, queue: .main) { [weak self] note in
                if self?.focusedInput === note.object as? UIView {
                    self?.focusedInput = nil
                }
            },
            center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
                if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    self?.keyboardFrame = frame
                }
            },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
                self?.keyboardFrame = .zero
            }
        ]

        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
        //Track layout at the display's full rate (120 Hz on ProMotion) to keep up with scrolling
        link.preferredFramesPerSecond = 0
        link.add(to: .main, forMode: .common)
        displayLink = link
        refresh()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        displayLink?.invalidate()
        displayLink = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        focusedInput = nil
        lastRegions = []
        onRegionsChanged?([])

        lock.lock()
        currentSnapshot = .empty
        history.removeAll()
        lock.unlock()
    }

    //MARK: Matching

    /// Recomputes the masked regions. Main thread only.
    func refresh() {
        let windows = appWindows()
        let screenBounds = (windows.first?.screen ?? UIScreen.main).bounds

        var regions: [MaskRegion] = []
        for window in windows {
            collect(window, screenBounds: screenBounds, into: &regions)
        }

        //Keyboard key pop-ups reveal what's typed in a masked field
        if let input = focusedInput, input.window != nil, !keyboardFrame.isEmpty, isMaskedSelfOrAncestor(input) {
            let keyboard = keyboardFrame.intersection(screenBounds)
            if !keyboard.isNull && !keyboard.isEmpty {
                regions.append(MaskRegion(rect: keyboard, reason: "keyboard", isKeyboard: true))
            }
        }

        let padding = MaskRegistry.padding
        let rects = regions.map { $0.rect.insetBy(dx: -padding, dy: -padding) }

        //During a screen transition (push, pop, present, interactive back) masked content moves in ways we can't
        //measure reliably, so frames are dropped until it settles, as long as anything masked is or was on screen
        let transitioning = isTransitionActive(in: windows)
        if !transitioning {
            lastStableSnapshotHadMasks = !rects.isEmpty
        }
        let isUnsafe = transitioning && (!rects.isEmpty || lastStableSnapshotHadMasks)

        let snapshot = MaskSnapshot(rects: rects, screenSize: screenBounds.size, timestamp: CACurrentMediaTime(), isUnsafe: isUnsafe)
        lock.lock()
        currentSnapshot = snapshot
        history.append(snapshot)
        lock.unlock()

        //The on-device hints disappear as soon as a transition starts and come back once it's done
        let hintRegions = transitioning ? [] : regions
        if hintRegions != lastRegions {
            lastRegions = hintRegions
            onRegionsChanged?(hintRegions)
        }
    }

    /// True while any view controller transition runs (navigation push/pop, modal present/dismiss,
    /// interactive back swipe). SwiftUI navigation goes through the same UIKit containers.
    private func isTransitionActive(in windows: [UIWindow]) -> Bool {
        return windows.contains { window in
            guard let root = window.rootViewController else { return false }
            return hasActiveTransition(root)
        }
    }

    private func hasActiveTransition(_ viewController: UIViewController) -> Bool {
        if viewController.transitionCoordinator != nil {
            return true
        }
        if viewController.children.contains(where: { hasActiveTransition($0) }) {
            return true
        }
        if let presented = viewController.presentedViewController, presented.presentingViewController === viewController {
            return hasActiveTransition(presented)
        }
        return false
    }

    private func appWindows() -> [UIWindow] {
        var windows: [UIWindow] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene, windowScene.activationState != .background else { continue }
            windows.append(contentsOf: windowScene.windows)
        }
        if windows.isEmpty {
            windows = UIApplication.shared.windows
        }
        return windows.filter { $0 !== excludedWindow && !$0.isHidden && $0.alpha > 0.01 }
    }

    private func collect(_ view: UIView, screenBounds: CGRect, into regions: inout [MaskRegion]) {
        //Visible if either the final or the on-screen (animating) opacity shows it, e.g. while fading out
        let onScreenOpacity = CGFloat(view.layer.presentation()?.opacity ?? Float(view.alpha))
        guard !view.isHidden, max(view.alpha, onScreenOpacity) > 0.01 else { return }

        if let reason = matchReason(for: view) {
            let rect = MaskRegistry.onScreenRect(of: view).intersection(screenBounds)
            if !rect.isNull && !rect.isEmpty {
                regions.append(MaskRegion(rect: rect, reason: reason, isKeyboard: false))
            }
            //The whole frame is covered, no need to look at subviews
            return
        }

        for subview in view.subviews {
            collect(subview, screenBounds: screenBounds, into: &regions)
        }
    }

    /// Where the view is drawn right now, in screen points. Uses the presentation layers, so views that are
    /// moving in an animation (navigation push/pop, sheets, scrolling animations) are measured where they
    /// appear, not where they will end up.
    static func onScreenRect(of view: UIView) -> CGRect {
        guard let window = view.window else {
            return view.convert(view.bounds, to: UIScreen.main.coordinateSpace)
        }

        let inWindow: CGRect
        if let layer = view.layer.presentation(), let windowLayer = window.layer.presentation() {
            //Presentation layers resolve their superlayers to presentation copies too, so the whole chain is on-screen state
            inWindow = layer.convert(layer.bounds, to: windowLayer)
        } else {
            //Not rendered yet: the final layout is all there is
            inWindow = view.convert(view.bounds, to: window)
        }
        return window.convert(inWindow, to: window.screen.coordinateSpace)
    }

    /// The rule that masks this view, or nil
    func matchReason(for view: UIView) -> String? {
        if let explicit = view.auviousMasked {
            return explicit ? "explicit" : nil
        }

        if !rules.accessibilityIdentifiers.isEmpty, let identifier = view.accessibilityIdentifier, !identifier.isEmpty, rules.matches(identifier: identifier) {
            return "id: \(identifier)"
        }

        for viewClass in rules.viewClasses where view.isKind(of: viewClass) {
            return "class: \(viewClass)"
        }

        if rules.maskAllTextInputs && (view is UITextField || view is UITextView) {
            return "text input"
        }

        if rules.maskSecureTextFields, let textField = view as? UITextField, textField.isSecureTextEntry {
            return "secure"
        }

        return nil
    }

    private func isMaskedSelfOrAncestor(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if matchReason(for: candidate) != nil {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}

/// Breaks the CADisplayLink -> target retain cycle
private final class DisplayLinkProxy {
    private weak var registry: MaskRegistry?

    init(_ registry: MaskRegistry) {
        self.registry = registry
    }

    @objc func tick() {
        registry?.refresh()
    }
}
