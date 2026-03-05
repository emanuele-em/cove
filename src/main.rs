mod app;
mod db;
mod store;
mod ui;

fn main() -> iced::Result {
    iced::daemon(app::Morfeo::boot, app::Morfeo::update, app::Morfeo::view)
        .title(app::Morfeo::title)
        .theme(app::Morfeo::theme)
        .subscription(app::Morfeo::subscription)
        .run()
}
