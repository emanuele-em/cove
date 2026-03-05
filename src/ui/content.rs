use super::query_editor;
use super::table_view;

pub enum ContentView {
    Empty,
    Table(table_view::TableView),
    Query(query_editor::QueryEditor),
}
