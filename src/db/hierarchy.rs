#[derive(Debug, Clone)]
pub struct HierarchyNode {
    pub name: String,
    pub kind: NodeKind,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NodeKind {
    Database,
    Schema,
    TableGroup,
    ViewGroup,
    Table,
    View,
}

impl NodeKind {
    pub fn is_expandable(&self) -> bool {
        matches!(
            self,
            Self::Database | Self::Schema | Self::TableGroup | Self::ViewGroup
        )
    }
}
