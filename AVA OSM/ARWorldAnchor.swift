//
//  ARWorldAnchor.swift
//  AVA OSM
//
//  Created by Matt Maring on 9/28/21.
//

import Foundation
import UIKit
import ARKit
import SceneKit

class ARWWorldAnchor: ARAnchor {
    init(column0: SIMD4<Float> = [1, 0, 0, 0], column1: SIMD4<Float> = [0, 1, 0, 0], column2: SIMD4<Float> = [0, 0, 1, 0], column3: SIMD4<Float> = [0, 0, 0, 1]) {
        let transform = simd_float4x4(columns: (column0, column1, column2, column3))
        let worldAnchor = ARAnchor(name: "Door Handle", transform: transform)
        super.init(anchor: worldAnchor)
    }
    
    required init(anchor: ARAnchor) {
        super.init(anchor: anchor)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        fatalError("Hasn't been implemented yet...")
    }
}
