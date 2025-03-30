//
//  Item.swift
//  Chess
//
//  Created by Aren Koş on 31.03.2025.
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
