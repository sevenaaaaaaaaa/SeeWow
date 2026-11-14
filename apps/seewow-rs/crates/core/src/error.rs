//! 统一错误类型：所有 crate 的错误都收敛到这里，调用方只匹配一次。
//!
//! 原则：能恢复的用数据描述（NotFound / Unsupported），不能恢复的把底层错误带上
//! （Io / Db），配置与解析错误给用户可读的中文，不吞掉原始信息。

use std::fmt;
use std::io;

/// 库内通用错误。
#[derive(Debug)]
pub enum Error {
    /// 文件系统或网络 IO 失败。
    Io(io::Error),
    /// 文件名、列表或输入格式不合法；消息面向用户。
    Parse(String),
    /// 配置缺失或损坏；消息面向用户。
    Config(String),
    /// 数据库失败；消息保留底层细节，便于日志排查。
    Db(String),
    /// 期望存在的条目不存在。
    NotFound(String),
    /// 当前平台或版本不支持的能力。
    Unsupported(String),
    /// 不该发生的情况，通常意味着代码缺陷。
    Internal(String),
}

/// 库内通用结果。
pub type Result<T> = std::result::Result<T, Error>;

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io(e) => write!(f, "读写失败：{e}"),
            Error::Parse(msg) => write!(f, "格式无法解析：{msg}"),
            Error::Config(msg) => write!(f, "配置有误：{msg}"),
            Error::Db(msg) => write!(f, "片库数据库出错：{msg}"),
            Error::NotFound(msg) => write!(f, "找不到：{msg}"),
            Error::Unsupported(msg) => write!(f, "暂不支持：{msg}"),
            Error::Internal(msg) => write!(f, "内部错误：{msg}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Error::Io(e) => Some(e),
            _ => None,
        }
    }
}

impl From<io::Error> for Error {
    fn from(value: io::Error) -> Self {
        Error::Io(value)
    }
}

impl From<serde_json::Error> for Error {
    fn from(value: serde_json::Error) -> Self {
        Error::Config(value.to_string())
    }
}

impl Error {
    /// 便于测试与日志的一行归类，不会泄露用户路径。
    pub fn kind(&self) -> &'static str {
        match self {
            Error::Io(_) => "io",
            Error::Parse(_) => "parse",
            Error::Config(_) => "config",
            Error::Db(_) => "db",
            Error::NotFound(_) => "not_found",
            Error::Unsupported(_) => "unsupported",
            Error::Internal(_) => "internal",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_is_readable_and_kind_is_stable() {
        let parse = Error::Parse("缺少片名".into());
        assert_eq!(parse.kind(), "parse");
        assert!(parse.to_string().contains("缺少片名"));

        let io = Error::from(io::Error::new(io::ErrorKind::NotFound, "gone"));
        assert_eq!(io.kind(), "io");
        assert!(io.to_string().contains("gone"));
    }

    #[test]
    fn serde_errors_become_config_errors() {
        let err: Error = serde_json::from_str::<serde_json::Value>("{")
            .unwrap_err()
            .into();
        assert_eq!(err.kind(), "config");
    }
}
