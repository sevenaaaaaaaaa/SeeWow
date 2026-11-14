//! 播放会话的节拍决策（M3 · T-13 的运行时一半）。
//!
//! `preferences.rs` 存用户选了什么；这里判断**这一拍该做什么**：
//! 预加载下一集、切下一集、到点停、把进度落盘。
//!
//! 为什么单独成模块：这些动作互相打架（定时关闭不该同时又切下一集；暂停时不该预加载），
//! 写在 UI 事件回调里必然出现「先切集再停」这类顺序 bug。这里一次算清、顺序固定，
//! 调用方按返回列表顺序执行即可。

use crate::preferences::{PlayerPreferences, SleepTimer};
use crate::resume::ResumePolicy;

/// 一拍里要执行的动作（按返回顺序执行）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Signal {
    /// 把进度写进库（节流由 `ResumePolicy` 决定）。
    PersistProgress,
    /// 提前打开下一集的首帧（不切界面）。
    PreloadNext,
    /// 切到下一集。
    AdvanceToNext,
    /// 定时关闭到点：暂停并淡出，不做其他动作。
    StopForSleep,
}

/// 播放器这一拍的观测值。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PlaybackTick {
    pub position_ms: i64,
    pub duration_ms: Option<i64>,
    pub paused: bool,
}

/// 会话规则里可调的三个数。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SessionRules {
    /// 剩余不到这么多就预加载下一集。
    pub preload_lead_ms: i64,
    /// 剩余不到这么多就算「这一集放完了」，可以切下一集。
    pub advance_lead_ms: i64,
    /// 续播与落盘策略。
    pub resume: ResumePolicy,
}

impl Default for SessionRules {
    fn default() -> Self {
        Self {
            preload_lead_ms: 10_000,
            advance_lead_ms: 500,
            resume: ResumePolicy::default(),
        }
    }
}

/// 定时关闭的运行时状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct SleepTimerState {
    pub timer: SleepTimer,
    /// 设定定时器的时刻；`SleepTimer::Off` 时无意义。
    pub armed_at_ms: Option<i64>,
}

impl SleepTimerState {
    pub fn off() -> Self {
        Self::default()
    }

    pub fn armed(timer: SleepTimer, now_ms: i64) -> Self {
        Self {
            timer,
            armed_at_ms: Some(now_ms),
        }
    }

    /// 定时器是否已经到点。「播完本集」不按时间，由 `tick` 判断。
    pub fn expired(&self, now_ms: i64) -> bool {
        let Some(minutes) = self.timer.minutes() else {
            return false;
        };
        let Some(armed) = self.armed_at_ms else {
            return false;
        };
        now_ms - armed >= minutes * 60_000
    }
}

/// 计算这一拍的动作列表。
pub fn tick_signals(
    tick: PlaybackTick,
    prefs: &PlayerPreferences,
    rules: &SessionRules,
    sleep: &SleepTimerState,
    now_ms: i64,
    last_persisted_ms: i64,
) -> Vec<Signal> {
    let mut signals = Vec::new();

    let remaining = tick
        .duration_ms
        .filter(|duration| *duration > 0)
        .map(|duration| duration - tick.position_ms);
    let ended = remaining.is_some_and(|left| left <= rules.advance_lead_ms);

    // 1. 到点停：优先于一切。到点就不该再预加载或切集。
    let sleep_due =
        sleep.expired(now_ms) || (sleep.timer == SleepTimer::EndOfEpisode && ended && !tick.paused);
    if sleep_due {
        signals.push(Signal::StopForSleep);
        if rules
            .resume
            .should_persist(tick.position_ms, last_persisted_ms)
        {
            signals.push(Signal::PersistProgress);
        }
        return signals;
    }

    // 2. 暂停时只记进度，不预加载、不切集。
    if tick.paused {
        if rules
            .resume
            .should_persist(tick.position_ms, last_persisted_ms)
        {
            signals.push(Signal::PersistProgress);
        }
        return signals;
    }

    // 3. 放完这一集：连播开着才切；关着就什么都不做（停在片尾）。
    if ended {
        if prefs.continuous_play {
            signals.push(Signal::AdvanceToNext);
        }
        if rules
            .resume
            .should_persist(tick.position_ms, last_persisted_ms)
        {
            signals.push(Signal::PersistProgress);
        }
        return signals;
    }

    // 4. 还剩一点：先把下一集打开（只预加载，不切界面）。
    if prefs.continuous_play
        && let Some(left) = remaining
        && left <= rules.preload_lead_ms
    {
        signals.push(Signal::PreloadNext);
    }

    // 5. 常规落盘。
    if rules
        .resume
        .should_persist(tick.position_ms, last_persisted_ms)
    {
        signals.push(Signal::PersistProgress);
    }

    signals
}

#[cfg(test)]
mod tests {
    use super::*;

    const MINUTE: i64 = 60_000;

    fn playing(position_ms: i64, duration_ms: i64) -> PlaybackTick {
        PlaybackTick {
            position_ms,
            duration_ms: Some(duration_ms),
            paused: false,
        }
    }

    #[test]
    fn mid_playback_only_persists_on_the_interval() {
        let prefs = PlayerPreferences::default();
        let rules = SessionRules::default();
        let sleep = SleepTimerState::off();

        let fresh = tick_signals(
            playing(5 * MINUTE, 45 * MINUTE),
            &prefs,
            &rules,
            &sleep,
            0,
            5 * MINUTE,
        );
        assert_eq!(fresh, vec![]);

        let due = tick_signals(
            playing(5 * MINUTE, 45 * MINUTE),
            &prefs,
            &rules,
            &sleep,
            0,
            5 * MINUTE - 10_000,
        );
        assert_eq!(due, vec![Signal::PersistProgress]);
    }

    #[test]
    fn last_ten_seconds_preload_the_next_episode() {
        let prefs = PlayerPreferences::default();
        let rules = SessionRules::default();
        let sleep = SleepTimerState::off();
        let signals = tick_signals(
            playing(44 * MINUTE + 51_000, 45 * MINUTE),
            &prefs,
            &rules,
            &sleep,
            0,
            44 * MINUTE,
        );
        assert!(signals.contains(&Signal::PreloadNext), "{signals:?}");
    }

    #[test]
    fn the_end_advances_only_when_continuous_play_is_on() {
        let rules = SessionRules::default();
        let sleep = SleepTimerState::off();
        let tick = playing(45 * MINUTE - 200, 45 * MINUTE);

        let on = tick_signals(tick, &PlayerPreferences::default(), &rules, &sleep, 0, 0);
        assert!(on.contains(&Signal::AdvanceToNext), "{on:?}");

        let off_prefs = PlayerPreferences {
            continuous_play: false,
            ..PlayerPreferences::default()
        };
        let off = tick_signals(tick, &off_prefs, &rules, &sleep, 0, 0);
        assert!(!off.contains(&Signal::AdvanceToNext), "{off:?}");
        assert!(!off.contains(&Signal::PreloadNext));
    }

    #[test]
    fn paused_playback_never_preloads_or_advances() {
        let prefs = PlayerPreferences::default();
        let rules = SessionRules::default();
        let sleep = SleepTimerState::off();
        let signals = tick_signals(
            PlaybackTick {
                position_ms: 45 * MINUTE - 100,
                duration_ms: Some(45 * MINUTE),
                paused: true,
            },
            &prefs,
            &rules,
            &sleep,
            0,
            45 * MINUTE - 100,
        );
        assert_eq!(signals, vec![]);
    }

    #[test]
    fn sleep_timer_stops_instead_of_advancing() {
        let prefs = PlayerPreferences::default();
        let rules = SessionRules::default();
        let sleep = SleepTimerState::armed(SleepTimer::Minutes30, 1_000_000);
        // 30 分钟整到点。
        let signals = tick_signals(
            playing(45 * MINUTE - 100, 45 * MINUTE),
            &prefs,
            &rules,
            &sleep,
            1_000_000 + 30 * MINUTE,
            0,
        );
        assert_eq!(signals.first(), Some(&Signal::StopForSleep));
        assert!(!signals.contains(&Signal::AdvanceToNext));
        assert!(!signals.contains(&Signal::PreloadNext));
    }

    #[test]
    fn end_of_episode_timer_stops_at_the_credits() {
        let prefs = PlayerPreferences::default();
        let rules = SessionRules::default();
        let sleep = SleepTimerState::armed(SleepTimer::EndOfEpisode, 0);
        let signals = tick_signals(
            playing(45 * MINUTE - 100, 45 * MINUTE),
            &prefs,
            &rules,
            &sleep,
            9_999_999,
            0,
        );
        assert_eq!(signals.first(), Some(&Signal::StopForSleep));
        assert!(!signals.contains(&Signal::AdvanceToNext));
    }

    #[test]
    fn sleep_timer_not_yet_due_keeps_playing() {
        let rules = SessionRules::default();
        let sleep = SleepTimerState::armed(SleepTimer::Minutes60, 0);
        let signals = tick_signals(
            playing(10 * MINUTE, 45 * MINUTE),
            &PlayerPreferences::default(),
            &rules,
            &sleep,
            30 * MINUTE,
            10 * MINUTE,
        );
        assert!(!signals.contains(&Signal::StopForSleep));
    }

    #[test]
    fn unknown_duration_never_preloads_or_advances() {
        let prefs = PlayerPreferences::default();
        let rules = SessionRules::default();
        let sleep = SleepTimerState::off();
        let signals = tick_signals(
            PlaybackTick {
                position_ms: 40 * MINUTE,
                duration_ms: None,
                paused: false,
            },
            &prefs,
            &rules,
            &sleep,
            0,
            40 * MINUTE,
        );
        assert!(!signals.contains(&Signal::PreloadNext));
        assert!(!signals.contains(&Signal::AdvanceToNext));
    }

    #[test]
    fn stop_for_sleep_also_persists_when_the_interval_elapsed() {
        let rules = SessionRules::default();
        let sleep = SleepTimerState::armed(SleepTimer::Minutes15, 0);
        let signals = tick_signals(
            playing(20 * MINUTE, 45 * MINUTE),
            &PlayerPreferences::default(),
            &rules,
            &sleep,
            15 * MINUTE,
            19 * MINUTE,
        );
        assert_eq!(signals, vec![Signal::StopForSleep, Signal::PersistProgress]);
    }
}
