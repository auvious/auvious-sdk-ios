//
//  CobrowseDockView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// The floating control dock. Compact while sharing ([Draw] [End]), expanded while drawing
/// ([Pen] [Arrow] [Undo] [Clear] | [✓]). It can be dragged to the top or bottom edge.
/// AR pointer annotations use it too: [Annotate] compact, and a Laser tool first while drawing.
internal final class CobrowseDockView: UIView {

    enum Mode: Equatable {
        case connecting
        case sharing(canDraw: Bool)
        case notSharing
        /// AR pointer, not annotating: a single [Annotate] button
        case annotate
        case drawing(tool: SketchTool, inkColor: UIColor)
    }

    /// Offers the AR pointer's laser tool while drawing
    var showsLaser = false {
        didSet {
            if oldValue != showsLaser {
                rebuild()
            }
        }
    }

    var onCancel: (() -> Void)?
    var onDraw: (() -> Void)?
    var onShare: (() -> Void)?
    var onEnd: (() -> Void)?
    var onDone: (() -> Void)?
    var onToolSelected: ((SketchTool) -> Void)?
    var onUndo: (() -> Void)?
    var onClear: (() -> Void)?

    var accentColor: UIColor = CobrowseTheme.defaultAccent {
        didSet { rebuild() }
    }

    private(set) var mode: Mode = .connecting

    private let background = UIVisualEffectView(effect: nil)
    private let stack = UIStackView()
    private var laserButton: UIButton?
    private var penButton: UIButton?
    private var arrowButton: UIButton?
    private var clearButton: UIButton?
    private var isConfirmingClear = false
    private var clearConfirmWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        setUpBackground()

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -6)
        ])

        accessibilityHint = CobrowseStrings.moveControls
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMode(_ mode: Mode) {
        guard mode != self.mode else { return }
        let previous = self.mode
        self.mode = mode

        //Switching tools only restyles the buttons, so they stay put
        if case .drawing = previous, case .drawing(let tool, let inkColor) = mode, let pen = penButton, let arrow = arrowButton {
            styleTool(pen, selected: tool == .pen, inkColor: inkColor)
            styleTool(arrow, selected: tool == .arrow, inkColor: inkColor)
            if let laser = laserButton {
                styleTool(laser, selected: tool == .laser, inkColor: inkColor)
            }
            return
        }

        //New buttons are laid out in place right away, never animated in from a zero frame
        UIView.performWithoutAnimation {
            rebuild()
            layoutIfNeeded()
        }
    }

    //MARK: Layout

    /// Dark Liquid Glass on iOS 26 and later, a dark blur before that
    private func setUpBackground() {
        background.translatesAutoresizingMaskIntoConstraints = false
        background.overrideUserInterfaceStyle = .dark
        background.clipsToBounds = true
        background.layer.cornerRadius = (CobrowseTheme.dockButtonHeight + 12) / 2
        background.layer.cornerCurve = .continuous

        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = CobrowseTheme.dock.withAlphaComponent(0.55)
            glass.isInteractive = true
            background.effect = glass
            background.cornerConfiguration = .capsule()
        } else {
            background.effect = UIBlurEffect(style: .systemThickMaterialDark)
            background.backgroundColor = CobrowseTheme.dock.withAlphaComponent(0.35)
        }
        addSubview(background)
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        laserButton = nil
        penButton = nil
        arrowButton = nil
        clearButton = nil
        isConfirmingClear = false
        clearConfirmWorkItem?.cancel()

        switch mode {
        case .connecting:
            stack.spacing = 6
            stack.addArrangedSubview(labelButton(CobrowseStrings.cancel, image: nil, background: CobrowseTheme.dockGlassButton, foreground: .white, action: #selector(cancelTapped)))

        case .sharing(let canDraw):
            stack.spacing = 6
            if canDraw {
                stack.addArrangedSubview(labelButton(CobrowseStrings.draw, image: CobrowseTheme.penIcon(size: 22), background: CobrowseTheme.dockGlassButton, foreground: .white, action: #selector(drawTapped)))
            }
            stack.addArrangedSubview(endButton())

        case .notSharing:
            stack.spacing = 6
            stack.addArrangedSubview(labelButton(CobrowseStrings.shareScreen, image: CobrowseTheme.symbol("iphone"), background: CobrowseTheme.dockGlassButton, foreground: .white, action: #selector(shareTapped)))
            stack.addArrangedSubview(endButton())

        case .annotate:
            stack.spacing = 6
            stack.addArrangedSubview(labelButton(CobrowseStrings.annotate, image: CobrowseTheme.penIcon(size: 22), background: CobrowseTheme.dockGlassButton, foreground: .white, action: #selector(drawTapped)))

        case .drawing(let tool, let inkColor):
            stack.spacing = 4
            if showsLaser {
                let laser = iconButton(CobrowseTheme.laserIcon(), label: CobrowseStrings.laserPointer, action: #selector(laserTapped))
                styleTool(laser, selected: tool == .laser, inkColor: inkColor)
                laserButton = laser
                stack.addArrangedSubview(laser)
            }
            let pen = iconButton(CobrowseTheme.penIcon(), label: CobrowseStrings.pen, action: #selector(penTapped))
            let arrow = iconButton(CobrowseTheme.lineSymbol("arrow.up.right"), label: CobrowseStrings.arrow, action: #selector(arrowTapped))
            styleTool(pen, selected: tool == .pen, inkColor: inkColor)
            styleTool(arrow, selected: tool == .arrow, inkColor: inkColor)
            penButton = pen
            arrowButton = arrow

            let undo = iconButton(CobrowseTheme.lineSymbol("arrow.uturn.left"), label: CobrowseStrings.undo, action: #selector(undoTapped))
            let clear = iconButton(CobrowseTheme.lineSymbol("trash"), label: CobrowseStrings.clearDrawings, action: #selector(clearTapped))
            clearButton = clear

            let divider = UIView()
            divider.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            divider.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                divider.widthAnchor.constraint(equalToConstant: 1),
                divider.heightAnchor.constraint(equalToConstant: 28)
            ])

            //Done is a tick, so it fits however narrow the dock gets
            let done = iconButton(CobrowseTheme.symbol("checkmark", size: 20, weight: .bold), label: CobrowseStrings.done, action: #selector(doneTapped))
            done.backgroundColor = .white
            done.tintColor = CobrowseTheme.dock

            for view in [pen, arrow, undo, clear, divider, done] {
                stack.addArrangedSubview(view)
            }
            stack.setCustomSpacing(8, after: clear)
            stack.setCustomSpacing(8, after: divider)
        }
    }

    private func labelButton(_ title: String, image: UIImage?, background: UIColor, foreground: UIColor, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = CobrowseTheme.font(15, .semibold)
        button.setTitleColor(foreground, for: .normal)
        button.tintColor = foreground
        button.backgroundColor = background
        button.layer.cornerRadius = CobrowseTheme.dockButtonHeight / 2
        if let image = image {
            button.setImage(image, for: .normal)
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 22, bottom: 0, right: 18)
        } else {
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        }
        button.heightAnchor.constraint(equalToConstant: CobrowseTheme.dockButtonHeight).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    /// End, in the SDK's red gradient
    private func endButton() -> UIButton {
        let button = CobrowseAccentButton(type: .custom)
        button.accentColor = accentColor
        button.setTitle(CobrowseStrings.end, for: .normal)
        button.titleLabel?.font = CobrowseTheme.font(15, .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        button.heightAnchor.constraint(equalToConstant: CobrowseTheme.dockButtonHeight).isActive = true
        button.addTarget(self, action: #selector(endTapped), for: .touchUpInside)
        return button
    }

    private func iconButton(_ image: UIImage?, label: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.tintColor = .white
        button.layer.cornerRadius = CobrowseTheme.dockButtonHeight / 2
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: CobrowseTheme.dockButtonHeight),
            button.heightAnchor.constraint(equalToConstant: CobrowseTheme.dockButtonHeight)
        ])
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func styleTool(_ button: UIButton, selected: Bool, inkColor: UIColor) {
        button.backgroundColor = selected ? inkColor : .clear
        button.tintColor = selected ? CobrowseTheme.dock : .white
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }

    //MARK: Actions

    @objc private func cancelTapped() { onCancel?() }
    @objc private func drawTapped() { onDraw?() }
    @objc private func shareTapped() { onShare?() }
    @objc private func endTapped() { onEnd?() }
    @objc private func doneTapped() { onDone?() }
    @objc private func laserTapped() { onToolSelected?(.laser) }
    @objc private func penTapped() { onToolSelected?(.pen) }
    @objc private func arrowTapped() { onToolSelected?(.arrow) }
    @objc private func undoTapped() { onUndo?() }

    /// Clear needs a second tap: the trash icon turns into a red "Clear" button for 3 seconds.
    @objc private func clearTapped() {
        guard let clearButton = clearButton else { return }

        if isConfirmingClear {
            clearConfirmWorkItem?.cancel()
            isConfirmingClear = false
            onClear?()
            resetClearButton(clearButton)
            return
        }

        isConfirmingClear = true
        clearButton.setImage(nil, for: .normal)
        clearButton.setTitle(CobrowseStrings.clear, for: .normal)
        clearButton.titleLabel?.font = CobrowseTheme.font(13, .semibold)
        clearButton.setTitleColor(.white, for: .normal)
        clearButton.backgroundColor = accentColor
        clearButton.accessibilityLabel = CobrowseStrings.clearConfirm
        UIAccessibility.post(notification: .announcement, argument: CobrowseStrings.clearConfirm)

        let workItem = DispatchWorkItem { [weak self, weak clearButton] in
            guard let self = self, let button = clearButton else { return }
            self.isConfirmingClear = false
            self.resetClearButton(button)
        }
        clearConfirmWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func resetClearButton(_ button: UIButton) {
        button.setTitle(nil, for: .normal)
        button.setImage(CobrowseTheme.lineSymbol("trash"), for: .normal)
        button.backgroundColor = .clear
        button.accessibilityLabel = CobrowseStrings.clearDrawings
    }
}
