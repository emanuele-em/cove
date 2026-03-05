use iced::widget::{button, column, container, row, scrollable, text, text_editor};
use iced::{Element, Length};

use crate::db::result::QueryResult;

#[derive(Debug, Clone)]
pub enum Message {
    EditorAction(text_editor::Action),
    Execute,
}

pub struct QueryEditor {
    pub content: text_editor::Content,
    pub database: String,
    pub result: Option<QueryResult>,
    pub error: Option<String>,
    pub executing: bool,
}

impl QueryEditor {
    pub fn new(database: String) -> Self {
        Self {
            content: text_editor::Content::new(),
            database,
            result: None,
            error: None,
            executing: false,
        }
    }

    pub fn query_text(&self) -> String {
        self.content.text()
    }

    pub fn set_result(&mut self, result: QueryResult) {
        self.result = Some(result);
        self.error = None;
        self.executing = false;
    }

    pub fn set_error(&mut self, error: String) {
        self.error = Some(error);
        self.result = None;
        self.executing = false;
    }

    pub fn view(&self) -> Element<'_, Message> {
        let editor = text_editor(&self.content)
            .on_action(Message::EditorAction)
            .height(200);

        let execute_btn = if self.executing {
            button(text("Executing..."))
        } else {
            button(text("Execute")).on_press(Message::Execute)
        };

        let toolbar = row![execute_btn].spacing(8).padding([4, 0]);

        let results: Element<'_, Message> = if let Some(err) = &self.error {
            text(err).color([0.8, 0.2, 0.2]).into()
        } else if let Some(result) = &self.result {
            if result.columns.is_empty() {
                let msg = match result.rows_affected {
                    Some(n) => format!("{n} rows affected"),
                    None => "Query executed successfully".to_string(),
                };
                text(msg).into()
            } else {
                let header_cells: Vec<Element<'_, Message>> = result
                    .columns
                    .iter()
                    .map(|col| {
                        container(text(&col.name).size(13))
                            .padding([4, 8])
                            .into()
                    })
                    .collect();
                let header = row(header_cells).spacing(1);

                let data_rows: Vec<Element<'_, Message>> = result
                    .rows
                    .iter()
                    .take(10_000)
                    .map(|data_row| {
                        let cells: Vec<Element<'_, Message>> = data_row
                            .iter()
                            .map(|val| {
                                let display = val.as_deref().unwrap_or("NULL");
                                container(text(display).size(13))
                                    .padding([2, 8])
                                    .width(120)
                                    .into()
                            })
                            .collect();
                        row(cells).spacing(1).into()
                    })
                    .collect();

                let row_count = result.rows.len();
                let truncated = if row_count > 10_000 {
                    text(format!("Showing 10,000 of {row_count} rows")).size(12)
                } else {
                    text(format!("{row_count} rows")).size(12)
                };

                column![
                    scrollable(column![header, column(data_rows).spacing(1)]).height(Length::Fill),
                    truncated,
                ]
                .spacing(4)
                .into()
            }
        } else {
            text("").into()
        };

        column![editor, toolbar, results]
            .spacing(4)
            .padding(8)
            .height(Length::Fill)
            .into()
    }
}
