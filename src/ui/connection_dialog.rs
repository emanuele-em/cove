use iced::widget::{button, column, container, pick_list, row, text, text_input, Space};
use iced::{Alignment, Element, Length};

use crate::db::BackendType;
use crate::store::SavedConnection;
use crate::ui::theme;

#[derive(Debug, Clone)]
pub enum Message {
    BackendSelected(BackendType),
    NameChanged(String),
    HostChanged(String),
    PortChanged(String),
    UserChanged(String),
    PasswordChanged(String),
    DatabaseChanged(String),
    Connect,
    Cancel,
}

pub struct ConnectionDialog {
    pub backend: BackendType,
    pub name: String,
    pub host: String,
    pub port: String,
    pub user: String,
    pub password: String,
    pub database: String,
    pub connecting: bool,
    pub error: Option<String>,
}

impl ConnectionDialog {
    pub fn new() -> Self {
        Self {
            backend: BackendType::Postgres,
            name: String::from("Local"),
            host: String::from("127.0.0.1"),
            port: String::from("5432"),
            user: String::from("postgres"),
            password: String::new(),
            database: String::new(),
            connecting: false,
            error: None,
        }
    }

    pub fn to_saved_connection(&self) -> SavedConnection {
        SavedConnection {
            name: self.name.clone(),
            backend: self.backend,
            host: self.host.clone(),
            port: self.port.clone(),
            user: self.user.clone(),
            password: self.password.clone(),
            database: self.database.clone(),
        }
    }

    pub fn connection_url(&self) -> String {
        self.to_saved_connection().connection_url()
    }

    pub fn view(&self) -> Element<'_, Message> {
        let name_row = form_row(
            "Name",
            text_input("Connection name", &self.name)
                .on_input(Message::NameChanged)
                .size(12)
                .padding([5, 8])
                .style(theme::native_input)
                .into(),
        );

        let backend_row = form_row(
            "Backend",
            pick_list(
                BackendType::ALL,
                Some(self.backend),
                Message::BackendSelected,
            )
            .text_size(12)
            .padding([5, 8])
            .style(theme::native_pick_list)
            .into(),
        );

        let host_port_row = form_row(
            "Host",
            row![
                text_input("127.0.0.1", &self.host)
                    .on_input(Message::HostChanged)
                    .size(12)
                    .padding([5, 8])
                    .style(theme::native_input)
                    .width(Length::Fill),
                text_input("5432", &self.port)
                    .on_input(Message::PortChanged)
                    .size(12)
                    .padding([5, 8])
                    .style(theme::native_input)
                    .width(80),
            ]
            .spacing(8)
            .into(),
        );

        let user_row = form_row(
            "User",
            text_input("postgres", &self.user)
                .on_input(Message::UserChanged)
                .size(12)
                .padding([5, 8])
                .style(theme::native_input)
                .into(),
        );

        let password_row = form_row(
            "Password",
            text_input("password", &self.password)
                .on_input(Message::PasswordChanged)
                .secure(true)
                .size(12)
                .padding([5, 8])
                .style(theme::native_input)
                .into(),
        );

        let database_row = form_row(
            "Database",
            text_input("database", &self.database)
                .on_input(Message::DatabaseChanged)
                .size(12)
                .padding([5, 8])
                .style(theme::native_input)
                .into(),
        );

        let connect_btn = if self.connecting {
            button(text("Connecting...").size(12))
                .padding([4, 14])
                .style(theme::native_btn)
        } else {
            button(text("Connect").size(12))
                .padding([4, 14])
                .style(theme::native_btn)
                .on_press(Message::Connect)
        };

        let cancel_btn = button(text("Cancel").size(12))
            .padding([4, 14])
            .style(theme::native_btn)
            .on_press(Message::Cancel);

        let buttons = row![Space::new().width(Length::Fill), cancel_btn, connect_btn]
            .spacing(8)
            .padding([4, 0]);

        let mut form = column![
            name_row,
            backend_row,
            host_port_row,
            user_row,
            password_row,
            database_row,
            buttons,
        ]
        .spacing(10)
        .padding(20);

        if let Some(err) = &self.error {
            form = form.push(text(err).color(theme::ERROR).size(11));
        }

        container(form)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }
}

fn form_row<'a>(label: &'a str, input: Element<'a, Message>) -> Element<'a, Message> {
    row![
        container(text(label).size(12).color(theme::TEXT_SECONDARY)).width(70),
        input,
    ]
    .spacing(8)
    .align_y(Alignment::Center)
    .into()
}
