use super::error::DbError;
use super::hierarchy::HierarchyNode;
use super::result::{QueryResult, SortDirection};

pub trait DatabaseBackend: Send + Sync {
    fn name(&self) -> &str;

    fn list_children(
        &self,
        path: &[String],
    ) -> impl Future<Output = Result<Vec<HierarchyNode>, DbError>> + Send;

    fn fetch_table_data(
        &self,
        path: &[String],
        limit: u32,
        offset: u32,
        sort: Option<(&str, SortDirection)>,
    ) -> impl Future<Output = Result<QueryResult, DbError>> + Send;

    fn execute_query(
        &self,
        database: &str,
        query: &str,
    ) -> impl Future<Output = Result<QueryResult, DbError>> + Send;

    fn update_cell(
        &self,
        table_path: &[String],
        primary_key: &[(String, String)],
        column: &str,
        new_value: Option<&str>,
    ) -> impl Future<Output = Result<(), DbError>> + Send;
}
