use iced::widget::{button, column, container, row, scrollable, text};
use iced::{Border, Element, Length, Theme};

use super::theme;
use super::tree;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tab {
    Items,
    Query,
}

#[derive(Debug, Clone)]
pub enum Message {
    TabSelected(Tab),
    Tree(tree::Message),
}

pub struct Sidebar {
    pub active_tab: Tab,
    pub tree: tree::TreeState,
}

impl Sidebar {
    pub fn new() -> Self {
        Self {
            active_tab: Tab::Items,
            tree: tree::TreeState::new(),
        }
    }

    pub fn view(&self) -> Element<'_, Message> {
        let tabs = segmented_control(self.active_tab);

        let content: Element<'_, Message> = match self.active_tab {
            Tab::Items => self.tree.view().map(Message::Tree),
            Tab::Query => text("Query tab").color(theme::TEXT_SECONDARY).into(),
        };

        let body = container(
            column![
                container(tabs).padding([10, 10]),
                scrollable(container(content).padding([0, 10])).height(Length::Fill),
            ]
            .spacing(4),
        )
        .width(220)
        .height(Length::Fill)
        .style(|_theme: &Theme| container::Style {
            background: Some(theme::BG_MID.into()),
            border: Border {
                color: theme::BORDER,
                width: 1.0,
                radius: 0.0.into(),
            },
            ..container::Style::default()
        });

        body.into()
    }
}

fn segmented_control(active: Tab) -> Element<'static, Message> {
    let items_btn = seg_button("Items", Tab::Items, active);
    let query_btn = seg_button("Query", Tab::Query, active);

    container(row![items_btn, query_btn].spacing(0))
        .style(|_theme: &Theme| container::Style {
            background: Some(theme::BG_DARK.into()),
            border: Border {
                radius: 6.0.into(),
                ..Border::default()
            },
            ..container::Style::default()
        })
        .into()
}

fn seg_button(label: &'static str, tab: Tab, active: Tab) -> Element<'static, Message> {
    let is_active = tab == active;
    let label_widget = text(label).size(12).color(if is_active {
        theme::TEXT_PRIMARY
    } else {
        theme::TEXT_SECONDARY
    });

    button(container(label_widget).center_x(Length::Fill).center_y(24))
        .padding([4, 16])
        .width(Length::Fill)
        .on_press(Message::TabSelected(tab))
        .style(move |_theme: &Theme, _status| {
            let bg = if is_active {
                theme::BG_LIGHT
            } else {
                iced::Color::TRANSPARENT
            };
            button::Style {
                background: Some(bg.into()),
                text_color: if is_active {
                    theme::TEXT_PRIMARY
                } else {
                    theme::TEXT_SECONDARY
                },
                border: Border {
                    radius: 5.0.into(),
                    ..Border::default()
                },
                ..button::Style::default()
            }
        })
        .into()
}
