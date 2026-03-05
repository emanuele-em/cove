use std::collections::HashMap;
use std::sync::Arc;

use sqlx::postgres::{PgPool, PgValueRef};
use sqlx::types::{chrono, uuid, JsonValue};
use sqlx::{Column as _, Decode, Row, ValueRef};

use super::backend::DatabaseBackend;
use super::error::DbError;
use super::hierarchy::{HierarchyNode, NodeKind};
use super::result::{ColumnInfo, QueryResult, SortDirection};

pub struct PostgresBackend {
    default_url: String,
    pools: Arc<std::sync::RwLock<HashMap<String, PgPool>>>,
}

impl PostgresBackend {
    pub async fn connect(url: &str) -> Result<Self, DbError> {
        let pool = PgPool::connect(url)
            .await
            .map_err(|e| DbError::Connection(e.to_string()))?;

        let db_name: String = sqlx::query_scalar("SELECT current_database()")
            .fetch_one(&pool)
            .await
            .map_err(|e| DbError::Query(e.to_string()))?;

        let mut pools = HashMap::new();
        pools.insert(db_name, pool);

        Ok(Self {
            default_url: url.to_string(),
            pools: Arc::new(std::sync::RwLock::new(pools)),
        })
    }

    async fn pool_for_db(&self, database: &str) -> Result<PgPool, DbError> {
        {
            let pools = self.pools.read().expect("pool lock poisoned");
            if let Some(pool) = pools.get(database) {
                return Ok(pool.clone());
            }
        }

        let url = replace_database_in_url(&self.default_url, database);
        let pool = PgPool::connect(&url)
            .await
            .map_err(|e| DbError::Connection(e.to_string()))?;

        let mut pools = self.pools.write().expect("pool lock poisoned");
        pools.insert(database.to_string(), pool.clone());
        Ok(pool)
    }

    fn any_pool(&self) -> Result<PgPool, DbError> {
        let pools = self.pools.read().expect("pool lock poisoned");
        pools
            .values()
            .next()
            .cloned()
            .ok_or(DbError::Connection("no connection available".to_string()))
    }
}

impl DatabaseBackend for PostgresBackend {
    fn name(&self) -> &str {
        "PostgreSQL"
    }

    async fn list_children(&self, path: &[String]) -> Result<Vec<HierarchyNode>, DbError> {
        match path.len() {
            0 => {
                let pool = self.any_pool()?;
                let rows: Vec<String> = sqlx::query_scalar(
                    "SELECT datname FROM pg_database \
                     WHERE datistemplate = false ORDER BY datname",
                )
                .fetch_all(&pool)
                .await
                .map_err(|e| DbError::Query(e.to_string()))?;

                Ok(rows
                    .into_iter()
                    .map(|name| HierarchyNode {
                        name,
                        kind: NodeKind::Database,
                    })
                    .collect())
            }

            1 => {
                let pool = self.pool_for_db(&path[0]).await?;
                let rows: Vec<String> = sqlx::query_scalar(
                    "SELECT schema_name FROM information_schema.schemata \
                     WHERE schema_name NOT IN ('pg_toast', 'pg_catalog', 'information_schema') \
                     ORDER BY schema_name",
                )
                .fetch_all(&pool)
                .await
                .map_err(|e| DbError::Query(e.to_string()))?;

                Ok(rows
                    .into_iter()
                    .map(|name| HierarchyNode {
                        name,
                        kind: NodeKind::Schema,
                    })
                    .collect())
            }

            2 => Ok(vec![
                HierarchyNode {
                    name: "Tables".to_string(),
                    kind: NodeKind::TableGroup,
                },
                HierarchyNode {
                    name: "Views".to_string(),
                    kind: NodeKind::ViewGroup,
                },
            ]),

            3 => {
                let pool = self.pool_for_db(&path[0]).await?;
                let schema = &path[1];

                let (table_type, node_kind) = match path[2].as_str() {
                    "Tables" => ("BASE TABLE", NodeKind::Table),
                    "Views" => ("VIEW", NodeKind::View),
                    other => {
                        return Err(DbError::Other(format!("unknown group: {other}")));
                    }
                };

                let rows: Vec<String> = sqlx::query_scalar(
                    "SELECT table_name FROM information_schema.tables \
                     WHERE table_schema = $1 AND table_type = $2 \
                     ORDER BY table_name",
                )
                .bind(schema)
                .bind(table_type)
                .fetch_all(&pool)
                .await
                .map_err(|e| DbError::Query(e.to_string()))?;

                Ok(rows
                    .into_iter()
                    .map(|name| HierarchyNode {
                        name,
                        kind: node_kind.clone(),
                    })
                    .collect())
            }

            _ => Err(DbError::InvalidPath {
                expected: 4,
                got: path.len(),
            }),
        }
    }

    async fn fetch_table_data(
        &self,
        path: &[String],
        limit: u32,
        offset: u32,
        sort: Option<(&str, SortDirection)>,
    ) -> Result<QueryResult, DbError> {
        if path.len() != 4 {
            return Err(DbError::InvalidPath {
                expected: 4,
                got: path.len(),
            });
        }

        let pool = self.pool_for_db(&path[0]).await?;
        let schema = &path[1];
        let table = &path[3];
        let fqn = format!("\"{schema}\".\"{table}\"");

        let columns = fetch_column_info(&pool, schema, table).await?;

        let order_clause = match sort {
            Some((col, SortDirection::Asc)) => format!(" ORDER BY \"{col}\" ASC"),
            Some((col, SortDirection::Desc)) => format!(" ORDER BY \"{col}\" DESC"),
            None => String::new(),
        };

        let query = format!("SELECT * FROM {fqn}{order_clause} LIMIT {limit} OFFSET {offset}");
        let rows = sqlx::query(&query)
            .fetch_all(&pool)
            .await
            .map_err(|e| DbError::Query(e.to_string()))?;

        let type_names: Vec<&str> = columns.iter().map(|c| c.type_name.as_str()).collect();
        let data = decode_rows(&rows, &type_names);

        let count_query = format!("SELECT COUNT(*) FROM {fqn}");
        let total_count: i64 = sqlx::query_scalar(&count_query)
            .fetch_one(&pool)
            .await
            .map_err(|e| DbError::Query(e.to_string()))?;

        Ok(QueryResult {
            columns,
            rows: data,
            rows_affected: None,
            total_count: Some(total_count as u64),
        })
    }

    async fn execute_query(
        &self,
        database: &str,
        query: &str,
    ) -> Result<QueryResult, DbError> {
        let pool = self.pool_for_db(database).await?;

        let rows = sqlx::query(query)
            .fetch_all(&pool)
            .await
            .map_err(|e| DbError::Query(e.to_string()))?;

        if rows.is_empty() {
            return Ok(QueryResult {
                columns: vec![],
                rows: vec![],
                rows_affected: Some(0),
                total_count: None,
            });
        }

        let columns: Vec<ColumnInfo> = rows[0]
            .columns()
            .iter()
            .map(|c| ColumnInfo {
                name: c.name().to_string(),
                type_name: c.type_info().to_string(),
                is_primary_key: false,
            })
            .collect();

        let type_names: Vec<&str> = columns.iter().map(|c| c.type_name.as_str()).collect();
        let data = decode_rows(&rows, &type_names);

        Ok(QueryResult {
            columns,
            rows: data,
            rows_affected: None,
            total_count: None,
        })
    }

    async fn update_cell(
        &self,
        table_path: &[String],
        primary_key: &[(String, String)],
        column: &str,
        new_value: Option<&str>,
    ) -> Result<(), DbError> {
        if table_path.len() != 4 {
            return Err(DbError::InvalidPath {
                expected: 4,
                got: table_path.len(),
            });
        }

        let pool = self.pool_for_db(&table_path[0]).await?;
        let schema = &table_path[1];
        let table = &table_path[3];
        let fqn = format!("\"{schema}\".\"{table}\"");

        let set_clause = match new_value {
            Some(_) => format!("\"{column}\" = $1"),
            None => format!("\"{column}\" = NULL"),
        };

        let where_parts: Vec<String> = primary_key
            .iter()
            .enumerate()
            .map(|(i, (col, _))| {
                let param_idx = if new_value.is_some() { i + 2 } else { i + 1 };
                format!("\"{col}\" = ${param_idx}")
            })
            .collect();
        let where_clause = where_parts.join(" AND ");

        let sql = format!("UPDATE {fqn} SET {set_clause} WHERE {where_clause}");
        let mut q = sqlx::query(&sql);

        if let Some(val) = new_value {
            q = q.bind(val.to_string());
        }
        for (_, val) in primary_key {
            q = q.bind(val.to_string());
        }

        let result = q
            .execute(&pool)
            .await
            .map_err(|e| DbError::Query(e.to_string()))?;

        if result.rows_affected() == 0 {
            return Err(DbError::Other(
                "no rows updated — row may have been modified".to_string(),
            ));
        }

        Ok(())
    }
}

fn decode_rows(rows: &[sqlx::postgres::PgRow], type_names: &[&str]) -> Vec<Vec<Option<String>>> {
    rows.iter()
        .map(|row| {
            type_names
                .iter()
                .enumerate()
                .map(|(i, type_name)| {
                    let raw = row.try_get_raw(i).ok()?;
                    if raw.is_null() {
                        return None;
                    }
                    Some(decode_value(raw, type_name))
                })
                .collect()
        })
        .collect()
}

fn decode_value(raw: PgValueRef<'_>, type_name: &str) -> String {
    macro_rules! decode_as {
        ($t:ty) => {{
            let result: Result<$t, _> = Decode::<sqlx::Postgres>::decode(raw);
            return result
                .map(|v| v.to_string())
                .unwrap_or_else(|_| String::from("[decode error]"));
        }};
    }

    // Normalize: information_schema returns lowercase ("double precision"),
    // sqlx type_info returns uppercase OID names ("FLOAT8")
    match type_name.to_uppercase().as_str() {
        // Boolean
        "BOOL" | "BOOLEAN" => decode_as!(bool),

        // Integers
        "INT2" | "SMALLINT" | "SMALLSERIAL" | "SERIAL2" => decode_as!(i16),
        "INT4" | "INT" | "INTEGER" | "SERIAL" | "SERIAL4" => decode_as!(i32),
        "INT8" | "BIGINT" | "BIGSERIAL" | "SERIAL8" => decode_as!(i64),

        // Floats
        "FLOAT4" | "REAL" => decode_as!(f32),
        "FLOAT8" | "FLOAT" | "DOUBLE PRECISION" => decode_as!(f64),

        // Arbitrary precision
        "NUMERIC" | "DECIMAL" | "MONEY" => decode_as!(&str),

        // Date/time
        "DATE" => decode_as!(chrono::NaiveDate),
        "TIME" | "TIME WITHOUT TIME ZONE" => decode_as!(chrono::NaiveTime),
        "TIMETZ" | "TIME WITH TIME ZONE" => decode_as!(&str),
        "TIMESTAMP" | "TIMESTAMP WITHOUT TIME ZONE" => decode_as!(chrono::NaiveDateTime),
        "TIMESTAMPTZ" | "TIMESTAMP WITH TIME ZONE" => {
            decode_as!(chrono::DateTime<chrono::Utc>)
        }
        "INTERVAL" => decode_as!(&str),

        // UUID
        "UUID" => decode_as!(uuid::Uuid),

        // JSON
        "JSON" | "JSONB" => decode_as!(JsonValue),

        // Network
        "INET" | "CIDR" | "MACADDR" | "MACADDR8" => decode_as!(&str),

        // Text types, geometric, xml, arrays, and everything else
        _ => decode_as!(&str),
    }
}

async fn fetch_column_info(
    pool: &PgPool,
    schema: &str,
    table: &str,
) -> Result<Vec<ColumnInfo>, DbError> {
    let rows = sqlx::query(
        "SELECT c.column_name, c.data_type, \
         CASE WHEN tc.constraint_type = 'PRIMARY KEY' THEN true ELSE false END as is_pk \
         FROM information_schema.columns c \
         LEFT JOIN information_schema.key_column_usage kcu \
           ON c.table_schema = kcu.table_schema \
           AND c.table_name = kcu.table_name \
           AND c.column_name = kcu.column_name \
         LEFT JOIN information_schema.table_constraints tc \
           ON kcu.constraint_name = tc.constraint_name \
           AND kcu.table_schema = tc.table_schema \
           AND tc.constraint_type = 'PRIMARY KEY' \
         WHERE c.table_schema = $1 AND c.table_name = $2 \
         ORDER BY c.ordinal_position",
    )
    .bind(schema)
    .bind(table)
    .fetch_all(pool)
    .await
    .map_err(|e| DbError::Query(e.to_string()))?;

    Ok(rows
        .iter()
        .map(|row| ColumnInfo {
            name: row.get("column_name"),
            type_name: row.get("data_type"),
            is_primary_key: row.get("is_pk"),
        })
        .collect())
}

fn replace_database_in_url(url: &str, database: &str) -> String {
    if let Some(at_pos) = url.rfind('@') {
        let after_at = &url[at_pos..];
        if let Some(slash_pos) = after_at.find('/') {
            let absolute_slash = at_pos + slash_pos;
            let before_db = &url[..absolute_slash + 1];
            let after_db = url[absolute_slash + 1..]
                .find('?')
                .map(|qp| &url[absolute_slash + 1 + qp..])
                .unwrap_or("");
            return format!("{before_db}{database}{after_db}");
        }
    }
    format!("{url}/{database}")
}
