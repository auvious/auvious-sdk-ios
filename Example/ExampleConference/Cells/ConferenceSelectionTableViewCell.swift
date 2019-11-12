//
//  ConferenceSelectionTableViewCell.swift
//  AuviousSDK_Foundation
//
//  Created by Macis on 12/01/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import UIKit

class ConferenceSelectionTableViewCell: UITableViewCell {
    
    @IBOutlet weak var joinBtn: UIButton!
    @IBOutlet weak var confIdLb: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        
        joinBtn.layer.cornerRadius = 5.0
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
}
