//
//  ConferenceGridLayout.swift
//  AuviousSDK
//
//  Created by Auvious on 22/10/26.
//

import Foundation

/// Cells of the call grid for more than 3 participants (pure, so it can be tested)
internal enum ConferenceGridLayout {

    struct Cell: Equatable {
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
    }

    /// Rows and columns for `count` tiles. Portrait has 2 columns, landscape 2 rows.
    static func dimensions(count: Int, isLandscape: Bool) -> (rows: Int, columns: Int) {
        let lines = Int((Double(count) / 2).rounded(.up))
        return isLandscape ? (2, lines) : (lines, 2)
    }

    /// The remote tiles in order, then ours. When the remote count is even, ours spans the last line.
    static func cells(remoteCount: Int, isLandscape: Bool) -> [Cell] {
        var cells: [Cell] = []
        for index in 0...remoteCount {
            let line = index / 2
            let position = index % 2
            let isLocal = index == remoteCount
            let spans = isLocal && remoteCount % 2 == 0
            if isLandscape {
                cells.append(Cell(row: spans ? 0 : position, column: line, rowSpan: spans ? 2 : 1, columnSpan: 1))
            } else {
                cells.append(Cell(row: line, column: spans ? 0 : position, rowSpan: 1, columnSpan: spans ? 2 : 1))
            }
        }
        return cells
    }
}
