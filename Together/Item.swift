//
//  Item.swift
//  Together
//
//  Created by 廖云丰 on 2026/3/9.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
