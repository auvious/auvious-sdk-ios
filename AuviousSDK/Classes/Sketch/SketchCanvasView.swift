//
//  SketchCanvasView.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// Full-screen annotation layer. Stores and renders everyone's sketch items in the shared 720 unit
/// project space, and turns the customer's touches into new items while drawing is enabled.
internal final class SketchCanvasView: UIView {

    /// Items are unique per author endpoint and id
    struct ItemKey: Hashable, Comparable {
        let id: Int64
        let userEndpointId: String

        static func < (lhs: ItemKey, rhs: ItemKey) -> Bool {
            if lhs.id != rhs.id {
                return lhs.id < rhs.id
            }
            return lhs.userEndpointId < rhs.userEndpointId
        }
    }

    private struct Entry {
        let item: PaperItem
        let data: SketchItemData
        let layer: CALayer
    }

    /// Who is drawing locally (userId, userEndpointId). Nil before login.
    var localIdentity: (() -> (userId: String, endpointId: String)?)?

    /// Called when the customer finishes an item
    var onLocalItemCreated: ((PaperItem) -> Void)?

    var tool: SketchTool = .pen {
        didSet {
            isUserInteractionEnabled = isDrawingEnabled && tool != .laser
            cancelStroke()
        }
    }
    var inkColor: UIColor = SketchGeometry.color(hex: SketchGeometry.fallbackColor)!

    /// While true, touches draw instead of reaching the app. The laser tool never draws.
    var isDrawingEnabled: Bool = false {
        didSet {
            isUserInteractionEnabled = isDrawingEnabled && tool != .laser
            if !isDrawingEnabled {
                cancelStroke()
            }
        }
    }

    private var entries: [ItemKey: Entry] = [:]
    private var renderedScale: CGFloat = 0
    private var lastLocalId: Int64 = 0

    //Stroke in progress, in project units
    private var strokePoints: [CGPoint] = []
    private let strokeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isMultipleTouchEnabled = false

        strokeLayer.fillColor = UIColor.clear.cgColor
        strokeLayer.lineCap = .round
        strokeLayer.lineJoin = .round
        strokeLayer.zPosition = 1_000_000
        layer.addSublayer(strokeLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var scale: CGFloat {
        return SketchGeometry.scale(for: bounds.size)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        strokeLayer.frame = bounds

        //Re-render when the width (and therefore the project scale) changes, e.g. on rotation
        if abs(renderedScale - scale) > 0.0001 {
            renderedScale = scale
            for (key, entry) in entries {
                entry.layer.removeFromSuperlayer()
                let layer = makeLayer(for: entry.item)
                self.layer.addSublayer(layer)
                entries[key] = Entry(item: entry.item, data: entry.data, layer: layer)
            }
            applyZOrder()
        }
    }

    //MARK: Store

    /// Adds a remote or local item. Returns false if it was already present.
    @discardableResult
    func add(_ item: PaperItem) -> Bool {
        guard let data = item.itemData else { return false }

        let key = ItemKey(id: data.id, userEndpointId: data.userEndpointId)
        guard entries[key] == nil else { return false }

        let itemLayer = makeLayer(for: item)
        layer.addSublayer(itemLayer)
        entries[key] = Entry(item: item, data: data, layer: itemLayer)
        applyZOrder()
        return true
    }

    /// Removes every item with the given id (the web matches erase requests on id only)
    func remove(id: Int64) {
        for key in entries.keys where key.id == id {
            entries[key]?.layer.removeFromSuperlayer()
            entries[key] = nil
        }
    }

    func removeAll(where shouldRemove: (SketchItemData) -> Bool = { _ in true }) {
        for (key, entry) in entries where shouldRemove(entry.data) {
            entry.layer.removeFromSuperlayer()
            entries[key] = nil
        }
    }

    /// Items drawn from the given endpoint, oldest first
    func items(ownedBy endpointId: String) -> [PaperItem] {
        return entries.keys.filter { $0.userEndpointId == endpointId }.sorted().compactMap { entries[$0]?.item }
    }

    /// The most recent item drawn from the given endpoint
    func lastItemData(ownedBy endpointId: String) -> SketchItemData? {
        return entries.keys.filter { $0.userEndpointId == endpointId }.sorted().last.flatMap { entries[$0]?.data }
    }

    var isEmpty: Bool {
        return entries.isEmpty
    }

    private func applyZOrder() {
        for (index, key) in entries.keys.sorted().enumerated() {
            entries[key]?.layer.zPosition = CGFloat(index)
        }
    }

    //MARK: Rendering

    private func makeLayer(for item: PaperItem, parentTransform: CGAffineTransform = .identity) -> CALayer {
        switch item {
        case .path(let path):
            return makePathLayer(path, parentTransform: parentTransform)

        case .group(let group):
            let container = CALayer()
            container.frame = bounds
            let transform = SketchCanvasView.transform(from: group.matrix).concatenating(parentTransform)
            for child in group.children {
                container.addSublayer(makeLayer(for: child, parentTransform: transform))
            }
            if let opacity = group.opacity {
                container.opacity = Float(opacity)
            }
            return container

        case .unsupported:
            return CALayer()
        }
    }

    private func makePathLayer(_ path: PaperPath, parentTransform: CGAffineTransform) -> CAShapeLayer {
        let k = scale
        var transform = SketchCanvasView.transform(from: path.matrix)
            .concatenating(parentTransform)
            .concatenating(CGAffineTransform(scaleX: k, y: k))

        let shape = CAShapeLayer()
        shape.frame = bounds
        shape.path = SketchCanvasView.bezierPath(for: path.segments, closed: path.closed ?? false).cgPath.copy(using: &transform)
        shape.fillColor = UIColor.clear.cgColor
        shape.strokeColor = (path.strokeColor?.uiColor ?? .black).cgColor
        shape.lineWidth = max(CGFloat(path.strokeWidth ?? 1) * k, SketchGeometry.minimumRenderedWidth)
        shape.lineCap = path.strokeCap == "butt" ? .butt : (path.strokeCap == "square" ? .square : .round)
        shape.lineJoin = path.strokeJoin == "miter" ? .miter : (path.strokeJoin == "bevel" ? .bevel : .round)
        if let opacity = path.opacity {
            shape.opacity = Float(opacity)
        }
        return shape
    }

    /// Cubic bezier through paper segments: cp1 = previous point + previous handleOut, cp2 = point + handleIn
    static func bezierPath(for segments: [PaperSegment], closed: Bool) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = segments.first else { return path }

        path.move(to: first.point)
        func curve(from previous: PaperSegment, to current: PaperSegment) {
            if previous.handleOut == .zero && current.handleIn == .zero {
                path.addLine(to: current.point)
            } else {
                path.addCurve(to: current.point,
                              controlPoint1: CGPoint(x: previous.point.x + previous.handleOut.x, y: previous.point.y + previous.handleOut.y),
                              controlPoint2: CGPoint(x: current.point.x + current.handleIn.x, y: current.point.y + current.handleIn.y))
            }
        }

        if segments.count > 1 {
            for index in 1..<segments.count {
                curve(from: segments[index - 1], to: segments[index])
            }
        }

        if closed, segments.count > 1, let last = segments.last {
            curve(from: last, to: first)
            path.close()
        }
        return path
    }

    static func transform(from matrix: [Double]?) -> CGAffineTransform {
        guard let m = matrix, m.count == 6 else { return .identity }
        return CGAffineTransform(a: CGFloat(m[0]), b: CGFloat(m[1]), c: CGFloat(m[2]), d: CGFloat(m[3]), tx: CGFloat(m[4]), ty: CGFloat(m[5]))
    }

    //MARK: Drawing input

    private func projectPoint(_ touch: UITouch) -> CGPoint {
        let location = touch.location(in: self)
        let k = scale
        return CGPoint(x: location.x / k, y: location.y / k)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingEnabled, let touch = touches.first else { return }

        strokePoints = [projectPoint(touch)]
        strokeLayer.strokeColor = inkColor.cgColor
        strokeLayer.lineWidth = max(CGFloat(SketchGeometry.outgoingStrokeWidth(for: bounds.size)) * scale, SketchGeometry.minimumRenderedWidth)
        updateStrokeLayer()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingEnabled, let touch = touches.first, let first = strokePoints.first else { return }

        let point = projectPoint(touch)
        switch tool {
        case .pen:
            if let last = strokePoints.last, hypot(point.x - last.x, point.y - last.y) >= SketchGeometry.minimumPointDistance {
                strokePoints.append(point)
            }
        case .arrow:
            strokePoints = [first, point]
        case .laser:
            return
        }
        updateStrokeLayer()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingEnabled else { return }

        if let touch = touches.first, tool == .pen, let last = strokePoints.last {
            let point = projectPoint(touch)
            if point != last {
                strokePoints.append(point)
            }
        }

        let points = strokePoints
        cancelStroke()

        guard let item = makeLocalItem(from: points) else { return }
        add(item)
        onLocalItemCreated?(item)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelStroke()
    }

    private func cancelStroke() {
        strokePoints = []
        strokeLayer.path = nil
    }

    private func updateStrokeLayer() {
        let k = scale
        let path = UIBezierPath()
        let points = strokePoints.map { CGPoint(x: $0.x * k, y: $0.y * k) }
        guard let first = points.first else {
            strokeLayer.path = nil
            return
        }

        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }

        if tool == .arrow, points.count == 2 {
            let head = SketchGeometry.arrowHead(from: strokePoints[0], to: strokePoints[1]).map { CGPoint(x: $0.x * k, y: $0.y * k) }
            path.move(to: head[0])
            path.addLine(to: head[1])
            path.addLine(to: head[2])
        }
        strokeLayer.path = path.cgPath
    }

    /// Builds a paper item the web clients can import (same shape as paper's exportJSON)
    private func makeLocalItem(from points: [CGPoint]) -> PaperItem? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }

        let identity = localIdentity?() ?? (userId: "", endpointId: "")
        let color = PaperColor(inkColor)
        let width = SketchGeometry.outgoingStrokeWidth(for: bounds.size)

        //Ids are epoch milliseconds, kept strictly increasing for our own items
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        lastLocalId = max(now, lastLocalId + 1)

        switch tool {
        case .pen:
            let simplified = SketchGeometry.simplify(points, tolerance: SketchGeometry.simplifyTolerance)
            guard simplified.count >= 2 else { return nil }
            let data = SketchItemData(tool: "path", id: lastLocalId, userId: identity.userId, userEndpointId: identity.endpointId)
            let path = PaperPath(data: data,
                                 segments: simplified.map { PaperSegment(point: $0) },
                                 strokeColor: color,
                                 strokeWidth: width,
                                 shadowColor: color,
                                 shadowBlur: 1)
            return .path(path)

        case .arrow:
            guard hypot(last.x - first.x, last.y - first.y) >= SketchGeometry.minimumPointDistance * 2 else { return nil }
            let data = SketchItemData(tool: "arrow", id: lastLocalId, userId: identity.userId, userEndpointId: identity.endpointId)
            let shaft = PaperPath(data: nil, segments: [PaperSegment(point: first), PaperSegment(point: last)], strokeColor: color, strokeWidth: width)
            let head = PaperPath(data: nil, segments: SketchGeometry.arrowHead(from: first, to: last).map { PaperSegment(point: $0) }, strokeColor: color, strokeWidth: width)
            return .group(PaperGroup(data: data, children: [.path(shaft), .path(head)]))

        case .laser:
            return nil
        }
    }
}
