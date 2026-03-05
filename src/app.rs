use std::sync::Arc;

use iced::widget::{center, column, container, row, text};
use iced::window;
use iced::{Element, Length, Size, Subscription, Task, Theme};

use crate::db::connection::ConnectionConfig;
use crate::db::error::DbError;
use crate::db::hierarchy::HierarchyNode;
use crate::db::result::{QueryResult, SortDirection};
use crate::db::DatabaseConnection;
use crate::store;
use crate::ui::{
    connection_dialog, connection_rail, content::ContentView, header, query_editor, sidebar,
    table_view, theme, tree,
};

pub struct Morfeo {
    main_window: window::Id,
    dialog_window: Option<window::Id>,
    rail: connection_rail::ConnectionRail,
    header: header::Header,
    sidebar: sidebar::Sidebar,
    content: ContentView,
    connection: Option<Arc<DatabaseConnection>>,
    show_sidebar: bool,
    show_content: bool,
    connection_dialog: connection_dialog::ConnectionDialog,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Message {
    Rail(connection_rail::Message),
    Header(header::Message),
    Sidebar(sidebar::Message),
    TableView(table_view::Message),
    QueryEditor(query_editor::Message),
    ConnectionDialog(connection_dialog::Message),
    Connected(Result<Arc<DatabaseConnection>, DbError>),
    ChildrenLoaded(Vec<String>, Result<Vec<HierarchyNode>, DbError>),
    TableDataLoaded(Vec<String>, Result<QueryResult, DbError>),
    QueryResultLoaded(Result<QueryResult, DbError>),
    WindowOpened,
    WindowCloseRequested(window::Id),
    WindowClosed(window::Id),
    Error(String),
}

impl Morfeo {
    pub fn boot() -> (Self, Task<Message>) {
        let (main_id, open_main) = window::open(window::Settings {
            size: Size::new(1200.0, 800.0),
            ..Default::default()
        });

        let saved = store::load();

        (
            Self {
                main_window: main_id,
                dialog_window: None,
                rail: connection_rail::ConnectionRail::new(saved.connections),
                header: header::Header::new(),
                sidebar: sidebar::Sidebar::new(),
                content: ContentView::Empty,
                connection: None,
                show_sidebar: true,
                show_content: true,
                connection_dialog: connection_dialog::ConnectionDialog::new(),
                error: None,
            },
            open_main.map(|_| Message::WindowOpened),
        )
    }

    pub fn title(&self, id: window::Id) -> String {
        if self.dialog_window == Some(id) {
            String::from("New Connection")
        } else {
            String::from("Morfeo")
        }
    }

    pub fn theme(&self, _id: window::Id) -> Theme {
        Theme::Dark
    }

    pub fn subscription(&self) -> Subscription<Message> {
        iced::event::listen_with(|event, _status, id| match event {
            iced::Event::Window(window::Event::CloseRequested) => {
                Some(Message::WindowCloseRequested(id))
            }
            iced::Event::Window(window::Event::Closed) => Some(Message::WindowClosed(id)),
            _ => None,
        })
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::Rail(msg) => self.handle_rail(msg),
            Message::Header(msg) => self.handle_header(msg),
            Message::Sidebar(msg) => self.handle_sidebar(msg),
            Message::TableView(msg) => self.handle_table_view(msg),
            Message::QueryEditor(msg) => self.handle_query_editor(msg),
            Message::ConnectionDialog(msg) => self.handle_connection_dialog(msg),
            Message::Connected(result) => self.handle_connected(result),
            Message::ChildrenLoaded(path, result) => {
                self.handle_children_loaded(path, result);
                Task::none()
            }
            Message::TableDataLoaded(path, result) => {
                self.handle_table_data_loaded(path, result);
                Task::none()
            }
            Message::QueryResultLoaded(result) => {
                self.handle_query_result_loaded(result);
                Task::none()
            }
            Message::WindowOpened => Task::none(),
            Message::WindowCloseRequested(id) => {
                if id == self.main_window {
                    iced::exit()
                } else {
                    self.dialog_window = None;
                    self.connection_dialog.connecting = false;
                    window::close(id)
                }
            }
            Message::WindowClosed(id) => {
                if self.dialog_window == Some(id) {
                    self.dialog_window = None;
                    self.connection_dialog.connecting = false;
                }
                Task::none()
            }
            Message::Error(err) => {
                self.error = Some(err);
                Task::none()
            }
        }
    }

    pub fn view(&self, id: window::Id) -> Element<'_, Message> {
        if self.dialog_window == Some(id) {
            return self.connection_dialog.view().map(Message::ConnectionDialog);
        }

        let header = self.header.view().map(Message::Header);
        let mut main_col = column![header];

        if let Some(err) = &self.error {
            main_col = main_col.push(
                container(text(err).color(theme::ERROR))
                    .padding([4, 8])
                    .width(Length::Fill)
                    .style(|_theme: &Theme| container::Style {
                        background: Some(theme::BG_SURFACE.into()),
                        ..container::Style::default()
                    }),
            );
        }

        let mut body_row = row![self.rail.view().map(Message::Rail)];

        if self.show_sidebar && self.connection.is_some() {
            body_row = body_row.push(self.sidebar.view().map(Message::Sidebar));
        }

        if self.show_content {
            let content: Element<'_, Message> = match &self.content {
                ContentView::Empty => {
                    center(text("Select a table or open a query").color(theme::TEXT_MUTED)).into()
                }
                ContentView::Table(tv) => tv.view().map(Message::TableView),
                ContentView::Query(qe) => qe.view().map(Message::QueryEditor),
            };
            body_row = body_row.push(
                container(content)
                    .width(Length::Fill)
                    .height(Length::Fill)
                    .style(|_theme: &Theme| container::Style {
                        background: Some(theme::BG_SURFACE.into()),
                        ..container::Style::default()
                    }),
            );
        }

        main_col = main_col.push(body_row.height(Length::Fill));
        main_col.height(Length::Fill).into()
    }

    fn open_dialog(&mut self) -> Task<Message> {
        if self.dialog_window.is_some() {
            return Task::none();
        }
        self.connection_dialog.error = None;
        self.connection_dialog.connecting = false;
        let (id, task) = window::open(window::Settings {
            size: Size::new(480.0, 380.0),
            resizable: false,
            minimizable: false,
            ..Default::default()
        });
        self.dialog_window = Some(id);
        task.map(|_| Message::WindowOpened)
    }

    fn close_dialog(&mut self) -> Task<Message> {
        if let Some(id) = self.dialog_window.take() {
            self.connection_dialog.connecting = false;
            window::close(id)
        } else {
            Task::none()
        }
    }

    fn update_breadcrumb(&mut self) {
        let mut parts = Vec::new();

        if let Some(conn) = self.rail.active_connection() {
            parts.push(conn.name.as_str());
            parts.push(match conn.backend {
                crate::db::BackendType::Postgres => "PostgreSQL",
            });
        }

        if let Some(selected) = &self.sidebar.tree.selected {
            for segment in selected {
                parts.push(segment);
            }
        }

        self.header.set_breadcrumb(&parts);
    }

    fn handle_rail(&mut self, msg: connection_rail::Message) -> Task<Message> {
        match msg {
            connection_rail::Message::AddConnection => self.open_dialog(),
            connection_rail::Message::SelectConnection(idx) => {
                self.rail.active = Some(idx);
                self.update_breadcrumb();

                let Some(saved) = self.rail.connections.get(idx).cloned() else {
                    return Task::none();
                };
                let config = ConnectionConfig {
                    backend: saved.backend,
                    connection_string: saved.connection_url(),
                };
                Task::perform(
                    async move {
                        crate::db::connection::connect(&config)
                            .await
                            .map(Arc::new)
                    },
                    Message::Connected,
                )
            }
        }
    }

    fn handle_header(&mut self, msg: header::Message) -> Task<Message> {
        match msg {
            header::Message::DiscardPressed => {
                if let ContentView::Table(tv) = &mut self.content {
                    tv.discard_edits();
                    self.header.has_pending_edits = false;
                }
                Task::none()
            }
            header::Message::CommitPressed => self.commit_edits(),
            header::Message::RefreshPressed => self.refresh_current(),
            header::Message::ToggleSidebar => {
                self.show_sidebar = !self.show_sidebar;
                Task::none()
            }
            header::Message::ToggleContent => {
                self.show_content = !self.show_content;
                Task::none()
            }
        }
    }

    fn handle_sidebar(&mut self, msg: sidebar::Message) -> Task<Message> {
        match msg {
            sidebar::Message::TabSelected(tab) => {
                self.sidebar.active_tab = tab;
                match tab {
                    sidebar::Tab::Query
                        if !matches!(self.content, ContentView::Query(_)) =>
                    {
                        let db = self.current_database().unwrap_or_default();
                        self.content = ContentView::Query(query_editor::QueryEditor::new(db));
                    }
                    sidebar::Tab::Items
                        if matches!(self.content, ContentView::Query(_)) =>
                    {
                        if let Some(path) = self.sidebar.tree.selected.clone() {
                            return self.load_table_data(path, 0);
                        } else {
                            self.content = ContentView::Empty;
                        }
                    }
                    _ => {}
                }
                Task::none()
            }
            sidebar::Message::Tree(tree_msg) => self.handle_tree(tree_msg),
        }
    }

    fn handle_tree(&mut self, msg: tree::Message) -> Task<Message> {
        match msg {
            tree::Message::Toggle(path) => {
                let tree = &mut self.sidebar.tree;
                if tree.expanded.contains(&path) {
                    tree.expanded.remove(&path);
                } else {
                    tree.expanded.insert(path.clone());
                    if !tree.children.contains_key(&path) {
                        return self.load_children(path);
                    }
                }
                Task::none()
            }
            tree::Message::Select(path) => {
                self.sidebar.tree.selected = Some(path.clone());
                self.update_breadcrumb();
                self.load_table_data(path, 0)
            }
        }
    }

    fn handle_table_view(&mut self, msg: table_view::Message) -> Task<Message> {
        let tv = match &mut self.content {
            ContentView::Table(tv) => tv,
            _ => return Task::none(),
        };

        match msg {
            table_view::Message::PageSizeChanged(size) => {
                tv.page_size = size;
                tv.offset = 0;
                let path = tv.table_path.clone();
                self.load_table_data(path, 0)
            }
            table_view::Message::NextPage => {
                let new_offset = tv.offset + tv.page_size;
                tv.offset = new_offset;
                let path = tv.table_path.clone();
                self.load_table_data(path, new_offset)
            }
            table_view::Message::PrevPage => {
                let new_offset = tv.offset.saturating_sub(tv.page_size);
                tv.offset = new_offset;
                let path = tv.table_path.clone();
                self.load_table_data(path, new_offset)
            }
            table_view::Message::Sort(col_name) => {
                if tv.sort_column.as_deref() == Some(&col_name) {
                    tv.sort_direction = match tv.sort_direction {
                        SortDirection::Asc => SortDirection::Desc,
                        SortDirection::Desc => SortDirection::Asc,
                    };
                } else {
                    tv.sort_column = Some(col_name);
                    tv.sort_direction = SortDirection::Asc;
                }
                let path = tv.table_path.clone();
                let offset = tv.offset;
                self.load_table_data(path, offset)
            }
            table_view::Message::CellClicked(r, c) => {
                let has_pk = tv.columns.iter().any(|c| c.is_primary_key);
                if has_pk {
                    let current = tv.effective_value(r, c).clone().unwrap_or_default();
                    tv.editing_cell = Some(table_view::CellEdit {
                        row: r,
                        col: c,
                        value: current,
                    });
                }
                Task::none()
            }
            table_view::Message::CellEdited(val) => {
                if let Some(edit) = &mut tv.editing_cell {
                    edit.value = val;
                }
                Task::none()
            }
            table_view::Message::CellEditConfirmed => {
                if let Some(edit) = tv.editing_cell.take() {
                    let new_value = if edit.value.is_empty() {
                        None
                    } else {
                        Some(edit.value)
                    };
                    tv.pending_edits.push(table_view::PendingEdit {
                        row: edit.row,
                        col: edit.col,
                        new_value,
                    });
                    self.header.has_pending_edits = true;
                }
                Task::none()
            }
        }
    }

    fn handle_query_editor(&mut self, msg: query_editor::Message) -> Task<Message> {
        let qe = match &mut self.content {
            ContentView::Query(qe) => qe,
            _ => return Task::none(),
        };

        match msg {
            query_editor::Message::EditorAction(action) => {
                qe.content.perform(action);
                Task::none()
            }
            query_editor::Message::Execute => {
                let conn = match &self.connection {
                    Some(c) => Arc::clone(c),
                    None => return Task::none(),
                };
                let query = qe.query_text();
                let database = qe.database.clone();
                qe.executing = true;
                Task::perform(
                    async move { conn.execute_query(&database, &query).await },
                    Message::QueryResultLoaded,
                )
            }
        }
    }

    fn handle_connection_dialog(&mut self, msg: connection_dialog::Message) -> Task<Message> {
        match msg {
            connection_dialog::Message::BackendSelected(b) => {
                self.connection_dialog.backend = b;
                Task::none()
            }
            connection_dialog::Message::HostChanged(s) => {
                self.connection_dialog.host = s;
                Task::none()
            }
            connection_dialog::Message::PortChanged(s) => {
                self.connection_dialog.port = s;
                Task::none()
            }
            connection_dialog::Message::UserChanged(s) => {
                self.connection_dialog.user = s;
                Task::none()
            }
            connection_dialog::Message::PasswordChanged(s) => {
                self.connection_dialog.password = s;
                Task::none()
            }
            connection_dialog::Message::DatabaseChanged(s) => {
                self.connection_dialog.database = s;
                Task::none()
            }
            connection_dialog::Message::NameChanged(s) => {
                self.connection_dialog.name = s;
                Task::none()
            }
            connection_dialog::Message::Connect => {
                self.connection_dialog.connecting = true;
                self.connection_dialog.error = None;
                let config = ConnectionConfig {
                    backend: self.connection_dialog.backend,
                    connection_string: self.connection_dialog.connection_url(),
                };
                Task::perform(
                    async move {
                        crate::db::connection::connect(&config)
                            .await
                            .map(Arc::new)
                    },
                    Message::Connected,
                )
            }
            connection_dialog::Message::Cancel => self.close_dialog(),
        }
    }

    fn handle_connected(
        &mut self,
        result: Result<Arc<DatabaseConnection>, DbError>,
    ) -> Task<Message> {
        let from_dialog = self.dialog_window.is_some();
        self.connection_dialog.connecting = false;

        match result {
            Ok(conn) => {
                self.connection = Some(conn);
                self.error = None;

                let mut tasks = vec![self.load_children(vec![])];

                if from_dialog {
                    let saved_conn = self.connection_dialog.to_saved_connection();
                    self.rail.add(saved_conn);
                    self.update_breadcrumb();

                    let store_data = store::ConnectionStore {
                        connections: self.rail.connections.clone(),
                    };
                    store::save(&store_data);

                    tasks.push(self.close_dialog());
                }

                // Reset sidebar/content for new connection
                self.sidebar = sidebar::Sidebar::new();
                self.content = ContentView::Empty;

                Task::batch(tasks)
            }
            Err(e) => {
                if from_dialog {
                    self.connection_dialog.error = Some(e.to_string());
                } else {
                    self.error = Some(e.to_string());
                }
                Task::none()
            }
        }
    }

    fn handle_children_loaded(
        &mut self,
        path: Vec<String>,
        result: Result<Vec<HierarchyNode>, DbError>,
    ) {
        let tree = &mut self.sidebar.tree;
        tree.loading.remove(&path);
        match result {
            Ok(children) => {
                tree.children.insert(path, children);
            }
            Err(e) => {
                self.error = Some(e.to_string());
            }
        }
    }

    fn handle_table_data_loaded(
        &mut self,
        path: Vec<String>,
        result: Result<QueryResult, DbError>,
    ) {
        match result {
            Ok(data) => {
                match &mut self.content {
                    ContentView::Table(tv) if tv.table_path == path => {
                        tv.update_data(data);
                    }
                    _ => {
                        self.content = ContentView::Table(table_view::TableView::new(path, data));
                    }
                }
                self.error = None;
            }
            Err(e) => {
                self.error = Some(e.to_string());
            }
        }
    }

    fn handle_query_result_loaded(&mut self, result: Result<QueryResult, DbError>) {
        if let ContentView::Query(qe) = &mut self.content {
            match result {
                Ok(data) => qe.set_result(data),
                Err(e) => qe.set_error(e.to_string()),
            }
        }
    }

    fn load_children(&mut self, path: Vec<String>) -> Task<Message> {
        let conn = match &self.connection {
            Some(c) => Arc::clone(c),
            None => return Task::none(),
        };
        self.sidebar.tree.loading.insert(path.clone());
        let p = path.clone();
        Task::perform(
            async move { conn.list_children(&p).await },
            move |result| Message::ChildrenLoaded(path.clone(), result),
        )
    }

    fn load_table_data(&self, path: Vec<String>, offset: u32) -> Task<Message> {
        let conn = match &self.connection {
            Some(c) => Arc::clone(c),
            None => return Task::none(),
        };

        let (sort_col, sort_dir) = if let ContentView::Table(tv) = &self.content {
            (tv.sort_column.clone(), tv.sort_direction)
        } else {
            (None, SortDirection::Asc)
        };

        let limit = if let ContentView::Table(tv) = &self.content {
            tv.page_size
        } else {
            50
        };

        let p = path.clone();
        Task::perform(
            async move {
                let sort = sort_col.as_deref().map(|c| (c, sort_dir));
                conn.fetch_table_data(&p, limit, offset, sort).await
            },
            move |result| Message::TableDataLoaded(path.clone(), result),
        )
    }

    fn commit_edits(&mut self) -> Task<Message> {
        let tv = match &mut self.content {
            ContentView::Table(tv) => tv,
            _ => return Task::none(),
        };

        if tv.pending_edits.is_empty() {
            return Task::none();
        }

        let conn = match &self.connection {
            Some(c) => Arc::clone(c),
            None => return Task::none(),
        };

        let table_path = tv.table_path.clone();
        let columns = tv.columns.clone();
        let rows = tv.rows.clone();
        let edits = tv.pending_edits.clone();

        let pk_cols: Vec<usize> = columns
            .iter()
            .enumerate()
            .filter(|(_, c)| c.is_primary_key)
            .map(|(i, _)| i)
            .collect();

        Task::perform(
            async move {
                for edit in &edits {
                    let pk: Vec<(String, String)> = pk_cols
                        .iter()
                        .map(|&i| {
                            (
                                columns[i].name.clone(),
                                rows[edit.row][i].clone().unwrap_or_default(),
                            )
                        })
                        .collect();

                    conn.update_cell(
                        &table_path,
                        &pk,
                        &columns[edit.col].name,
                        edit.new_value.as_deref(),
                    )
                    .await?;
                }
                Ok::<(), DbError>(())
            },
            |result| match result {
                Ok(()) => Message::Header(header::Message::RefreshPressed),
                Err(e) => Message::Error(e.to_string()),
            },
        )
    }

    fn refresh_current(&mut self) -> Task<Message> {
        if let ContentView::Table(tv) = &self.content {
            let path = tv.table_path.clone();
            let offset = tv.offset;
            self.load_table_data(path, offset)
        } else {
            Task::none()
        }
    }

    fn current_database(&self) -> Option<String> {
        self.sidebar
            .tree
            .selected
            .as_ref()
            .and_then(|p| p.first().cloned())
    }
}
