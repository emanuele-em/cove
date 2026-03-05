use iced::widget::{button, container, pick_list, text_input};
use iced::{Border, Color, Theme};

pub const BG_DARK: Color = Color::from_rgb(0.118, 0.118, 0.180);
pub const BG_MID: Color = Color::from_rgb(0.149, 0.153, 0.208);
pub const BG_LIGHT: Color = Color::from_rgb(0.180, 0.184, 0.243);
pub const BG_SURFACE: Color = Color::from_rgb(0.204, 0.208, 0.271);

pub const ACCENT_DIM: Color = Color::from_rgb(0.353, 0.400, 0.702);

pub const TEXT_PRIMARY: Color = Color::from_rgb(0.804, 0.820, 0.898);
pub const TEXT_SECONDARY: Color = Color::from_rgb(0.533, 0.553, 0.659);
pub const TEXT_MUTED: Color = Color::from_rgb(0.373, 0.388, 0.478);

pub const BORDER: Color = Color::from_rgb(0.247, 0.255, 0.329);
pub const ERROR: Color = Color::from_rgb(0.894, 0.318, 0.318);

const INPUT_BG: Color = Color::from_rgb(0.16, 0.16, 0.20);
const INPUT_BORDER: Color = Color::from_rgb(0.30, 0.30, 0.36);
const INPUT_BORDER_FOCUS: Color = Color::from_rgb(0.40, 0.45, 0.75);

pub fn native_btn(_theme: &Theme, status: button::Status) -> button::Style {
    let (bg, border_color) = match status {
        button::Status::Hovered => (
            Color::from_rgb(0.30, 0.31, 0.36),
            Color::from_rgb(0.42, 0.43, 0.48),
        ),
        button::Status::Pressed => (
            Color::from_rgb(0.20, 0.21, 0.26),
            Color::from_rgb(0.35, 0.36, 0.41),
        ),
        _ => (
            Color::from_rgb(0.25, 0.26, 0.31),
            Color::from_rgb(0.38, 0.39, 0.44),
        ),
    };
    button::Style {
        background: Some(bg.into()),
        text_color: TEXT_SECONDARY,
        border: Border {
            color: border_color,
            width: 0.5,
            radius: 5.0.into(),
        },
        ..button::Style::default()
    }
}

pub fn native_input(_theme: &Theme, status: text_input::Status) -> text_input::Style {
    let border_color = match status {
        text_input::Status::Focused { .. } => INPUT_BORDER_FOCUS,
        text_input::Status::Hovered => Color::from_rgb(0.35, 0.35, 0.42),
        _ => INPUT_BORDER,
    };
    text_input::Style {
        background: INPUT_BG.into(),
        border: Border {
            color: border_color,
            width: 0.5,
            radius: 5.0.into(),
        },
        icon: TEXT_MUTED,
        placeholder: TEXT_MUTED,
        value: TEXT_PRIMARY,
        selection: ACCENT_DIM,
    }
}

pub fn native_pick_list(_theme: &Theme, status: pick_list::Status) -> pick_list::Style {
    let border_color = match status {
        pick_list::Status::Hovered => Color::from_rgb(0.35, 0.35, 0.42),
        _ => INPUT_BORDER,
    };
    pick_list::Style {
        text_color: TEXT_PRIMARY,
        placeholder_color: TEXT_MUTED,
        handle_color: TEXT_SECONDARY,
        background: INPUT_BG.into(),
        border: Border {
            color: border_color,
            width: 0.5,
            radius: 5.0.into(),
        },
    }
}

// Tree node: transparent, no border, subtle hover
pub fn tree_btn(selected: bool) -> impl Fn(&Theme, button::Status) -> button::Style {
    move |_theme: &Theme, status: button::Status| {
        let bg = if selected {
            ACCENT_DIM.scale_alpha(0.25)
        } else {
            match status {
                button::Status::Hovered => BG_LIGHT.scale_alpha(0.5),
                _ => Color::TRANSPARENT,
            }
        };
        button::Style {
            background: Some(bg.into()),
            text_color: if selected {
                TEXT_PRIMARY
            } else {
                TEXT_SECONDARY
            },
            border: Border {
                radius: 4.0.into(),
                ..Border::default()
            },
            ..button::Style::default()
        }
    }
}

// Table header cell
pub fn table_header_btn(_theme: &Theme, status: button::Status) -> button::Style {
    let bg = match status {
        button::Status::Hovered => BG_LIGHT,
        _ => BG_MID,
    };
    button::Style {
        background: Some(bg.into()),
        text_color: TEXT_SECONDARY,
        border: Border {
            color: BORDER,
            width: 0.0,
            radius: 0.0.into(),
        },
        ..button::Style::default()
    }
}

// Table data cell — transparent, no chrome
pub fn table_cell_btn(
    edited: bool,
) -> impl Fn(&Theme, button::Status) -> button::Style {
    move |_theme: &Theme, status: button::Status| {
        let bg = match status {
            button::Status::Hovered => BG_LIGHT.scale_alpha(0.3),
            _ => Color::TRANSPARENT,
        };
        button::Style {
            background: Some(bg.into()),
            text_color: if edited {
                Color::from_rgb(0.85, 0.65, 0.15)
            } else {
                TEXT_PRIMARY
            },
            border: Border::default(),
            ..button::Style::default()
        }
    }
}

// Table header row container
pub fn table_header_row(_theme: &Theme) -> container::Style {
    container::Style {
        background: Some(BG_MID.into()),
        border: Border {
            color: BORDER,
            width: 1.0,
            radius: 0.0.into(),
        },
        ..container::Style::default()
    }
}
