//! 路径：数据目录、片库数据库、日志、缓存。
//!
//! 重要原则：**测试不许写用户的真实主目录**。所有解析都走 resolve()，测试传自己的
//! 根目录或临时目录；只有 discover() 在真实运行里读环境变量。

use std::path::{Path, PathBuf};

use crate::error::{Error, Result};

/// 决定默认数据目录位置的操作系统。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    MacOs,
    Linux,
    Windows,
    Other,
}

pub fn current_platform() -> Platform {
    if cfg!(target_os = "macos") {
        Platform::MacOs
    } else if cfg!(target_os = "linux") {
        Platform::Linux
    } else if cfg!(target_os = "windows") {
        Platform::Windows
    } else {
        Platform::Other
    }
}

/// 应用数据目录解析结果。所有子路径都由根目录派生，便于测试与迁移。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Paths {
    root: PathBuf,
}

impl Paths {
    pub fn with_root(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// 纯函数版解析，方便测试三种平台与「没有主目录」的失败路径。
    pub fn resolve(
        env_override: Option<&str>,
        home: Option<&Path>,
        platform: Platform,
    ) -> Result<Self> {
        if let Some(dir) = env_override.map(str::trim).filter(|dir| !dir.is_empty()) {
            return Ok(Self::with_root(dir));
        }
        let home =
            home.ok_or_else(|| Error::Config("无法确定用户主目录，请设置 SEEWOW_DATA_DIR".into()))?;
        let root = match platform {
            Platform::MacOs => home.join("Library/Application Support/SeeWow"),
            Platform::Linux => home.join(".local/share/SeeWow"),
            Platform::Windows => home.join("AppData/Roaming/SeeWow"),
            Platform::Other => home.join(".seewow"),
        };
        Ok(Self::with_root(root))
    }

    /// 真实运行入口：环境变量优先，其次按平台推默认目录。
    pub fn discover() -> Result<Self> {
        let env = std::env::var("SEEWOW_DATA_DIR").ok();
        let home = std::env::var_os("HOME")
            .or_else(|| std::env::var_os("USERPROFILE"))
            .map(PathBuf::from);
        Self::resolve(env.as_deref(), home.as_deref(), current_platform())
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn data_dir(&self) -> PathBuf {
        self.root.join("data")
    }

    pub fn library_db(&self) -> PathBuf {
        self.data_dir().join("library.db")
    }

    pub fn logs_dir(&self) -> PathBuf {
        self.root.join("logs")
    }

    pub fn cache_dir(&self) -> PathBuf {
        self.root.join("cache")
    }

    /// 建好运行需要的目录；重复调用不报错。
    pub fn ensure(&self) -> Result<()> {
        for dir in [self.data_dir(), self.logs_dir(), self.cache_dir()] {
            std::fs::create_dir_all(&dir).map_err(|e| {
                Error::Io(std::io::Error::new(
                    e.kind(),
                    format!("创建 {} 失败：{e}", dir.display()),
                ))
            })?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn home() -> PathBuf {
        PathBuf::from("/Users/example")
    }

    #[test]
    fn macos_uses_application_support() {
        let paths = Paths::resolve(None, Some(&home()), Platform::MacOs).unwrap();
        assert_eq!(
            paths.library_db(),
            PathBuf::from("/Users/example/Library/Application Support/SeeWow/data/library.db")
        );
    }

    #[test]
    fn linux_and_windows_have_their_own_roots() {
        let linux = Paths::resolve(None, Some(&home()), Platform::Linux).unwrap();
        assert_eq!(
            linux.root(),
            Path::new("/Users/example/.local/share/SeeWow")
        );
        let windows =
            Paths::resolve(None, Some(Path::new("C:/Users/example")), Platform::Windows).unwrap();
        assert_eq!(
            windows.root(),
            Path::new("C:/Users/example/AppData/Roaming/SeeWow")
        );
    }

    #[test]
    fn env_override_wins_and_blank_override_is_ignored() {
        let overridden =
            Paths::resolve(Some("/tmp/seewow-test"), Some(&home()), Platform::MacOs).unwrap();
        assert_eq!(overridden.root(), Path::new("/tmp/seewow-test"));

        let blank = Paths::resolve(Some("   "), Some(&home()), Platform::MacOs).unwrap();
        assert_eq!(
            blank.root(),
            Path::new("/Users/example/Library/Application Support/SeeWow")
        );
    }

    #[test]
    fn missing_home_is_a_config_error_not_a_panic() {
        let err = Paths::resolve(None, None, Platform::MacOs).unwrap_err();
        assert_eq!(err.kind(), "config");
    }

    #[test]
    fn ensure_creates_every_directory_once() {
        let root = std::env::temp_dir().join(format!("seewow-paths-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let paths = Paths::with_root(&root);
        paths.ensure().unwrap();
        paths.ensure().unwrap();
        assert!(paths.data_dir().is_dir());
        assert!(paths.logs_dir().is_dir());
        assert!(paths.cache_dir().is_dir());
        let _ = std::fs::remove_dir_all(&root);
    }
}
