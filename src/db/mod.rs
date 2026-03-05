mod backend;
pub mod connection;
pub mod error;
pub mod hierarchy;
pub mod postgres;
pub mod result;

use backend::DatabaseBackend;
use error::DbError;
use hierarchy::HierarchyNode;
use postgres::PostgresBackend;
use result::{QueryResult, SortDirection};

pub use connection::BackendType;

pub enum DatabaseConnection {
    Postgres(PostgresBackend),
}

impl std::fmt::Debug for DatabaseConnection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "DatabaseConnection({})", self.name())
    }
}

impl DatabaseConnection {
    pub async fn list_children(&self, path: &[String]) -> Result<Vec<HierarchyNode>, DbError> {
        match self {
            Self::Postgres(pg) => pg.list_children(path).await,
        }
    }

    pub async fn fetch_table_data(
        &self,
        path: &[String],
        limit: u32,
        offset: u32,
        sort: Option<(&str, SortDirection)>,
    ) -> Result<QueryResult, DbError> {
        match self {
            Self::Postgres(pg) => pg.fetch_table_data(path, limit, offset, sort).await,
        }
    }

    pub async fn execute_query(
        &self,
        database: &str,
        query: &str,
    ) -> Result<QueryResult, DbError> {
        match self {
            Self::Postgres(pg) => pg.execute_query(database, query).await,
        }
    }

    pub async fn update_cell(
        &self,
        table_path: &[String],
        primary_key: &[(String, String)],
        column: &str,
        new_value: Option<&str>,
    ) -> Result<(), DbError> {
        match self {
            Self::Postgres(pg) => pg.update_cell(table_path, primary_key, column, new_value).await,
        }
    }

    pub fn name(&self) -> &str {
        match self {
            Self::Postgres(pg) => pg.name(),
        }
    }
}
