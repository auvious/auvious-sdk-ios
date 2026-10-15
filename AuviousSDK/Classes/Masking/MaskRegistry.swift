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

    static let empty = MaskSnapshot(rects: [], screenSize: .zero, timestamp: 0)
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
    private var lastRegions: [MaskRegion] = []
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
        link.preferredFramesPerSecond = 60
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

        lock.lock()
        currentSnapshot = MaskSnapshot(rects: rects, screenSize: screenBounds.size, timestamp: CACurrentMediaTime())
        lock.unlock()

        if regions != lastRegions {
            lastRegions = regions
            onRegionsChanged?(regions)
        }
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
        guard !view.isHidden, view.alpha > 0.01 else { return }

        if let reason = matchReason(for: view) {
            let rect = view.convert(view.bounds, to: view.window?.screen.coordinateSpace ?? UIScreen.main.coordinateSpace).intersection(screenBounds)
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
