import SwiftUI

struct NodeTint: Sendable, Equatable {
    let r: Double, g: Double, b: Double
    var color: Color { Color(red: r, green: g, blue: b) }
}

struct HierarchyNode: Sendable, Equatable {
    let name: String
    let icon: String
    let tint: NodeTint
    let isExpandable: Bool
}
