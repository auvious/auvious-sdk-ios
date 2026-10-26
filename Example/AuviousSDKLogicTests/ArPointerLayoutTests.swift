//
//  ArPointerLayoutTests.swift
//  AuviousSDKLogicTests
//
//  Created by Auvious on 22/10/26.
//

import XCTest
import UIKit

final class ArPointerLayoutTests: XCTestCase {

    typealias Cell = ConferenceGridLayout.Cell

    //MARK: Grid

    func testFourParticipantsKeepTheTwoByTwoGrid() {
        XCTAssertTrue(ConferenceGridLayout.dimensions(count: 4, isLandscape: false) == (2, 2))
        XCTAssertEqual(ConferenceGridLayout.cells(remoteCount: 3, isLandscape: false), [
            Cell(row: 0, column: 0, rowSpan: 1, columnSpan: 1),
            Cell(row: 0, column: 1, rowSpan: 1, columnSpan: 1),
            Cell(row: 1, column: 0, rowSpan: 1, columnSpan: 1),
            Cell(row: 1, column: 1, rowSpan: 1, columnSpan: 1)
        ])
    }

    func testOurTileSpansTheLastRowWhenTheRemoteCountIsEven() {
        XCTAssertTrue(ConferenceGridLayout.dimensions(count: 5, isLandscape: false) == (3, 2))
        XCTAssertEqual(ConferenceGridLayout.cells(remoteCount: 4, isLandscape: false).last, Cell(row: 2, column: 0, rowSpan: 1, columnSpan: 2))

        XCTAssertTrue(ConferenceGridLayout.dimensions(count: 7, isLandscape: false) == (4, 2))
        XCTAssertEqual(ConferenceGridLayout.cells(remoteCount: 6, isLandscape: false).last, Cell(row: 3, column: 0, rowSpan: 1, columnSpan: 2))
    }

    func testEightParticipantsFillFourRows() {
        let cells = ConferenceGridLayout.cells(remoteCount: 7, isLandscape: false)
        XCTAssertTrue(ConferenceGridLayout.dimensions(count: 8, isLandscape: false) == (4, 2))
        XCTAssertEqual(cells.count, 8)
        XCTAssertEqual(cells.last, Cell(row: 3, column: 1, rowSpan: 1, columnSpan: 1))
        XCTAssertTrue(cells.allSatisfy { $0.rowSpan == 1 && $0.columnSpan == 1 })
    }

    func testLandscapeUsesTwoRowsAndOurTileSpansTheLastColumn() {
        XCTAssertTrue(ConferenceGridLayout.dimensions(count: 5, isLandscape: true) == (2, 3))
        let cells = ConferenceGridLayout.cells(remoteCount: 4, isLandscape: true)
        XCTAssertEqual(cells[1], Cell(row: 1, column: 0, rowSpan: 1, columnSpan: 1))
        XCTAssertEqual(cells.last, Cell(row: 0, column: 2, rowSpan: 2, columnSpan: 1))
    }

    //MARK: Annotation surface

    func testTouchesGoThroughUntilAnnotating() {
        let surface = AnnotationSurfaceView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        XCTAssertNil(surface.hitTest(CGPoint(x: 100, y: 100), with: nil))

        surface.isAnnotating = true
        XCTAssertNotNil(surface.hitTest(CGPoint(x: 100, y: 100), with: nil))
    }

    func testOnlyThePenAndArrowDraw() {
        let surface = AnnotationSurfaceView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        surface.isAnnotating = true

        surface.tool = .laser
        XCTAssertFalse(surface.canvas.isUserInteractionEnabled)

        surface.tool = .pen
        XCTAssertTrue(surface.canvas.isUserInteractionEnabled)

        surface.tool = .arrow
        XCTAssertTrue(surface.canvas.isUserInteractionEnabled)

        surface.isAnnotating = false
        XCTAssertFalse(surface.canvas.isUserInteractionEnabled)
    }

    func testCameraSketchesAreMirroredButPointsAreNot() {
        let surface = AnnotationSurfaceView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        surface.isSketchMirrored = true
        surface.layoutIfNeeded()

        XCTAssertEqual(surface.canvas.transform, CGAffineTransform(scaleX: -1, y: 1))
        XCTAssertEqual(surface.canvas.frame, surface.bounds)
        XCTAssertEqual(surface.laser.transform, .identity)
    }

    //MARK: Dock

    func testTheDockStartsWithAnnotateAndOffersTheLaserWhileDrawing() {
        let dock = CobrowseDockView()
        dock.showsLaser = true

        dock.setMode(.annotate)
        XCTAssertEqual(buttons(in: dock).compactMap { $0.title(for: .normal) }, [CobrowseStrings.annotate])

        dock.setMode(.drawing(tool: .laser, inkColor: .green))
        let labels = buttons(in: dock).compactMap { $0.accessibilityLabel }
        XCTAssertEqual(labels.first, CobrowseStrings.laserPointer)
        XCTAssertTrue(buttons(in: dock).first?.accessibilityTraits.contains(.selected) == true)
    }

    func testCobrowseDrawingHasNoLaser() {
        let dock = CobrowseDockView()
        dock.setMode(.drawing(tool: .pen, inkColor: .green))
        XCTAssertFalse(buttons(in: dock).contains { $0.accessibilityLabel == CobrowseStrings.laserPointer })
    }

    private func buttons(in view: UIView) -> [UIButton] {
        return view.subviews.flatMap { subview -> [UIButton] in
            if let button = subview as? UIButton {
                return [button]
            }
            return buttons(in: subview)
        }
    }
}
