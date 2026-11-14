//! 领域类型：媒体种类、片源种类、稳定 ID 与片库条目。
//!
//! 这些类型是 core / library / sources / app 之间唯一的共同语言，改动会影响三个
//! crate；新增字段先加在这里，再由持有者按需使用。

use std::fmt;
use std::path::PathBuf;

/// 媒体种类。字符串会进数据库，必须稳定。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum MediaKind {
    Movie,
    Episode,
    Audio,
    Course,
    Other,
}

impl MediaKind {
    pub fn as_str(self) -> &'static str {
        match self {
            MediaKind::Movie => "movie",
            MediaKind::Episode => "episode",
            MediaKind::Audio => "audio",
            MediaKind::Course => "course",
            MediaKind::Other => "other",
        }
    }

    /// 只认自己写出的字符串；未知值返回 None，由调用方决定是报错还是兜底。
    pub fn from_code(value: &str) -> Option<Self> {
        match value {
            "movie" => Some(MediaKind::Movie),
            "episode" => Some(MediaKind::Episode),
            "audio" => Some(MediaKind::Audio),
            "course" => Some(MediaKind::Course),
            "other" => Some(MediaKind::Other),
            _ => None,
        }
    }

    pub fn is_episode(self) -> bool {
        matches!(self, MediaKind::Episode)
    }
}

impl fmt::Display for MediaKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// 片源种类。Local 指本机路径（含已挂载的 NAS 目录）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SourceKind {
    Local,
    Smb,
    WebDav,
    Jellyfin,
    Emby,
    Plex,
    Iptv,
    Bridge,
    OpenList,
}

impl SourceKind {
    pub fn as_str(self) -> &'static str {
        match self {
            SourceKind::Local => "local",
            SourceKind::Smb => "smb",
            SourceKind::WebDav => "webdav",
            SourceKind::Jellyfin => "jellyfin",
            SourceKind::Emby => "emby",
            SourceKind::Plex => "plex",
            SourceKind::Iptv => "iptv",
            SourceKind::Bridge => "bridge",
            SourceKind::OpenList => "openlist",
        }
    }

    pub fn from_code(value: &str) -> Option<Self> {
        match value {
            "local" => Some(SourceKind::Local),
            "smb" => Some(SourceKind::Smb),
            "webdav" => Some(SourceKind::WebDav),
            "jellyfin" => Some(SourceKind::Jellyfin),
            "emby" => Some(SourceKind::Emby),
            "plex" => Some(SourceKind::Plex),
            "iptv" => Some(SourceKind::Iptv),
            "bridge" => Some(SourceKind::Bridge),
            "openlist" => Some(SourceKind::OpenList),
            _ => None,
        }
    }

    /// 网络片源需要凭据与超时；本地片源不需要。M4 起用到。
    pub fn is_network(self) -> bool {
        !matches!(self, SourceKind::Local)
    }
}

impl fmt::Display for SourceKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// 64 位 FNV-1a。选它是因为：零依赖、跨版本稳定、对 1 万个路径足够快。
///
/// std::hash::DefaultHasher 明确不保证跨版本稳定，不能用来做持久 ID。
pub fn fnv1a64(bytes: &[u8]) -> u64 {
    const OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
    const PRIME: u64 = 0x0000_0100_0000_01b3;
    let mut hash = OFFSET;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(PRIME);
    }
    hash
}

/// 片库条目的持久 ID：由「片源 + 相对路径」决定，重扫不会变。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct MediaId(u64);

impl MediaId {
    /// 长度前缀编码：片源 ID 或路径里就算出现分隔符，也不会和另一种切分撞上。
    pub fn from_parts(source_id: &str, relative_path: &str) -> Self {
        let mut buffer = Vec::with_capacity(source_id.len() + relative_path.len() + 16);
        buffer.extend_from_slice(&(source_id.len() as u64).to_le_bytes());
        buffer.extend_from_slice(source_id.as_bytes());
        buffer.extend_from_slice(&(relative_path.len() as u64).to_le_bytes());
        buffer.extend_from_slice(relative_path.as_bytes());
        MediaId(fnv1a64(&buffer))
    }

    pub fn raw(self) -> u64 {
        self.0
    }
}

impl fmt::Display for MediaId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:016x}", self.0)
    }
}

/// 一条片库条目。M2 只填扫描与解析能给出的字段；时长、简介等由后续里程碑补。
#[derive(Debug, Clone, PartialEq)]
pub struct MediaEntry {
    pub id: MediaId,
    pub source_id: String,
    pub relative_path: PathBuf,
    pub kind: MediaKind,
    pub title: String,
    pub show_title: Option<String>,
    pub year: Option<i32>,
    pub season: Option<u32>,
    pub episode: Option<u32>,
    pub quality: String,
    pub added_at_ms: i64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kind_and_source_strings_round_trip() {
        for kind in [
            MediaKind::Movie,
            MediaKind::Episode,
            MediaKind::Audio,
            MediaKind::Course,
            MediaKind::Other,
        ] {
            assert_eq!(MediaKind::from_code(kind.as_str()), Some(kind));
        }
        for source in [
            SourceKind::Local,
            SourceKind::Smb,
            SourceKind::WebDav,
            SourceKind::Jellyfin,
            SourceKind::Emby,
            SourceKind::Plex,
            SourceKind::Iptv,
            SourceKind::Bridge,
            SourceKind::OpenList,
        ] {
            assert_eq!(SourceKind::from_code(source.as_str()), Some(source));
        }
        assert_eq!(MediaKind::from_code("tv"), None);
    }

    #[test]
    fn network_flag_is_false_only_for_local() {
        assert!(!SourceKind::Local.is_network());
        assert!(SourceKind::WebDav.is_network());
    }

    #[test]
    fn stable_id_depends_on_source_and_path_only() {
        let a = MediaId::from_parts("local", "Movies/Dune.mkv");
        let b = MediaId::from_parts("local", "Movies/Dune.mkv");
        let c = MediaId::from_parts("local", "Movies/Other.mkv");
        let d = MediaId::from_parts("smb", "Movies/Dune.mkv");
        assert_eq!(a, b);
        assert_ne!(a, c);
        assert_ne!(a, d);
        // 分隔符参与哈希：source 与 path 拼接歧义不会撞。
        assert_ne!(
            MediaId::from_parts("a:b", "c"),
            MediaId::from_parts("a", "b:c")
        );
    }

    #[test]
    fn fnv1a_matches_known_vector() {
        // FNV-1a 64 的经典测试向量。
        assert_eq!(fnv1a64(b""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(fnv1a64(b"a"), 0xaf63_dc4c_8601_ec8c);
        assert_eq!(fnv1a64(b"foobar"), 0x8594_4171_f739_67e8);
    }
}
