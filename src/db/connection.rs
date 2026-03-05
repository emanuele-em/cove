use super::error::DbError;
use super::postgres::PostgresBackend;
use super::DatabaseConnection;

#[derive(Debug, Clone)]
pub struct ConnectionConfig {
    pub backend: BackendType,
    pub connection_string: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BackendType {
    Postgres,
}

impl BackendType {
    pub const ALL: &[Self] = &[Self::Postgres];
}

impl std::fmt::Display for BackendType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Postgres => write!(f, "PostgreSQL"),
        }
    }
}

pub async fn connect(config: &ConnectionConfig) -> Result<DatabaseConnection, DbError> {
    match config.backend {
        BackendType::Postgres => {
            let backend = PostgresBackend::connect(&config.connection_string).await?;
            Ok(DatabaseConnection::Postgres(backend))
        }
    }
}
