use iced::widget::{button, container, row, text};
use iced::{Border, Element, Length, Theme};

use crate::ui::theme;

#[derive(Debug, Clone)]
pub enum Message {
    RefreshPressed,
    DiscardPressed,
    CommitPressed,
    ToggleSidebar,
    ToggleContent,
}

pub struct Header {
    pub has_pending_edits: bool,
    pub breadcrumb: String,
}

impl Header {
    pub fn new() -> Self {
        Self {
            has_pending_edits: false,
            breadcrumb: String::new(),
        }
    }

    pub fn set_breadcrumb(&mut self, parts: &[&str]) {
        self.breadcrumb = parts.join(" : ");
    }

    pub fn view(&self) -> Element<'_, Message> {
        let refresh = icon_btn("\u{27F3}", Message::RefreshPressed, true);

        let discard = icon_btn("\u{2715}", Message::DiscardPressed, self.has_pending_edits);
        let commit = icon_btn("\u{2713}", Message::CommitPressed, self.has_pending_edits);

        let left = row![refresh, discard, commit].spacing(4);

        let crumb_text = if self.breadcrumb.is_empty() {
            "Morfeo".to_string()
        } else {
            self.breadcrumb.clone()
        };
        let center = container(text(crumb_text).size(13).color(theme::TEXT_SECONDARY))
            .center_x(Length::Fill);

        let sidebar_toggle = icon_btn("\u{25E7}", Message::ToggleSidebar, true);
        let content_toggle = icon_btn("\u{25E8}", Message::ToggleContent, true);
        let right = row![sidebar_toggle, content_toggle].spacing(4);

        container(
            row![left, center, right]
                .spacing(8)
                .padding([6, 12])
                .align_y(iced::Alignment::Center),
        )
        .width(Length::Fill)
        .style(|_theme: &Theme| container::Style {
            background: Some(theme::BG_LIGHT.into()),
            border: Border {
                color: theme::BORDER,
                width: 0.0,
                ..Border::default()
            },
            ..container::Style::default()
        })
        .into()
    }
}

fn icon_btn(icon: &str, msg: Message, enabled: bool) -> Element<'_, Message> {
    let label = text(icon).size(15).color(if enabled {
        theme::TEXT_PRIMARY
    } else {
        theme::TEXT_MUTED
    });

    let btn = button(container(label).center_x(28).center_y(28))
        .padding(0)
        .width(28)
        .height(28)
        .style(|_theme: &Theme, status| {
            let bg = match status {
                button::Status::Hovered => theme::BG_SURFACE,
                _ => iced::Color::TRANSPARENT,
            };
            button::Style {
                background: Some(bg.into()),
                text_color: theme::TEXT_PRIMARY,
                border: Border {
                    radius: 6.0.into(),
                    ..Border::default()
                },
                ..button::Style::default()
            }
        });

    if enabled {
        btn.on_press(msg).into()
    } else {
        btn.into()
    }
}
