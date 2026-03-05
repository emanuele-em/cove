use iced::widget::{button, column, container, text, Space};
use iced::{Border, Element, Length, Padding, Theme};

use crate::store::SavedConnection;
use crate::ui::theme;

#[derive(Debug, Clone)]
pub enum Message {
    AddConnection,
    SelectConnection(usize),
}

pub struct ConnectionRail {
    pub connections: Vec<SavedConnection>,
    pub active: Option<usize>,
}

impl ConnectionRail {
    pub fn new(connections: Vec<SavedConnection>) -> Self {
        Self {
            connections,
            active: None,
        }
    }

    pub fn add(&mut self, conn: SavedConnection) {
        self.connections.push(conn);
        self.active = Some(self.connections.len() - 1);
    }

    pub fn active_connection(&self) -> Option<&SavedConnection> {
        self.active.and_then(|i| self.connections.get(i))
    }

    pub fn view(&self) -> Element<'_, Message> {
        let add_btn = button(
            container(text("+").size(18).color(theme::TEXT_PRIMARY))
                .center_x(36)
                .center_y(36),
        )
        .padding(0)
        .width(36)
        .height(36)
        .on_press(Message::AddConnection)
        .style(|_theme: &Theme, status| {
            let bg = match status {
                button::Status::Hovered => theme::ACCENT_DIM,
                _ => theme::BG_MID,
            };
            button::Style {
                background: Some(bg.into()),
                text_color: theme::TEXT_PRIMARY,
                border: Border {
                    radius: 8.0.into(),
                    ..Border::default()
                },
                ..button::Style::default()
            }
        });

        let mut col = column![add_btn].spacing(8).padding(Padding::new(7.0));

        for (i, conn) in self.connections.iter().enumerate() {
            let is_active = self.active == Some(i);
            let abbrev = abbreviation(&conn.name);

            let label = container(
                text(abbrev)
                    .size(12)
                    .color(if is_active {
                        theme::TEXT_PRIMARY
                    } else {
                        theme::TEXT_SECONDARY
                    }),
            )
            .center_x(36)
            .center_y(36);

            let btn = button(label)
                .padding(0)
                .width(36)
                .height(36)
                .on_press(Message::SelectConnection(i))
                .style(move |_theme: &Theme, status| {
                    let bg = if is_active {
                        theme::ACCENT_DIM
                    } else {
                        match status {
                            button::Status::Hovered => theme::BG_LIGHT,
                            _ => theme::BG_DARK,
                        }
                    };
                    button::Style {
                        background: Some(bg.into()),
                        text_color: theme::TEXT_PRIMARY,
                        border: Border {
                            radius: 8.0.into(),
                            ..Border::default()
                        },
                        ..button::Style::default()
                    }
                });

            col = col.push(btn);
        }

        col = col.push(Space::new().height(Length::Fill));

        container(col)
            .width(50)
            .height(Length::Fill)
            .style(|_theme: &Theme| container::Style {
                background: Some(theme::BG_DARK.into()),
                ..container::Style::default()
            })
            .into()
    }
}

fn abbreviation(name: &str) -> String {
    let chars: Vec<char> = name
        .split_whitespace()
        .filter_map(|w| w.chars().next())
        .take(2)
        .collect();
    if chars.len() >= 2 {
        chars.iter().collect::<String>().to_uppercase()
    } else {
        name.chars().take(2).collect::<String>().to_uppercase()
    }
}
