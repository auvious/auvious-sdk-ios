//
//  ConferenceCell.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 14/01/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import UIKit


class ConferenceCell: UICollectionViewCell {

    static let identifier = "ConferenceCell"
    
    //UI components
    @IBOutlet weak var streamView: StreamView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

}
