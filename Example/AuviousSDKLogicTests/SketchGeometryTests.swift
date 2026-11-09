//
//  SketchGeometryTests.swift
//  AuviousSDKLogicTests
//
//  Created by Auvious on 15/10/26.
//

import XCTest
import UIKit

final class SketchGeometryTests: XCTestCase {

    func testArrowHeadMatchesTheWebArrow() {
        //Same drag as the paper.js fixture: [100,100] -> [300,250]
        let head = SketchGeometry.arrowHead(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250))

        XCTAssertEqual(head.count, 3)
        XCTAssertEqual(head[0].x, 276.03581, accuracy: 0.001)
        XCTAssertEqual(head[0].y, 251.31048, accuracy: 0.001)
        XCTAssertEqual(head[1], CGPoint(x: 300, y: 250))
        XCTAssertEqual(head[2].x, 294.54809, accuracy: 0.001)
        XCTAssertEqual(head[2].y, 226.62744, accuracy: 0.001)
    }

    func testProjectSpaceIs720UnitsWide() {
        XCTAssertEqual(SketchGeometry.scale(for: CGSize(width: 390, height: 844)), 390.0 / 720.0, accuracy: 0.00001)
        XCTAssertEqual(SketchGeometry.scale(for: CGSize(width: 720, height: 1)), 1)
    }

    func testOutgoingStrokesAreVisibleOnThePhone() {
        let size = CGSize(width: 390, height: 844)
        let width = SketchGeometry.outgoingStrokeWidth(for: size)
        XCTAssertGreaterThanOrEqual(width, 3, "Never thinner than the web default")
        XCTAssertGreaterThanOrEqual(CGFloat(width) * SketchGeometry.scale(for: size), SketchGeometry.minimumRenderedWidth)
    }

    func testSimplifyKeepsShapeAndEndpoints() {
        let line = (0...20).map { CGPoint(x: CGFloat($0) * 5, y: 0) }
        XCTAssertEqual(SketchGeometry.simplify(line, tolerance: 1), [line.first!, line.last!])

        let corner = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 50), CGPoint(x: 100, y: 100)]
        XCTAssertEqual(SketchGeometry.simplify(corner, tolerance: 1), [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
    }

    func testBezierPathUsesRelativeHandles() {
        let segments = [PaperSegment(point: CGPoint(x: 0, y: 0), handleOut: CGPoint(x: 10, y: 0)),
                        PaperSegment(point: CGPoint(x: 100, y: 0), handleIn: CGPoint(x: -10, y: 0))]
        let path = SketchCanvasView.bezierPath(for: segments, closed: false)
        XCTAssertEqual(path.bounds.minX, 0, accuracy: 0.001)
        XCTAssertEqual(path.bounds.maxX, 100, accuracy: 0.001)
    }

    func testCanvasStoresItemsPerAuthorAndErasesById() {
        let canvas = SketchCanvasView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        func marker(_ id: Int64, _ endpoint: String) -> PaperItem {
            return .path(PaperPath(data: SketchItemData(tool: "path", id: id, userId: "u", userEndpointId: endpoint), segments: [PaperSegment(point: .zero), PaperSegment(point: CGPoint(x: 5, y: 5))], strokeColor: PaperColor(red: 1, green: 0, blue: 0), strokeWidth: 3))
        }

        XCTAssertTrue(canvas.add(marker(1, "agent")))
        XCTAssertFalse(canvas.add(marker(1, "agent")), "Duplicates are ignored")
        XCTAssertTrue(canvas.add(marker(2, "me")))
        XCTAssertTrue(canvas.add(marker(3, "me")))

        XCTAssertEqual(canvas.items(ownedBy: "me").compactMap { $0.itemData?.id }, [2, 3])
        XCTAssertEqual(canvas.lastItemData(ownedBy: "me")?.id, 3)

        canvas.remove(id: 3)
        XCTAssertEqual(canvas.lastItemData(ownedBy: "me")?.id, 2)

        canvas.removeAll { $0.userEndpointId != "me" }
        XCTAssertTrue(canvas.items(ownedBy: "agent").isEmpty)
        XCTAssertFalse(canvas.isEmpty)
    }
}
