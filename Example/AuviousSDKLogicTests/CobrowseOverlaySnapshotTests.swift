//
//  CobrowseOverlaySnapshotTests.swift
//  AuviousSDKLogicTests
//
//  Created by Auvious on 15/10/26.
//
//  Renders every overlay phase over a fake app screen. Set TEST_RUNNER_AUVIOUS_SNAPSHOT_DIR when running
//  xcodebuild to write the PNGs to that folder for a visual check.
//

import XCTest
import UIKit

final class CobrowseOverlaySnapshotTests: XCTestCase {

    private let size = CGSize(width: 390, height: 844)
    private var window: UIWindow!
    private var overlay: CobrowseOverlayViewController!

    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)

        overlay = CobrowseOverlayViewController()
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = overlay
        window.isHidden = false
        overlay.view.frame = window.bounds
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        overlay = nil
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    func testConnecting() {
        overlay.setPhase(.connecting)
        snapshot("1-connecting")
    }

    func testExplainer() {
        overlay.setPhase(.awaitingConsent)
        overlay.showSheet(CobrowseSheetView.Content(iconSymbol: "iphone",
                                                    title: CobrowseStrings.explainerTitle("Anna"),
                                                    body: nil,
                                                    bullets: [CobrowseStrings.explainerAppOnly("Anna"), CobrowseStrings.explainerPrivate, CobrowseStrings.explainerDraw],
                                                    primaryTitle: CobrowseStrings.startSharing,
                                                    secondaryTitle: CobrowseStrings.notNow,
                                                    footnote: CobrowseStrings.explainerFootnote),
                          onPrimary: {}, onSecondary: {})
        snapshot("2-explainer")
    }

    func testSharingWithAnnotationsAndMaskHints() {
        overlay.setPhase(.sharing(since: Date().addingTimeInterval(-252)))
        addInk()
        overlay.hints.update(regions: maskedFields(), debug: false)
        overlay.laser.show(x: 120, y: 140, areaWidth: 390, areaHeight: 844, color: UIColor(red: 0.2, green: 0.55, blue: 0.97, alpha: 1), index: 2, ttl: 5)
        snapshot("3-sharing")
    }

    func testDrawing() {
        overlay.canvas.inkColor = UIColor(red: 0.97, green: 0.64, blue: 0.2, alpha: 1)
        overlay.setPhase(.drawing(since: Date().addingTimeInterval(-252)))
        addInk()
        snapshot("4-drawing")

        overlay.tool = .arrow
        snapshot("4b-drawing-arrow")
    }

    func testNotSharingWithAgentNotice() {
        overlay.setPhase(.notSharing)
        overlay.showToast(style: .info, title: nil, message: CobrowseStrings.agentStoppedViewing("Anna"))
        snapshot("5-not-sharing")
    }

    func testEndConfirmation() {
        overlay.setPhase(.sharing(since: Date().addingTimeInterval(-478)))
        overlay.showSheet(CobrowseSheetView.Content(iconSymbol: nil, title: CobrowseStrings.endTitle, body: CobrowseStrings.endBody("Anna"), bullets: [], primaryTitle: CobrowseStrings.endSession, secondaryTitle: CobrowseStrings.keepSharing, footnote: nil),
                          onPrimary: {}, onSecondary: {})
        snapshot("6-end-confirm")
    }

    func testSessionEnded() {
        overlay.setPhase(.notSharing)
        overlay.pill.isHidden = true
        overlay.dock.isHidden = true
        overlay.showToast(style: .ended, title: CobrowseStrings.sessionEnded, message: CobrowseStrings.sessionEndedBody("Anna"))
        snapshot("7-ended")
    }

    func testDebugMaskHighlight() {
        overlay.setPhase(.sharing(since: Date()))
        overlay.hints.update(regions: maskedFields() + [MaskRegion(rect: CGRect(x: 0, y: 548, width: 390, height: 296), reason: "keyboard", isKeyboard: true)], debug: true)
        snapshot("8-debug-masks")
    }

    //MARK: Helpers

    private func maskedFields() -> [MaskRegion] {
        return [MaskRegion(rect: CGRect(x: 20, y: 234, width: 350, height: 48), reason: "explicit", isKeyboard: false),
                MaskRegion(rect: CGRect(x: 20, y: 414, width: 350, height: 48), reason: "id: payment.iban", isKeyboard: false)]
    }

    private func addInk() {
        let agentColor = PaperColor(red: 0.2, green: 0.54902, blue: 0.96863)
        let start = CGPoint(x: 554, y: 1119)
        let end = CGPoint(x: 425, y: 1237)
        let shaft = PaperPath(data: nil, segments: [PaperSegment(point: start), PaperSegment(point: end)], strokeColor: agentColor, strokeWidth: 3)
        let head = PaperPath(data: nil, segments: SketchGeometry.arrowHead(from: start, to: end).map { PaperSegment(point: $0) }, strokeColor: agentColor, strokeWidth: 3)
        overlay.canvas.add(.group(PaperGroup(data: SketchItemData(tool: "arrow", id: 1, userId: "agent", userEndpointId: "agent-ep"), children: [.path(shaft), .path(head)])))

        let customerColor = PaperColor(red: 0.96863, green: 0.63529, blue: 0.20392)
        let loop = [CGPoint(x: 70, y: 600), CGPoint(x: 360, y: 560), CGPoint(x: 650, y: 610), CGPoint(x: 600, y: 720), CGPoint(x: 120, y: 715), CGPoint(x: 60, y: 640)]
        overlay.canvas.add(.path(PaperPath(data: SketchItemData(tool: "path", id: 2, userId: "me", userEndpointId: "me-ep"), segments: loop.map { PaperSegment(point: $0) }, strokeColor: customerColor, strokeWidth: 6)))
    }

    private func snapshot(_ name: String) {
        overlay.view.setNeedsLayout()
        overlay.view.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(size: size).image { context in
            drawFakeApp(in: context.cgContext)
            window.layer.render(in: context.cgContext)
        }
        XCTAssertGreaterThan(image.size.width, 0)

        guard let directory = ProcessInfo.processInfo.environment["AUVIOUS_SNAPSHOT_DIR"], let data = image.pngData() else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        XCTAssertNoThrow(try data.write(to: url))
    }

    /// A plain "Send money" form behind the overlay
    private func drawFakeApp(in context: CGContext) {
        UIColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))

        let title = NSAttributedString(string: "Send money", attributes: [.font: UIFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: UIColor.black])
        title.draw(at: CGPoint(x: 20, y: 150))

        let labels = ["From account", "Amount", "Recipient IBAN", "Reference"]
        for (index, label) in labels.enumerated() {
            let y = 210 + CGFloat(index) * 90
            NSAttributedString(string: label, attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: UIColor.darkGray]).draw(at: CGPoint(x: 20, y: y))
            let field = UIBezierPath(roundedRect: CGRect(x: 20, y: y + 24, width: 350, height: 48), cornerRadius: 12)
            UIColor.white.setFill()
            field.fill()
            UIColor.lightGray.setStroke()
            field.stroke()
        }

        let button = UIBezierPath(roundedRect: CGRect(x: 20, y: 676, width: 350, height: 54), cornerRadius: 27)
        UIColor(red: 0.055, green: 0.486, blue: 0.4, alpha: 1).setFill()
        button.fill()
    }
}
