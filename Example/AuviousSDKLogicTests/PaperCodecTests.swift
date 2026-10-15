//
//  PaperCodecTests.swift
//  AuviousSDKLogicTests
//
//  Created by Auvious on 15/10/26.
//
//  Fixtures are paper.js 0.12.18 `exportJSON` output, as produced by the agent web app.
//

import XCTest
import UIKit

final class PaperCodecTests: XCTestCase {

    private func decodeItem(_ json: String) throws -> PaperItem {
        return try JSONDecoder().decode(PaperItem.self, from: Data(json.utf8))
    }

    func testDecodesMarkerWithBezierHandles() throws {
        let json = """
        ["Path",{"applyMatrix":true,"data":{"tool":"path","id":1760524800123,"userId":"agent-user","userEndpointId":"ep-agent"},
         "segments":[[[100,200],[0,0],[32.34705,12.93882]],[[155,270],[-8.13303,-32.53211],[0,0]]],
         "strokeColor":[0.2,0.54902,0.96863],"strokeWidth":3,"strokeCap":"round","strokeJoin":"round",
         "shadowColor":[0.2,0.54902,0.96863],"shadowBlur":1}]
        """

        guard case .path(let path) = try decodeItem(json) else {
            return XCTFail("Expected a path")
        }
        XCTAssertEqual(path.data, SketchItemData(tool: "path", id: 1760524800123, userId: "agent-user", userEndpointId: "ep-agent"))
        XCTAssertEqual(path.segments.count, 2)
        XCTAssertEqual(path.segments[0].point, CGPoint(x: 100, y: 200))
        XCTAssertEqual(path.segments[0].handleOut.x, 32.34705, accuracy: 0.00001)
        XCTAssertEqual(path.segments[1].handleIn.y, -32.53211, accuracy: 0.00001)
        XCTAssertEqual(path.strokeColor?.blue ?? 0, 0.96863, accuracy: 0.00001)
        XCTAssertEqual(path.strokeColor?.alpha, 1)
        XCTAssertEqual(path.strokeWidth, 3)
    }

    func testDecodesDefaultMarkerWithAlphaColor() throws {
        let json = """
        ["Path",{"applyMatrix":true,"data":{"tool":"path","id":1,"userId":"u","userEndpointId":"e"},"segments":[[10,10],[20,20]],
         "strokeColor":[0.83137,1,0.19608,0.4],"strokeWidth":10,"strokeCap":"round","strokeJoin":"round",
         "shadowColor":[0.83137,1,0.19608,0.4],"shadowBlur":1}]
        """

        guard case .path(let path) = try decodeItem(json) else {
            return XCTFail("Expected a path")
        }
        XCTAssertEqual(path.segments.map { $0.point }, [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)])
        XCTAssertEqual(path.strokeColor?.alpha ?? 0, 0.4, accuracy: 0.00001)
    }

    func testDecodesArrowGroupWithStyledChildren() throws {
        let json = """
        ["Group",{"applyMatrix":true,"data":{"tool":"arrow","id":1760524800456,"userId":"agent-user","userEndpointId":"ep-agent"},
         "children":[
          ["Path",{"applyMatrix":true,"segments":[[100,100],[300,250]],"strokeColor":[0.96863,0.35294,0.31765],"strokeWidth":3,"strokeCap":"round","strokeJoin":"round","shadowColor":[0,0,0]}],
          ["Path",{"applyMatrix":true,"segments":[[276.03581,251.31048],[300,250],[294.54809,226.62744]],"strokeColor":[0.96863,0.35294,0.31765],"strokeWidth":3,"strokeCap":"round","strokeJoin":"round","shadowColor":[0,0,0]}]]}]
        """

        let item = try decodeItem(json)
        XCTAssertEqual(item.itemData?.tool, "arrow")
        guard case .group(let group) = item else {
            return XCTFail("Expected a group")
        }
        XCTAssertEqual(group.children.count, 2)
        guard case .path(let head) = group.children[1] else {
            return XCTFail("Expected a path")
        }
        XCTAssertEqual(head.segments.count, 3)
        XCTAssertNil(head.data)
    }

    func testAcceptsHexColorsAndFloatIds() throws {
        let json = """
        ["Path",{"data":{"tool":"path","id":1.760524800123e12,"userId":"u","userEndpointId":"e"},"segments":[[0,0],[1,1]],"strokeColor":"#F75A51"}]
        """

        guard case .path(let path) = try decodeItem(json) else {
            return XCTFail("Expected a path")
        }
        XCTAssertEqual(path.data?.id, 1760524800123)
        XCTAssertEqual(path.strokeColor?.red ?? 0, 247.0 / 255.0, accuracy: 0.0001)
    }

    func testUnwrapsDictionaryWrapper() throws {
        let json = """
        [["dictionary",{}],["Path",{"data":{"tool":"path","id":5,"userId":"u","userEndpointId":"e"},"segments":[[0,0],[1,1]]}]]
        """
        XCTAssertEqual(try decodeItem(json).itemData?.id, 5)
    }

    func testUnknownItemClassesDecodeAsUnsupported() throws {
        XCTAssertEqual(try decodeItem(#"["PointText",{"content":"hi"}]"#), .unsupported("PointText"))
    }

    func testEncodesItemsTheWayPaperImportsThem() throws {
        let data = SketchItemData(tool: "path", id: 42, userId: "customer", userEndpointId: "ep-customer")
        let color = PaperColor(red: 0.968627451, green: 0.635294118, blue: 0.203921569)
        let item = PaperItem.path(PaperPath(data: data, segments: [PaperSegment(point: CGPoint(x: 1.234567, y: 2)), PaperSegment(point: CGPoint(x: 3, y: 4))], strokeColor: color, strokeWidth: 6, shadowColor: color, shadowBlur: 1))

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [Any]
        XCTAssertEqual(object?.first as? String, "Path")

        let props = object?.last as? [String: Any]
        XCTAssertEqual(props?["applyMatrix"] as? Bool, true)
        XCTAssertEqual(props?["strokeCap"] as? String, "round")
        XCTAssertEqual(props?["strokeJoin"] as? String, "round")
        XCTAssertEqual(props?["strokeWidth"] as? Double, 6)
        XCTAssertEqual((props?["strokeColor"] as? [Double])?.count, 3, "Opaque colors are written as rgb")
        XCTAssertEqual((props?["strokeColor"] as? [Double])?[0], 0.96863)
        XCTAssertEqual((props?["segments"] as? [[Double]])?[0], [1.23457, 2], "Plain segments, rounded to 5 decimals")

        let itemData = props?["data"] as? [String: Any]
        XCTAssertEqual(itemData?["tool"] as? String, "path")
        XCTAssertEqual((itemData?["id"] as? NSNumber)?.int64Value, 42)
        XCTAssertEqual(itemData?["userEndpointId"] as? String, "ep-customer")
        XCTAssertNil(props?["matrix"], "Nil optionals are omitted, like paper's defaults")
    }

    func testOperationsRoundTrip() throws {
        let data = SketchItemData(tool: "arrow", id: 7, userId: "u", userEndpointId: "e")
        let shaft = PaperPath(data: nil, segments: [PaperSegment(point: .zero), PaperSegment(point: CGPoint(x: 10, y: 0))], strokeColor: PaperColor(red: 1, green: 0, blue: 0), strokeWidth: 3)
        let operations: [SketchOperation] = [
            .arrowCreated(.group(PaperGroup(data: data, children: [.path(shaft)]))),
            .erased([SketchErasedReference(id: 7, userId: "u", userEndpointId: "e")]),
            .cleared
        ]

        let encoded = try operations.map { try JSONEncoder().encode($0) }
        XCTAssertEqual(SketchCodec.decodeOperations(from: encoded), operations)

        let cleared = try JSONSerialization.jsonObject(with: encoded[2]) as? [String: Any]
        XCTAssertEqual(cleared?["op"] as? String, "Sketch/Cleared")
        XCTAssertNil(cleared?["data"], "Cleared carries no data")
    }

    func testCreatedOperationFollowsTheTool() {
        let marker = PaperItem.path(PaperPath(data: SketchItemData(tool: "path", id: 1, userId: "u", userEndpointId: "e"), segments: [], strokeColor: PaperColor(red: 0, green: 0, blue: 0), strokeWidth: 1))
        let arrow = PaperItem.group(PaperGroup(data: SketchItemData(tool: "arrow", id: 2, userId: "u", userEndpointId: "e"), children: []))
        XCTAssertEqual(SketchOperation.created(marker), .markerCreated(marker))
        XCTAssertEqual(SketchOperation.created(arrow), .arrowCreated(arrow))
    }

    func testSkipsUnknownOperationsInABatch() {
        let unknown = Data(#"{"op":"Sketch/TextCreated","data":{}}"#.utf8)
        let cleared = Data(#"{"op":"Sketch/Cleared"}"#.utf8)
        XCTAssertEqual(SketchCodec.decodeOperations(from: [unknown, cleared]), [.cleared])
    }
}
