import Foundation

struct FlatTreeItem: Identifiable {
    let id = UUID()
    let path: [String]
    let label: String
    let icon: String
    let tint: NodeTint
    let depth: Int
    let expandable: Bool
    let expanded: Bool
    let selected: Bool
    let loading: Bool
}

@Observable
final class TreeState {
    var expanded: Set<[String]> = []
    var children: [[String]: [HierarchyNode]] = [:]
    var selected: [String]?
    var loading: Set<[String]> = []
    private(set) var flatItems: [FlatTreeItem] = []

    func reset() {
        expanded.removeAll()
        children.removeAll()
        selected = nil
        loading.removeAll()
        flatItems.removeAll()
    }

    func pathForIndex(_ index: Int) -> [String]? {
        guard index < flatItems.count else { return nil }
        return flatItems[index].path
    }

    func isExpandableAt(_ index: Int) -> Bool {
        guard index < flatItems.count else { return false }
        return flatItems[index].expandable
    }

    func rebuildFlat() {
        var items: [FlatTreeItem] = []
        let rootPath: [String] = []
        if let nodes = children[rootPath] {
            Self.flatten(
                nodes: nodes,
                parentPath: rootPath,
                expanded: expanded,
                children: children,
                selected: selected,
                loading: loading,
                items: &items
            )
        }
        flatItems = items
    }

    private static func flatten(
        nodes: [HierarchyNode],
        parentPath: [String],
        expanded: Set<[String]>,
        children: [[String]: [HierarchyNode]],
        selected: [String]?,
        loading: Set<[String]>,
        items: inout [FlatTreeItem]
    ) {
        for node in nodes {
            var path = parentPath
            path.append(node.name)
            let depth = path.count - 1
            let expandable = node.isExpandable
            let isExpanded = expanded.contains(path)
            let isSelected = selected == path
            let isLoading = loading.contains(path)

            items.append(FlatTreeItem(
                path: path,
                label: node.name,
                icon: node.icon,
                tint: node.tint,
                depth: depth,
                expandable: expandable,
                expanded: isExpanded,
                selected: isSelected,
                loading: isLoading
            ))

            if isExpanded && !isLoading {
                if let childNodes = children[path] {
                    flatten(
                        nodes: childNodes,
                        parentPath: path,
                        expanded: expanded,
                        children: children,
                        selected: selected,
                        loading: loading,
                        items: &items
                    )
                }
            }
        }
    }
}
