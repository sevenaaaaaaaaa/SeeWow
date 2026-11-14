//! 用户配置：片库根目录、隐藏文件策略、偏好语言、主题。
//!
//! 规则：缺失配置等于默认配置（首次启动不该失败）；配置损坏必须报可读错误，不许
//! 静默回到默认值——那会让用户的片库"消失"却没有任何提示。

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    /// 片库根目录。M2 只支持本机路径（含已挂载的 NAS 目录）。
    pub library_roots: Vec<PathBuf>,
    /// 是否收录隐藏目录与隐藏文件。
    pub include_hidden: bool,
    /// 解析与展示的默认语言标签。
    pub preferred_language: String,
    /// 主题名，M6 使用。
    pub theme: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            library_roots: Vec::new(),
            include_hidden: false,
            preferred_language: "zh-CN".to_string(),
            theme: "cinema".to_string(),
        }
    }
}

impl Config {
    pub const FILE_NAME: &'static str = "config.json";

    /// 读配置：文件不存在返回默认值，存在但坏掉返回错误。
    pub fn load(path: &Path) -> Result<Self> {
        match std::fs::read_to_string(path) {
            Ok(text) => {
                let config: Config = serde_json::from_str(&text).map_err(|e| {
                    Error::Config(format!("{} 不是有效的配置：{e}", path.display()))
                })?;
                config.validate()?;
                Ok(config)
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(Error::Io(std::io::Error::new(
                e.kind(),
                format!("读取 {} 失败：{e}", path.display()),
            ))),
        }
    }

    /// 先写临时文件再改名：中途崩溃不会留下半个配置。
    pub fn save(&self, path: &Path) -> Result<()> {
        self.validate()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let tmp = path.with_extension("json.tmp");
        let text = serde_json::to_string_pretty(self)?;
        std::fs::write(&tmp, text)?;
        std::fs::rename(&tmp, path)?;
        Ok(())
    }

    pub fn validate(&self) -> Result<()> {
        if self.preferred_language.trim().is_empty() {
            return Err(Error::Config("preferred_language 不能为空".to_string()));
        }
        let mut seen = HashSet::new();
        for root in &self.library_roots {
            if root.as_os_str().is_empty() {
                return Err(Error::Config("library_roots 里有空路径".to_string()));
            }
            if !seen.insert(root) {
                return Err(Error::Config(format!(
                    "library_roots 重复：{}",
                    root.display()
                )));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("seewow-config-{}-{tag}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn defaults_are_explicit() {
        let config = Config::default();
        assert!(config.library_roots.is_empty());
        assert!(!config.include_hidden);
        assert_eq!(config.preferred_language, "zh-CN");
        config.validate().unwrap();
    }

    #[test]
    fn missing_file_means_defaults() {
        let dir = temp_dir("missing");
        let config = Config::load(&dir.join("config.json")).unwrap();
        assert_eq!(config, Config::default());
    }

    #[test]
    fn round_trip_writes_valid_json_and_leaves_no_temp_file() {
        let dir = temp_dir("roundtrip");
        let path = dir.join("nested").join("config.json");
        let config = Config {
            library_roots: vec![PathBuf::from("/Volumes/Media/Movies")],
            include_hidden: true,
            preferred_language: "ja-JP".to_string(),
            theme: "graphite".to_string(),
        };
        config.save(&path).unwrap();
        assert_eq!(Config::load(&path).unwrap(), config);
        assert!(!path.with_extension("json.tmp").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn broken_json_is_reported_not_ignored() {
        let dir = temp_dir("broken");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("config.json");
        std::fs::write(&path, "{ not json").unwrap();
        let err = Config::load(&path).unwrap_err();
        assert_eq!(err.kind(), "config");
        assert!(err.to_string().contains("config.json"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn duplicate_roots_are_rejected() {
        let config = Config {
            library_roots: vec![PathBuf::from("/media"), PathBuf::from("/media")],
            ..Config::default()
        };
        assert_eq!(config.validate().unwrap_err().kind(), "config");
    }
}
