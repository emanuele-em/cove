use iced::widget::{button, column, container, row, scrollable, text, text_input};
use iced::{Border, Element, Length, Theme};

use crate::db::result::{ColumnInfo, QueryResult, SortDirection};
use crate::ui::theme;

#[derive(Debug, Clone)]
pub enum Message {
    PageSizeChanged(u32),
    NextPage,
    PrevPage,
    Sort(String),
    CellClicked(usize, usize),
    CellEdited(String),
    CellEditConfirmed,
}

#[derive(Debug, Clone)]
pub struct CellEdit {
    pub row: usize,
    pub col: usize,
    pub value: String,
}

pub struct TableView {
    pub columns: Vec<ColumnInfo>,
    pub rows: Vec<Vec<Option<String>>>,
    pub total_count: Option<u64>,
    pub page_size: u32,
    pub offset: u32,
    pub sort_column: Option<String>,
    pub sort_direction: SortDirection,
    pub table_path: Vec<String>,
    pub editing_cell: Option<CellEdit>,
    pub pending_edits: Vec<PendingEdit>,
}

#[derive(Debug, Clone)]
pub struct PendingEdit {
    pub row: usize,
    pub col: usize,
    pub new_value: Option<String>,
}

impl TableView {
    pub fn new(table_path: Vec<String>, result: QueryResult) -> Self {
        Self {
            total_count: result.total_count,
            columns: result.columns,
            rows: result.rows,
            page_size: 50,
            offset: 0,
            sort_column: None,
            sort_direction: SortDirection::Asc,
            table_path,
            editing_cell: None,
            pending_edits: Vec::new(),
        }
    }

    pub fn update_data(&mut self, result: QueryResult) {
        self.columns = result.columns;
        self.rows = result.rows;
        self.total_count = result.total_count;
        self.editing_cell = None;
    }

    pub fn discard_edits(&mut self) {
        self.pending_edits.clear();
        self.editing_cell = None;
    }

    pub fn effective_value(&self, row: usize, col: usize) -> &Option<String> {
        for edit in self.pending_edits.iter().rev() {
            if edit.row == row && edit.col == col {
                return &edit.new_value;
            }
        }
        &self.rows[row][col]
    }

    fn compute_col_widths(&self) -> Vec<f32> {
        const CHAR_WIDTH: f32 = 7.5;
        const PAD: f32 = 24.0;
        const MIN_W: f32 = 60.0;
        const MAX_W: f32 = 360.0;

        self.columns
            .iter()
            .enumerate()
            .map(|(col_idx, col)| {
                let header_len = col.name.len();
                let max_data_len = self
                    .rows
                    .iter()
                    .map(|row| row[col_idx].as_ref().map_or(4, |v| v.len()))
                    .max()
                    .unwrap_or(0);
                let chars = header_len.max(max_data_len) as f32;
                (chars * CHAR_WIDTH + PAD).clamp(MIN_W, MAX_W)
            })
            .collect()
    }

    pub fn view(&self) -> Element<'_, Message> {
        if self.columns.is_empty() {
            return text("No data").color(theme::TEXT_MUTED).into();
        }

        let col_widths = self.compute_col_widths();

        // Header row
        let header_cells: Vec<Element<'_, Message>> = self
            .columns
            .iter()
            .enumerate()
            .map(|(i, col)| {
                let w = col_widths[i];
                let label = if self.sort_column.as_deref() == Some(&col.name) {
                    let arrow = match self.sort_direction {
                        SortDirection::Asc => " ↑",
                        SortDirection::Desc => " ↓",
                    };
                    format!("{}{arrow}", col.name)
                } else {
                    col.name.clone()
                };
                button(text(label).size(12))
                    .on_press(Message::Sort(col.name.clone()))
                    .padding([6, 8])
                    .width(w)
                    .style(theme::table_header_btn)
                    .into()
            })
            .collect();

        let header = container(row(header_cells).spacing(1))
            .style(theme::table_header_row);

        // Data rows
        let data_rows: Vec<Element<'_, Message>> = (0..self.rows.len())
            .map(|row_idx| {
                let cells: Vec<Element<'_, Message>> = (0..self.columns.len())
                    .map(|col_idx| {
                        let w = col_widths[col_idx];
                        let is_editing = self
                            .editing_cell
                            .as_ref()
                            .is_some_and(|e| e.row == row_idx && e.col == col_idx);

                        let has_edit = self
                            .pending_edits
                            .iter()
                            .any(|e| e.row == row_idx && e.col == col_idx);

                        if is_editing {
                            let edit = self.editing_cell.as_ref().unwrap();
                            text_input("NULL", &edit.value)
                                .on_input(Message::CellEdited)
                                .on_submit(Message::CellEditConfirmed)
                                .size(12)
                                .padding([3, 6])
                                .width(w)
                                .style(theme::native_input)
                                .into()
                        } else {
                            let value = self.effective_value(row_idx, col_idx);
                            let is_null = value.is_none();
                            let display = value.as_deref().unwrap_or("NULL");

                            let cell_text = if has_edit {
                                text(display).size(12)
                            } else if is_null {
                                text(display).size(12).color(theme::TEXT_MUTED)
                            } else {
                                text(display).size(12).color(theme::TEXT_PRIMARY)
                            };

                            button(cell_text)
                                .on_press(Message::CellClicked(row_idx, col_idx))
                                .padding([3, 8])
                                .width(w)
                                .style(theme::table_cell_btn(has_edit))
                                .into()
                        }
                    })
                    .collect();

                let row_bg = if row_idx % 2 == 0 {
                    iced::Color::TRANSPARENT
                } else {
                    theme::BG_MID.scale_alpha(0.3)
                };

                container(row(cells).spacing(1))
                    .style(move |_theme: &Theme| container::Style {
                        background: Some(row_bg.into()),
                        ..container::Style::default()
                    })
                    .into()
            })
            .collect();

        let table = column(data_rows);

        // Pagination
        let current_page = self.offset / self.page_size + 1;
        let total_pages = self
            .total_count
            .map(|c| (c as u32 + self.page_size - 1) / self.page_size)
            .unwrap_or(1);

        let from = self.offset + 1;
        let to = self
            .total_count
            .map(|c| (self.offset + self.page_size).min(c as u32))
            .unwrap_or(self.offset + self.rows.len() as u32);

        let page_info = text(format!(
            "Rows {from}-{to}{}  Page {current_page}/{total_pages}",
            self.total_count
                .map(|c| format!(" of {c}"))
                .unwrap_or_default()
        ))
        .size(12)
        .color(theme::TEXT_SECONDARY);

        let prev_btn = if self.offset > 0 {
            button(text("Prev").size(12))
                .on_press(Message::PrevPage)
                .padding([3, 10])
                .style(theme::native_btn)
        } else {
            button(text("Prev").size(12))
                .padding([3, 10])
                .style(theme::native_btn)
        };

        let next_btn = if current_page < total_pages {
            button(text("Next").size(12))
                .on_press(Message::NextPage)
                .padding([3, 10])
                .style(theme::native_btn)
        } else {
            button(text("Next").size(12))
                .padding([3, 10])
                .style(theme::native_btn)
        };

        let size_btns = row![
            page_size_btn(50, self.page_size),
            page_size_btn(100, self.page_size),
            page_size_btn(500, self.page_size),
        ]
        .spacing(4);

        let footer = container(
            row![prev_btn, page_info, next_btn, size_btns]
                .spacing(8)
                .align_y(iced::Alignment::Center),
        )
        .padding([6, 8])
        .style(|_theme: &Theme| container::Style {
            border: Border {
                color: theme::BORDER,
                width: 1.0,
                radius: 0.0.into(),
            },
            ..container::Style::default()
        });

        column![
            scrollable(
                scrollable(column![header, table])
                    .direction(iced::widget::scrollable::Direction::Horizontal(
                        iced::widget::scrollable::Scrollbar::new()
                    ))
            )
            .height(Length::Fill),
            footer,
        ]
        .into()
    }
}

fn page_size_btn(size: u32, current: u32) -> Element<'static, Message> {
    let btn = button(text(size.to_string()).size(11))
        .padding([2, 8])
        .style(theme::native_btn);
    if size == current {
        btn.into()
    } else {
        btn.on_press(Message::PageSizeChanged(size)).into()
    }
}
