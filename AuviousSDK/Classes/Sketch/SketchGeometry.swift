//
//  SketchGeometry.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit

/// Drawing tools offered to the customer
internal enum SketchTool: Equatable {
    case pen
    case arrow
    /// AR pointer: a tap places a numbered point instead of drawing
    case laser
}

/// Constants and math shared with the web sketch implementation.
internal enum SketchGeometry {

    /// The visible area is always this many project units wide (web: lockRatio + syncedWidth 720)
    static let projectWidth: CGFloat = 720

    /// A new pen point is sampled only after moving this many project units (paper minDistance)
    static let minimumPointDistance: CGFloat = 3

    /// Ramer–Douglas–Peucker tolerance applied when a pen stroke ends, in project units
    static let simplifyTolerance: CGFloat = 1.5

    /// Arrow head length in project units
    static let arrowHeadLength: CGFloat = 24

    /// Angle of each arrow head side relative to the shaft direction, in degrees
    static let arrowHeadAngle: CGFloat = 140

    /// Thinnest stroke rendered on the phone, in points. The web default (3 units) is ~1.6pt on a phone, too thin to see.
    static let minimumRenderedWidth: CGFloat = 3

    /// Colors claimable in AR_POINTER_COLORS, in the web's order
    static let palette: [String] = ["#F75A51", "#4BCF5F", "#338CF7", "#F7CE33", "#F7A234", "#B26FD3", "#c39953", "#5C341F", "#90DABB"]

    /// Ink used when no color is claimed for this endpoint
    static let fallbackColor = "#F7A234"

    /// Order in which the customer picks an unclaimed color (red last, it clashes with the sharing border)
    static let customerFallbackOrder: [String] = ["#F7A234", "#338CF7", "#4BCF5F", "#B26FD3", "#F7CE33", "#90DABB", "#c39953", "#5C341F", "#F75A51"]

    /// Points per project unit for a view of the given size
    static func scale(for size: CGSize) -> CGFloat {
        guard size.width > 0 else { return 1 }
        return size.width / projectWidth
    }

    /// Stroke width in project units that renders at least `minimumRenderedWidth` points on this device
    static func outgoingStrokeWidth(for size: CGSize) -> Double {
        let k = scale(for: size)
        return Double(max(3, (minimumRenderedWidth / k).rounded(.up)))
    }

    /// The three points of an arrow head: [side, tip, side] (web: arrow.ts)
    static func arrowHead(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return [end, end, end] }

        let ux = dx / length * arrowHeadLength
        let uy = dy / length * arrowHeadLength

        func rotated(_ degrees: CGFloat) -> CGPoint {
            let radians = degrees * .pi / 180
            let x = ux * cos(radians) - uy * sin(radians)
            let y = ux * sin(radians) + uy * cos(radians)
            return CGPoint(x: end.x + x, y: end.y + y)
        }

        return [rotated(arrowHeadAngle), end, rotated(-arrowHeadAngle)]
    }

    /// Ramer–Douglas–Peucker polyline simplification
    static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last > first + 1 else { continue }

            var maxDistance: CGFloat = 0
            var index = first
            for i in (first + 1)..<last {
                let distance = perpendicularDistance(points[i], points[first], points[last])
                if distance > maxDistance {
                    maxDistance = distance
                    index = i
                }
            }

            if maxDistance > tolerance {
                keep[index] = true
                stack.append((first, index))
                stack.append((index, last))
            }
        }

        return points.enumerated().filter { keep[$0.offset] }.map { $0.element }
    }

    private static func perpendicularDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / length
    }

    static func color(hex: String) -> UIColor? {
        return PaperColor(hex: hex)?.uiColor
    }
}
