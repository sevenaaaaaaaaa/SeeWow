//! 断点续播策略（M3 · T-10）。
//!
//! 这里只放**判定**，不放 IO：播放器把 `position_ms` / `duration_ms` 交进来，
//! 拿回「从头放」「续播到某处」「算看完」三种结论；写库由 `seewow-library` 负责。
//!
//! 为什么阈值要单独成模块：Flutter 主线的续播判断散在播放页里，改一个数字要读
//! 整个页面；这里把三处数字（起播门槛、看完比例、落盘间隔）集中，配测试固定。

/// 续播判定用的三个数字。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ResumePolicy {
    /// 小于这个进度不提示续播，直接从头放（片头几秒的误触不该被记住）。
    pub min_resume_ms: i64,
    /// 进度达到时长的这个比例，就标记为「看完」并清空续播点。
    pub watched_ratio: f64,
    /// 距离结尾小于这个值时也算看完，避免演职员表没看完就永远挂着「未看完」。
    pub watched_tail_ms: i64,
    /// 播放中每前进这么多毫秒落一次盘，避免每帧都写 SQLite。
    pub persist_interval_ms: i64,
    /// 续播时往回退一点：暂停点常常落在半句台词中间（Infuse 与 ddPlayer 都这么做，
    /// 默认 3 秒）。退到负数按 0 算。
    pub rewind_ms: i64,
}

impl Default for ResumePolicy {
    fn default() -> Self {
        Self {
            min_resume_ms: 30_000,
            watched_ratio: 0.95,
            watched_tail_ms: 120_000,
            persist_interval_ms: 10_000,
            rewind_ms: 3_000,
        }
    }
}

/// 打开一个文件时应该怎么起播。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResumePoint {
    /// 从头播。
    FromStart,
    /// 从 `position_ms` 接着播。
    Continue { position_ms: i64 },
    /// 上次已经看完：从头播，但保留「已看完」状态。
    Finished,
}

impl ResumePolicy {
    /// 给出起播点。`duration_ms` 未知（容器没报时长）时只按进度判断。
    pub fn resume_point(&self, position_ms: i64, duration_ms: Option<i64>) -> ResumePoint {
        let position = position_ms.max(0);
        match duration_ms {
            Some(duration) if duration > 0 => {
                if self.is_watched(position, duration) {
                    ResumePoint::Finished
                } else if position >= self.min_resume_ms {
                    ResumePoint::Continue {
                        position_ms: self.with_rewind(position).min(duration),
                    }
                } else {
                    ResumePoint::FromStart
                }
            }
            // 时长未知：只要进度过了门槛就续播，宁可从近了放，也不把人扔回片头。
            _ => {
                if position >= self.min_resume_ms {
                    ResumePoint::Continue {
                        position_ms: self.with_rewind(position),
                    }
                } else {
                    ResumePoint::FromStart
                }
            }
        }
    }

    /// 把位置往回退 `rewind_ms`，但不小于 0。
    fn with_rewind(&self, position_ms: i64) -> i64 {
        (position_ms - self.rewind_ms.max(0)).max(0)
    }

    /// 是否算看完。
    pub fn is_watched(&self, position_ms: i64, duration_ms: i64) -> bool {
        if duration_ms <= 0 {
            return false;
        }
        let position = position_ms.max(0);
        let by_ratio = position as f64 >= duration_ms as f64 * self.watched_ratio;
        let by_tail = duration_ms - position <= self.watched_tail_ms;
        by_ratio || by_tail
    }

    /// 播放中是否该把进度落盘：只有相对上次落盘前进够了才写。
    ///
    /// 往回拖（`position_ms < last_persisted_ms`）时立刻落盘——用户主动跳转是明确
    /// 意图，不能等下一个 10 秒。
    pub fn should_persist(&self, position_ms: i64, last_persisted_ms: i64) -> bool {
        if position_ms < 0 {
            return false;
        }
        if position_ms < last_persisted_ms {
            return true;
        }
        position_ms - last_persisted_ms >= self.persist_interval_ms
    }

    /// 关窗/切片时该写进库的进度：看完写 0（下次从头），否则写当前位置。
    pub fn position_to_store(&self, position_ms: i64, duration_ms: Option<i64>) -> i64 {
        match duration_ms {
            Some(duration) if self.is_watched(position_ms, duration) => 0,
            _ if position_ms < self.min_resume_ms => 0,
            _ => position_ms.max(0),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MINUTE: i64 = 60_000;

    #[test]
    fn first_seconds_start_from_the_beginning() {
        let policy = ResumePolicy::default();
        assert_eq!(
            policy.resume_point(5_000, Some(45 * MINUTE)),
            ResumePoint::FromStart
        );
        assert_eq!(
            policy.resume_point(29_999, Some(45 * MINUTE)),
            ResumePoint::FromStart
        );
    }

    #[test]
    fn past_the_threshold_continues_where_it_stopped() {
        let policy = ResumePolicy::default();
        assert_eq!(
            policy.resume_point(10 * MINUTE, Some(45 * MINUTE)),
            ResumePoint::Continue {
                // 续播回退 3 秒，接上暂停点前那半句台词。
                position_ms: 10 * MINUTE - 3_000
            }
        );
    }

    #[test]
    fn near_the_end_counts_as_finished() {
        let policy = ResumePolicy::default();
        assert_eq!(
            policy.resume_point(44 * MINUTE, Some(45 * MINUTE)),
            ResumePoint::Finished
        );
        // 剩 3 分钟：既没到 95%，也没进 2 分钟尾巴。
        assert_eq!(
            policy.resume_point(42 * MINUTE, Some(45 * MINUTE)),
            ResumePoint::Continue {
                position_ms: 42 * MINUTE - 3_000
            }
        );
    }

    #[test]
    fn ratio_alone_can_finish_a_long_file() {
        let policy = ResumePolicy::default();
        // 两小时片子，剩 8 分钟（93.3%）没到 95%，也没进 12 分钟的尾巴。
        assert_eq!(
            policy.resume_point(112 * MINUTE, Some(120 * MINUTE)),
            ResumePoint::Continue {
                position_ms: 112 * MINUTE - 3_000
            }
        );
        // 剩余 6 分钟：比例 95% 到线。
        assert_eq!(
            policy.resume_point(114 * MINUTE, Some(120 * MINUTE)),
            ResumePoint::Finished
        );
    }

    #[test]
    fn unknown_duration_still_resumes() {
        let policy = ResumePolicy::default();
        assert_eq!(
            policy.resume_point(5 * MINUTE, None),
            ResumePoint::Continue {
                position_ms: 5 * MINUTE - 3_000
            }
        );
        assert_eq!(policy.resume_point(1_000, None), ResumePoint::FromStart);
    }

    #[test]
    fn rewind_never_goes_below_zero() {
        let policy = ResumePolicy::default();
        // 31 秒续播：31 - 3 = 28 秒。
        assert_eq!(
            policy.resume_point(31_000, Some(45 * MINUTE)),
            ResumePoint::Continue {
                position_ms: 28_000
            }
        );
        let no_rewind = ResumePolicy {
            rewind_ms: 0,
            ..ResumePolicy::default()
        };
        assert_eq!(
            no_rewind.resume_point(31_000, Some(45 * MINUTE)),
            ResumePoint::Continue {
                position_ms: 31_000
            }
        );
    }

    #[test]
    fn position_is_clamped_inside_the_file() {
        let policy = ResumePolicy::default();
        assert_eq!(
            policy.resume_point(50 * MINUTE, Some(45 * MINUTE)),
            ResumePoint::Finished
        );
        assert_eq!(
            policy.resume_point(-5_000, Some(45 * MINUTE)),
            ResumePoint::FromStart
        );
    }

    #[test]
    fn persistence_is_throttled_but_rewinds_write_at_once() {
        let policy = ResumePolicy::default();
        assert!(!policy.should_persist(25_000, 20_000));
        assert!(policy.should_persist(30_000, 20_000));
        // 往回拖立刻落盘。
        assert!(policy.should_persist(5_000, 20_000));
        // 非法进度不写。
        assert!(!policy.should_persist(-1, 0));
    }

    #[test]
    fn stored_position_clears_when_watched_or_barely_started() {
        let policy = ResumePolicy::default();
        assert_eq!(policy.position_to_store(5_000, Some(45 * MINUTE)), 0);
        assert_eq!(policy.position_to_store(44 * MINUTE, Some(45 * MINUTE)), 0);
        assert_eq!(
            policy.position_to_store(10 * MINUTE, Some(45 * MINUTE)),
            10 * MINUTE
        );
    }
}
