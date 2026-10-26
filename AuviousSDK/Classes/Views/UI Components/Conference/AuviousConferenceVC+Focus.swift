//
//  AuviousConferenceVC+Focus.swift
//  AuviousSDK
//
//  Created by Auvious on 22/10/26.
//

import UIKit

//The focus layout (one tile large, the others in a row under it) and the grid for larger calls
extension AuviousConferenceVCNew {

    /// The remote tiles that are drawn; past the cap the participants are heard only
    var renderedRemoteViews: [StreamView] {
        return Array(remoteViews.prefix(maximumRemoteStreamsRendered))
    }

    /// Moves the tiles other than the focused one into the scrolling strip, or back to the call
    func placeTilesInFocusStrip(_ active: Bool, focused: StreamView?) {
        if focusStrip.superview == nil {
            focusStrip.translatesAutoresizingMaskIntoConstraints = false
            focusStrip.showsHorizontalScrollIndicator = false
            focusStrip.showsVerticalScrollIndicator = false
            focusStrip.backgroundColor = .clear
            streamContainerView.addSubview(focusStrip)

            let content = focusStripContent
            content.translatesAutoresizingMaskIntoConstraints = false
            content.backgroundColor = .clear
            content.addLayoutGuide(focusGroupGuide)
            focusStrip.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: focusStrip.contentLayoutGuide.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: focusStrip.contentLayoutGuide.trailingAnchor),
                content.topAnchor.constraint(equalTo: focusStrip.contentLayoutGuide.topAnchor),
                content.bottomAnchor.constraint(equalTo: focusStrip.contentLayoutGuide.bottomAnchor)
            ])
        }
        focusStrip.isHidden = !active

        for (index, tile) in remoteViews.enumerated() {
            tile.isHidden = index >= maximumRemoteStreamsRendered
        }

        for tile in [localView] + remoteViews {
            let parent: UIView = active && tile !== focused ? focusStripContent : streamContainerView
            guard tile.superview !== parent else { continue }
            parent.addSubview(tile)
            //Moving a view drops its constraints to views outside it: redo the mute badge's
            let badgeLimit = tile.audioMutedBadgeBottomLimit
            tile.audioMutedBadgeBottomLimit = badgeLimit
        }
    }

    /// One tile large (the agent's screen share or the AR pointer's target), the others in a row under it (a column on
    /// the left in landscape). The row scrolls when its tiles don't fit. In full screen share the row moves off screen.
    func focusConstraints(focused: StreamView, fullScreen: Bool, isLandscape: Bool, safeArea: UILayoutGuide, safeLeading: NSLayoutXAxisAnchor) -> [NSLayoutConstraint] {
        var constraints: [NSLayoutConstraint] = []
        let others = (renderedRemoteViews + [localView]).filter { $0 !== focused }
        let strip = focusStrip
        let content = strip.contentLayoutGuide
        let frame = strip.frameLayoutGuide
        let stack: UIView = buttonContainerView.buttonStackView ?? buttonContainerView
        let gap = viewPadding
        let inset: CGFloat = 16
        let horizontal = fullScreen || !isLandscape

        if fullScreen {
            constraints.append(focused.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor))
            constraints.append(focused.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor))
            constraints.append(focused.topAnchor.constraint(equalTo: safeArea.topAnchor))
            constraints.append(focused.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor))

            constraints.append(strip.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor))
            constraints.append(strip.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor))
            constraints.append(strip.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: 150))
            constraints.append(strip.heightAnchor.constraint(equalToConstant: viewSize))
        } else if !isLandscape {
            constraints.append(focused.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor))
            constraints.append(focused.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor))
            constraints.append(focused.topAnchor.constraint(equalTo: safeArea.topAnchor))
            constraints.append(focused.bottomAnchor.constraint(equalTo: strip.topAnchor, constant: -15))

            constraints.append(strip.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor))
            constraints.append(strip.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor))
            constraints.append(strip.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -15))
            if others.count <= 1 {
                constraints.append(strip.heightAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.5))
            } else {
                constraints.append(strip.heightAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.5, constant: -gap / 2))
            }
        } else {
            constraints.append(strip.leadingAnchor.constraint(equalTo: safeLeading, constant: gap))
            constraints.append(strip.topAnchor.constraint(equalTo: safeArea.topAnchor))
            constraints.append(strip.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor))
            constraints.append(strip.widthAnchor.constraint(equalToConstant: viewSize))

            constraints.append(focused.leadingAnchor.constraint(equalTo: strip.trailingAnchor, constant: gap))
            constraints.append(focused.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor))
            constraints.append(focused.topAnchor.constraint(equalTo: safeArea.topAnchor))
            constraints.append(focused.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor))
        }

        guard let first = others.first, let last = others.last else { return constraints }

        //The content is at least as long as the strip, longer when the tiles need it, and the tiles sit centered in it
        let fill: NSLayoutConstraint
        if horizontal {
            constraints.append(content.heightAnchor.constraint(equalTo: frame.heightAnchor))
            constraints.append(content.widthAnchor.constraint(greaterThanOrEqualTo: frame.widthAnchor))
            fill = content.widthAnchor.constraint(equalTo: frame.widthAnchor)
            constraints.append(focusGroupGuide.leadingAnchor.constraint(equalTo: first.leadingAnchor))
            constraints.append(focusGroupGuide.trailingAnchor.constraint(equalTo: last.trailingAnchor))
            constraints.append(focusGroupGuide.centerXAnchor.constraint(equalTo: content.centerXAnchor))
            constraints.append(first.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: inset))
            constraints.append(last.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -inset))
        } else {
            constraints.append(content.widthAnchor.constraint(equalTo: frame.widthAnchor))
            constraints.append(content.heightAnchor.constraint(greaterThanOrEqualTo: frame.heightAnchor))
            fill = content.heightAnchor.constraint(equalTo: frame.heightAnchor)
            constraints.append(focusGroupGuide.topAnchor.constraint(equalTo: first.topAnchor))
            constraints.append(focusGroupGuide.bottomAnchor.constraint(equalTo: last.bottomAnchor))
            constraints.append(focusGroupGuide.centerYAnchor.constraint(equalTo: content.centerYAnchor))
            constraints.append(first.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: gap))
            constraints.append(last.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -gap))
        }
        fill.priority = .defaultLow
        constraints.append(fill)

        for (index, tile) in others.enumerated() {
            if horizontal {
                constraints.append(tile.topAnchor.constraint(equalTo: content.topAnchor))
                constraints.append(tile.heightAnchor.constraint(equalTo: frame.heightAnchor))
                if fullScreen || others.count <= 2 {
                    constraints.append(tile.widthAnchor.constraint(equalTo: tile.heightAnchor))
                } else {
                    constraints.append(tile.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 1 / 3, constant: -2 * gap / 3))
                }
                if index > 0 {
                    constraints.append(tile.leadingAnchor.constraint(equalTo: others[index - 1].trailingAnchor, constant: gap))
                }
            } else {
                constraints.append(tile.leadingAnchor.constraint(equalTo: content.leadingAnchor))
                constraints.append(tile.widthAnchor.constraint(equalTo: frame.widthAnchor))
                constraints.append(tile.heightAnchor.constraint(equalTo: tile.widthAnchor))
                if index > 0 {
                    constraints.append(tile.topAnchor.constraint(equalTo: others[index - 1].bottomAnchor, constant: gap))
                }
            }
        }
        return constraints
    }

    /// More than 3 participants: 2 columns (2 rows in landscape), the remote tiles in order and ours last.
    /// With an even remote count our tile spans the last line.
    func gridConstraints(isLandscape: Bool, safeArea: UILayoutGuide) -> [NSLayoutConstraint] {
        var constraints: [NSLayoutConstraint] = []
        let remotes = renderedRemoteViews
        let tiles = remotes + [localView]
        let cells = ConferenceGridLayout.cells(remoteCount: remotes.count, isLandscape: isLandscape)
        let (rows, columns) = ConferenceGridLayout.dimensions(count: tiles.count, isLandscape: isLandscape)
        let gap = viewPadding

        //One guide per row and column, each an equal share of the safe area. The rows end right above the controls.
        let rowGuides = (0..<rows).map { _ in UILayoutGuide() }
        let columnGuides = (0..<columns).map { _ in UILayoutGuide() }
        gridGuides.forEach { streamContainerView.removeLayoutGuide($0) }
        gridGuides = rowGuides + columnGuides
        gridGuides.forEach { streamContainerView.addLayoutGuide($0) }

        for (index, guide) in rowGuides.enumerated() {
            constraints.append(index == 0 ? guide.topAnchor.constraint(equalTo: safeArea.topAnchor) : guide.topAnchor.constraint(equalTo: rowGuides[index - 1].bottomAnchor, constant: gap))
            if index > 0 {
                constraints.append(guide.heightAnchor.constraint(equalTo: rowGuides[0].heightAnchor))
            }
        }
        if let last = rowGuides.last {
            constraints.append(last.bottomAnchor.constraint(equalTo: buttonContainerView.topAnchor, constant: -gap))
        }
        for (index, guide) in columnGuides.enumerated() {
            constraints.append(guide.widthAnchor.constraint(equalTo: safeArea.widthAnchor, multiplier: 1 / CGFloat(columns), constant: -gap * CGFloat(columns - 1) / CGFloat(columns)))
            constraints.append(index == 0 ? guide.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor) : guide.leadingAnchor.constraint(equalTo: columnGuides[index - 1].trailingAnchor, constant: gap))
        }

        for (tile, cell) in zip(tiles, cells) {
            constraints.append(tile.topAnchor.constraint(equalTo: rowGuides[cell.row].topAnchor))
            constraints.append(tile.bottomAnchor.constraint(equalTo: rowGuides[cell.row + cell.rowSpan - 1].bottomAnchor))
            constraints.append(tile.leadingAnchor.constraint(equalTo: columnGuides[cell.column].leadingAnchor))
            constraints.append(tile.trailingAnchor.constraint(equalTo: columnGuides[cell.column + cell.columnSpan - 1].trailingAnchor))
        }
        return constraints
    }
}
