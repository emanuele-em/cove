#[derive(Debug, thiserror::Error, Clone)]
pub enum DbError {
    #[error("connection failed: {0}")]
    Connection(String),
    #[error("query failed: {0}")]
    Query(String),
    #[error("invalid path: expected {expected} segments, got {got}")]
    InvalidPath { expected: usize, got: usize },
    #[error("{0}")]
    Other(String),
}
