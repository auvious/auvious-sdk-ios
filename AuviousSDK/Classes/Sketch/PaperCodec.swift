//
//  PaperCodec.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import Foundation
import UIKit

/*
 Codable mirrors of the sketch wire format used by the web clients (@auvious/sketch, paper.js 0.12).
 Items travel as paper.js `exportJSON` output: ["Path", {...}] or ["Group", {...}].
 Coordinates are in a shared project space that is 720 units wide across the whole shared frame.
 */

/// Rounds to paper.js' 5 decimal precision
@inline(__always) private func paperRound(_ value: Double) -> Double {
    return (value * 100000).rounded() / 100000
}

/// Decodes an integer that may have been written as a floating point number
private func decodeInt64(_ container: KeyedDecodingContainer<SketchItemData.CodingKeys>, _ key: SketchItemData.CodingKeys) throws -> Int64 {
    if let value = try? container.decode(Int64.self, forKey: key) {
        return value
    }
    return Int64(try container.decode(Double.self, forKey: key).rounded())
}

//MARK: - Item identity

/// Identity stored in paper's `item.data`
internal struct SketchItemData: Codable, Equatable {

    /// "path" for free-hand markers, "arrow" for arrows
    var tool: String

    /// Epoch milliseconds, unique per author
    var id: Int64

    /// RTC identity (username) of the author
    var userId: String

    /// RTC endpoint of the author
    var userEndpointId: String

    enum CodingKeys: String, CodingKey {
        case tool, id, userId, userEndpointId
    }

    init(tool: String, id: Int64, userId: String, userEndpointId: String) {
        self.tool = tool
        self.id = id
        self.userId = userId
        self.userEndpointId = userEndpointId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = (try? container.decode(String.self, forKey: .tool)) ?? "path"
        id = try decodeInt64(container, .id)
        userId = (try? container.decode(String.self, forKey: .userId)) ?? ""
        userEndpointId = (try? container.decode(String.self, forKey: .userEndpointId)) ?? ""
    }
}

//MARK: - Primitives

/// A paper.js color: [gray], [gray, a], [r, g, b] or [r, g, b, a] in 0...1. A "#rrggbb(aa)" string is accepted on decode.
internal struct PaperColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let components = try? container.decode([Double].self) {
            switch components.count {
            case 1:
                self.init(red: components[0], green: components[0], blue: components[0])
            case 2:
                self.init(red: components[0], green: components[0], blue: components[0], alpha: components[1])
            case 3:
                self.init(red: components[0], green: components[1], blue: components[2])
            case 4:
                self.init(red: components[0], green: components[1], blue: components[2], alpha: components[3])
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported color component count \(components.count)")
            }
            return
        }

        let string = try container.decode(String.self)
        guard let color = PaperColor(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported color \(string)")
        }
        self = color
    }

    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        //Expand #rgb / #rgba
        if value.count == 3 || value.count == 4 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else {
            return nil
        }
        if value.count == 6 {
            self.init(red: Double((number >> 16) & 0xff) / 255, green: Double((number >> 8) & 0xff) / 255, blue: Double(number & 0xff) / 255)
        } else {
            self.init(red: Double((number >> 24) & 0xff) / 255, green: Double((number >> 16) & 0xff) / 255, blue: Double((number >> 8) & 0xff) / 255, alpha: Double(number & 0xff) / 255)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var components = [paperRound(red), paperRound(green), paperRound(blue)]
        if alpha < 1 {
            components.append(paperRound(alpha))
        }
        try container.encode(components)
    }

    var uiColor: UIColor {
        return UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

/// A paper.js segment: [x, y] or [[x, y], [inX, inY], [outX, outY]] with handles relative to the point.
internal struct PaperSegment: Codable, Equatable {
    var point: CGPoint
    var handleIn: CGPoint = .zero
    var handleOut: CGPoint = .zero

    init(point: CGPoint, handleIn: CGPoint = .zero, handleOut: CGPoint = .zero) {
        self.point = point
        self.handleIn = handleIn
        self.handleOut = handleOut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flat = try? container.decode([Double].self), flat.count >= 2 {
            point = CGPoint(x: flat[0], y: flat[1])
            return
        }

        let nested = try container.decode([[Double]].self)
        guard let p = nested.first, p.count >= 2 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid segment")
        }
        point = CGPoint(x: p[0], y: p[1])
        if nested.count > 1, nested[1].count >= 2 {
            handleIn = CGPoint(x: nested[1][0], y: nested[1][1])
        }
        if nested.count > 2, nested[2].count >= 2 {
            handleOut = CGPoint(x: nested[2][0], y: nested[2][1])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let p = [paperRound(Double(point.x)), paperRound(Double(point.y))]
        if handleIn == .zero && handleOut == .zero {
            try container.encode(p)
        } else {
            try container.encode([p,
                                  [paperRound(Double(handleIn.x)), paperRound(Double(handleIn.y))],
                                  [paperRound(Double(handleOut.x)), paperRound(Double(handleOut.y))]])
        }
    }
}

//MARK: - Items

internal struct PaperPath: Codable, Equatable {
    var applyMatrix: Bool? = true
    var data: SketchItemData?
    var segments: [PaperSegment] = []
    var closed: Bool?
    /// [a, b, c, d, tx, ty], nil means identity
    var matrix: [Double]?
    var strokeColor: PaperColor?
    var strokeWidth: Double?
    var strokeCap: String?
    var strokeJoin: String?
    var shadowColor: PaperColor?
    var shadowBlur: Double?
    var opacity: Double?

    init(data: SketchItemData?, segments: [PaperSegment], strokeColor: PaperColor, strokeWidth: Double, shadowColor: PaperColor? = nil, shadowBlur: Double? = nil) {
        self.data = data
        self.segments = segments
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.strokeCap = "round"
        self.strokeJoin = "round"
        self.shadowColor = shadowColor
        self.shadowBlur = shadowBlur
    }

    enum CodingKeys: String, CodingKey {
        case applyMatrix, data, segments, closed, matrix, strokeColor, strokeWidth, strokeCap, strokeJoin, shadowColor, shadowBlur, opacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applyMatrix = try? container.decode(Bool.self, forKey: .applyMatrix)
        data = try? container.decode(SketchItemData.self, forKey: .data)
        segments = (try? container.decode([PaperSegment].self, forKey: .segments)) ?? []
        closed = try? container.decode(Bool.self, forKey: .closed)
        matrix = try? container.decode([Double].self, forKey: .matrix)
        strokeColor = try? container.decode(PaperColor.self, forKey: .strokeColor)
        strokeWidth = try? container.decode(Double.self, forKey: .strokeWidth)
        strokeCap = try? container.decode(String.self, forKey: .strokeCap)
        strokeJoin = try? container.decode(String.self, forKey: .strokeJoin)
        shadowColor = try? container.decode(PaperColor.self, forKey: .shadowColor)
        shadowBlur = try? container.decode(Double.self, forKey: .shadowBlur)
        opacity = try? container.decode(Double.self, forKey: .opacity)
    }
}

internal struct PaperGroup: Codable, Equatable {
    var applyMatrix: Bool? = true
    var data: SketchItemData?
    var children: [PaperItem] = []
    var matrix: [Double]?
    var opacity: Double?

    init(data: SketchItemData?, children: [PaperItem]) {
        self.data = data
        self.children = children
    }

    enum CodingKeys: String, CodingKey {
        case applyMatrix, data, children, matrix, opacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applyMatrix = try? container.decode(Bool.self, forKey: .applyMatrix)
        data = try? container.decode(SketchItemData.self, forKey: .data)
        children = (try? container.decode([PaperItem].self, forKey: .children)) ?? []
        matrix = try? container.decode([Double].self, forKey: .matrix)
        opacity = try? container.decode(Double.self, forKey: .opacity)
    }
}

/// A paper.js item as exported by `exportJSON`
internal indirect enum PaperItem: Codable, Equatable {
    case path(PaperPath)
    case group(PaperGroup)
    /// Item classes we don't draw (e.g. text); kept so a payload with them still decodes
    case unsupported(String)

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        //A [["dictionary", {...}], item] wrapper only appears with symbols, unwrap it defensively
        guard let className = try? container.decode(String.self) else {
            _ = try container.superDecoder()
            self = try container.decode(PaperItem.self)
            return
        }

        switch className {
        case "Path":
            self = .path(try container.decode(PaperPath.self))
        case "Group":
            self = .group(try container.decode(PaperGroup.self))
        default:
            self = .unsupported(className)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case .path(let path):
            try container.encode("Path")
            try container.encode(path)
        case .group(let group):
            try container.encode("Group")
            try container.encode(group)
        case .unsupported(let className):
            throw EncodingError.invalidValue(className, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode unsupported item"))
        }
    }

    /// The identity of a top level item
    var itemData: SketchItemData? {
        switch self {
        case .path(let path):
            return path.data
        case .group(let group):
            return group.data
        case .unsupported:
            return nil
        }
    }
}

//MARK: - Operations

/// Reference to an erased item. Receivers match on `id` only.
internal struct SketchErasedReference: Codable, Equatable {
    var id: Int64
    var userId: String?
    var userEndpointId: String?

    enum CodingKeys: String, CodingKey {
        case id, userId, userEndpointId
    }

    init(id: Int64, userId: String?, userEndpointId: String?) {
        self.id = id
        self.userId = userId
        self.userEndpointId = userEndpointId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Int64.self, forKey: .id) {
            id = value
        } else {
            id = Int64(try container.decode(Double.self, forKey: .id).rounded())
        }
        userId = try? container.decode(String.self, forKey: .userId)
        userEndpointId = try? container.decode(String.self, forKey: .userEndpointId)
    }
}

internal enum SketchOperationType: String, Codable {
    case markerCreated = "Sketch/MarkerCreated"
    case arrowCreated = "Sketch/ArrowCreated"
    case erased = "Sketch/Erased"
    case cleared = "Sketch/Cleared"
}

/// One entry of a sketch broadcast's `payload.events`: `{ "op": ..., "data": ... }`
internal enum SketchOperation: Codable, Equatable {
    case markerCreated(PaperItem)
    case arrowCreated(PaperItem)
    case erased([SketchErasedReference])
    case cleared

    private enum CodingKeys: String, CodingKey {
        case op, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(SketchOperationType.self, forKey: .op) {
        case .markerCreated:
            self = .markerCreated(try container.decode(PaperItem.self, forKey: .data))
        case .arrowCreated:
            self = .arrowCreated(try container.decode(PaperItem.self, forKey: .data))
        case .erased:
            self = .erased(try container.decode([SketchErasedReference].self, forKey: .data))
        case .cleared:
            self = .cleared
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .markerCreated(let item):
            try container.encode(SketchOperationType.markerCreated, forKey: .op)
            try container.encode(item, forKey: .data)
        case .arrowCreated(let item):
            try container.encode(SketchOperationType.arrowCreated, forKey: .op)
            try container.encode(item, forKey: .data)
        case .erased(let references):
            try container.encode(SketchOperationType.erased, forKey: .op)
            try container.encode(references, forKey: .data)
        case .cleared:
            try container.encode(SketchOperationType.cleared, forKey: .op)
        }
    }

    /// The "created" operation for an item, based on its tool
    static func created(_ item: PaperItem) -> SketchOperation {
        return item.itemData?.tool == "arrow" ? .arrowCreated(item) : .markerCreated(item)
    }
}

internal enum SketchCodec {

    /// Decodes each operation separately so a single unknown operation doesn't drop the whole batch
    static func decodeOperations(from data: [Data]) -> [SketchOperation] {
        let decoder = JSONDecoder()
        return data.compactMap { try? decoder.decode(SketchOperation.self, from: $0) }
    }

    /// Encodes operations into JSON objects that can be embedded in a request body
    static func jsonObjects(for operations: [SketchOperation]) -> [Any] {
        let encoder = JSONEncoder()
        return operations.compactMap { operation in
            guard let data = try? encoder.encode(operation) else { return nil }
            return try? JSONSerialization.jsonObject(with: data, options: [])
        }
    }
}
