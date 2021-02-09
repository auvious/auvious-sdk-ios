//
//  ConferenceInitialHoldView.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 8/2/21.
//

import Foundation

class ConferenceInitialHoldView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        backgroundColor = .blue
    }
}
