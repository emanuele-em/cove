use std::collections::{HashMap, HashSet};

use iced::widget::{button, column, row, text, Space};
use iced::{Element, Length};

use crate::db::hierarchy::{HierarchyNode, NodeKind};
use crate::ui::theme;

#[derive(Debug, Clone)]
pub enum Message {
    Toggle(Vec<String>),
    Select(Vec<String>),
}

pub struct TreeState {
    pub expanded: HashSet<Vec<String>>,
    pub children: HashMap<Vec<String>, Vec<HierarchyNode>>,
    pub selected: Option<Vec<String>>,
    pub loading: HashSet<Vec<String>>,
}

impl TreeState {
    pub fn new() -> Self {
        Self {
            expanded: HashSet::new(),
            children: HashMap::new(),
            selected: None,
            loading: HashSet::new(),
        }
    }

    pub fn view(&self) -> Element<'_, Message> {
        let root_path: Vec<String> = vec![];
        match self.children.get(&root_path) {
            Some(nodes) => {
                let items: Vec<Element<'_, Message>> = nodes
                    .iter()
                    .map(|node| self.view_node(node, &root_path))
                    .collect();
                column(items).spacing(1).width(Length::Fill).into()
            }
            None => text("Connect to a database")
                .size(12)
                .color(theme::TEXT_MUTED)
                .into(),
        }
    }

    fn view_node<'a>(
        &'a self,
        node: &'a HierarchyNode,
        parent_path: &[String],
    ) -> Element<'a, Message> {
        let mut path = parent_path.to_vec();
        path.push(node.name.clone());

        let depth = path.len();
        let indent = (depth.saturating_sub(1) * 16) as u32;

        let icon = if node.kind.is_expandable() {
            if self.expanded.contains(&path) {
                "▼ "
            } else {
                "▶ "
            }
        } else {
            "  "
        };

        let kind_icon = match node.kind {
            NodeKind::Database => "DB ",
            NodeKind::Schema => "S ",
            NodeKind::TableGroup | NodeKind::ViewGroup => "",
            NodeKind::Table => "T ",
            NodeKind::View => "V ",
        };

        let label = format!("{icon}{kind_icon}{}", node.name);
        let is_selected = self.selected.as_ref() == Some(&path);

        let node_btn = button(text(label).size(12))
            .padding([3, 6])
            .width(Length::Fill)
            .on_press(if node.kind.is_expandable() {
                Message::Toggle(path.clone())
            } else {
                Message::Select(path.clone())
            })
            .style(theme::tree_btn(is_selected));

        let mut items: Vec<Element<'a, Message>> =
            vec![row![Space::new().width(indent), node_btn].into()];

        if self.expanded.contains(&path) {
            if self.loading.contains(&path) {
                items.push(
                    row![
                        Space::new().width(indent + 16u32),
                        text("Loading...").size(11).color(theme::TEXT_MUTED)
                    ]
                    .into(),
                );
            } else if let Some(children) = self.children.get(&path) {
                for child in children {
                    items.push(self.view_node(child, &path));
                }
            }
        }

        column(items).into()
    }
}
