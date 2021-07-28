//
//  TableViewCell.swift
//  AVA OSM
//
//  Created by Matt Maring on 7/13/21.
//

import UIKit

class TableViewCell: UITableViewCell {

    @IBOutlet weak var tagType: UILabel!
    @IBOutlet weak var descriptiveName: UILabel!
    @IBOutlet weak var distance: UILabel!
    @IBOutlet weak var direction: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
