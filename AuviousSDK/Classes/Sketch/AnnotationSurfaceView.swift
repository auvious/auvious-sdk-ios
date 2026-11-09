//
//  AnnotationSurfaceView.swift
//  AuviousSDK
//
//  Created by Auvious on 22/10/26.
//

import UIKit

/**
 Where an AR pointer session is drawn: the sketch canvas plus the laser points, over the whole shared
 screen or over a call tile's video. While annotating, the laser tool turns taps into points and the
 pen and arrow draw on the canvas; otherwise touches go through.
 */
internal final class AnnotationSurfaceView: UIView {

    let canvas = SketchCanvasView()
    let laser = LaserPointerView()

    /// A tap with the laser tool, in this view's coordinates, with this view's size as the area
    var onPoint: ((CGPoint, CGSize) -> Void)?

    /// Camera sketches live in the mirrored self-view space of the web clients, so they are flipped
    /// over video that is shown unmirrored. Points are never mirrored.
    var isSketchMirrored = false {
        didSet {
            canvas.transform = isSketchMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        }
    }

    var tool: SketchTool = .laser {
        didSet {
            canvas.tool = tool
            applyInteraction()
        }
    }

    /// While true, touches annotate instead of reaching what is underneath
    var isAnnotating = false {
        didSet {
            applyInteraction()
        }
    }

    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false

        for layer in [canvas, laser] as [UIView] {
            layer.frame = bounds
            addSubview(layer)
        }
        canvas.tool = tool
        addGestureRecognizer(tap)
        applyInteraction()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        //The canvas may be flipped, so it is laid out through bounds and center
        canvas.bounds = CGRect(origin: .zero, size: bounds.size)
        canvas.center = CGPoint(x: bounds.midX, y: bounds.midY)
        laser.frame = bounds
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isAnnotating else { return nil }
        return super.hitTest(point, with: event)
    }

    private func applyInteraction() {
        isUserInteractionEnabled = isAnnotating
        canvas.isDrawingEnabled = isAnnotating && tool != .laser
        tap.isEnabled = isAnnotating && tool == .laser
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        onPoint?(gesture.location(in: self), bounds.size)
    }
}
