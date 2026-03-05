use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::db::BackendType;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SavedConnection {
    pub name: String,
    pub backend: BackendType,
    pub host: String,
    pub port: String,
    pub user: String,
    pub password: String,
    pub database: String,
}

impl SavedConnection {
    pub fn connection_url(&self) -> String {
        let mut url = String::from("postgresql://");
        url.push_str(&self.user);
        if !self.password.is_empty() {
            url.push(':');
            url.push_str(&self.password);
        }
        url.push('@');
        url.push_str(&self.host);
        url.push(':');
        url.push_str(&self.port);
        if !self.database.is_empty() {
            url.push('/');
            url.push_str(&self.database);
        }
        url
    }
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct ConnectionStore {
    #[serde(default)]
    pub connections: Vec<SavedConnection>,
}

fn config_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("morfeo").join("connections.toml"))
}

pub fn load() -> ConnectionStore {
    let Some(path) = config_path() else {
        return ConnectionStore::default();
    };
    let Ok(contents) = fs::read_to_string(&path) else {
        return ConnectionStore::default();
    };
    toml::from_str(&contents).unwrap_or_default()
}

pub fn save(store: &ConnectionStore) {
    let Some(path) = config_path() else { return };
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(contents) = toml::to_string_pretty(store) {
        let _ = fs::write(&path, contents);
    }
}
