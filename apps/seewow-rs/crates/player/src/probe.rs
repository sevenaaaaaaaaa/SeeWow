//! HDR 探针：把 mpv 的 `video-target-params` 与 macOS 图层/屏幕状态收缩成
//! **两个布尔** + 一句话结论（ADR-0010：不许合成一个布尔）。
//!
//! 口径（ADR-0010 §1）：
//!
//! ```text
//! pipeline_hdr =
//!       video-target-params/gamma ∈ {pq, hlg}
//!    && video-target-params/max-luma > 100.0            # 单位 cd/m²
//!    && video-target-params/primaries == bt.2020
//!    && layer.pixelFormat ∈ 10-bit XR 族 {bgr10a2Unorm, rgba16Float}   // ADR-0010 v3
//!    && layer.wantsExtendedDynamicRangeContent == true
//!    && layer.colorspace ∈ PQ/HLG 族
//!
//! on_screen_hdr = pipeline_hdr
//!    && screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0
//!    && screen.maximumExtendedDynamicRangeColorComponentValue > 1.0
//! ```
//!
//! 本机是 SDR 屏（headroom = 1.0），合格判定是 `pipeline_hdr == true` 且
//! `on_screen_hdr == false`：**「HDR 管线已通、未上屏」，这不是失败。**

/// SDR 参考白（cd/m²）。`max-luma` 必须严格大于它才算 HDR 目标。
pub const SDR_REFERENCE_WHITE: f64 = 100.0;

/// mpv `video-target-params/*` —— HDR 判定只读目标侧（ADR-0010 §3）。
#[derive(Clone, Debug, Default, PartialEq)]
pub struct TargetParams {
    pub gamma: String,
    pub primaries: String,
    /// cd/m²；取不到时为 `None`
    pub max_luma: Option<f64>,
    /// cd/m²；取不到时为 `None`
    pub min_luma: Option<f64>,
    pub pixelformat: String,
}

/// 视频窗口图层（mpv 的 cocoa-cb 建的 CAMetalLayer）。
#[derive(Clone, Debug, Default, PartialEq)]
pub struct LayerState {
    /// 归一化后的名字，例如 `rgba16float` / `bgra8unorm`；读不到时为空。
    pub pixel_format: String,
    pub wants_edr: bool,
    /// 图层色彩空间所属族，例如 `bt.2100-pq`；未知时为空。
    pub colorspace: String,
}

/// 源侧 video-params/* —— 只作证据（判定不用它），但日志里必须能复核「源是不是 PQ」。
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SourceParams {
    pub gamma: String,
    pub primaries: String,
    pub pixelformat: String,
    pub width: i64,
    pub height: i64,
}

/// 屏幕的 EDR 能力（`NSScreen`，只读）。
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ScreenState {
    pub max_potential_edr: f64,
    pub max_current_edr: f64,
    pub name: String,
    pub scale: f64,
}

/// 判定函数的输入：全部取不到的值都留空 / `None`，判定按「证据不足 = 不成立」处理。
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ProbeSeed {
    pub target: TargetParams,
    pub layer: LayerState,
    pub screen: ScreenState,
    /// 像素回读（`screenshot-raw` 16F）的最大通道值；M1 拿不到，为 `None`。
    pub pixel_readback_max: Option<f64>,
}

/// 探针证据行要不要写：**播放中每秒至少一条**，静止时只在关键字段变化时写。
///
/// 这条门独立于 UI —— 面板拿不到（`ui.upgrade()` 失败）也必须能留证据。
pub fn should_log_probe(playing: bool, changed: bool, since_last: std::time::Duration) -> bool {
    let slow_enough = since_last >= std::time::Duration::from_millis(1000);
    if playing {
        // 播放中：每秒至少一条（验收要看 target.* 到底有没有值），与字段是否变化无关
        slow_enough
    } else {
        // 静止：只在关键字段变化时写，避免刷屏
        changed && slow_enough
    }
}

/// 证据字段：空 / `n/a` / `no` 一律写成 `missing`，不许省略字段。
fn field(value: &str) -> &str {
    match value.trim() {
        "" | "n/a" | "no" | "unknown" => "missing",
        other => other,
    }
}

/// 一行写进 m1.log 的证据（与 UI 无关，测试可直接驱动）。
///
/// **源侧与目标侧必须同时出现**：只看目标侧无法复核「源是不是 PQ」，
/// 第三方复核时需要 `source.*` 与 `target.*` 在一行里对得上。
pub fn probe_log_line(seed: &ProbeSeed, source: &SourceParams, verdict: &Verdict) -> String {
    let source_size = if source.width > 0 && source.height > 0 {
        format!("{}x{}", source.width, source.height)
    } else {
        "missing".to_string()
    };
    format!(
        "probe: target.gamma={} target.primaries={} target.max-luma={} cd/m² target.pixfmt={} | surface.pixfmt={} wantsEDR={} csp(opt)={} | source.gamma={} source.primaries={} source.pixfmt={} source.size={} | screen.potentialEDR={:.3} currentEDR={:.3} | {}",
        field(&seed.target.gamma),
        field(&seed.target.primaries),
        seed.target
            .max_luma
            .map(|value| format!("{value:.1}"))
            .unwrap_or_else(|| "missing".into()),
        field(&seed.target.pixelformat),
        field(&seed.layer.pixel_format),
        seed.layer.wants_edr,
        dash(&seed.layer.colorspace),
        field(&source.gamma),
        field(&source.primaries),
        field(&source.pixelformat),
        source_size,
        seed.screen.max_potential_edr,
        seed.screen.max_current_edr,
        verdict.log_line(),
    )
}

/// `target.*` 不可用时的分项诊断：属性「不存在」与「存在但为空」要分开。
#[derive(Clone, Debug, Default, PartialEq)]
pub struct VoDiagnostics {
    pub current_vo: String,
    pub video_params: String,
    pub target_params: String,
}

/// target 不可用时写清原因：属性不存在 / 存在但为空，以及锁屏时这是「预期」。
pub fn target_unavailable_note(diag: &VoDiagnostics, locked: Option<bool>) -> String {
    let (lock_text, verdict_text) = match locked {
        Some(true) => ("锁屏", "VO 未呈现，target 不可用（属预期）"),
        Some(false) => ("未锁屏", "VO 未呈现属异常，需查 mpv 的 VO 日志"),
        None => ("锁屏状态未知", "无法判定，需查 mpv 的 VO 日志"),
    };
    format!(
        "target-diag: current-vo={} video-params={} video-target-params={} | {lock_text} → {verdict_text}",
        dash(&diag.current_vo),
        dash(&diag.video_params),
        dash(&diag.target_params),
    )
}

/// 面板 MACOS 列。**色彩空间那行必须写明是选项读回**，不许写成图层实测。
pub fn mac_rows(seed: &ProbeSeed) -> String {
    format!(
        "screen {}
potentialEDR {:.3}
currentEDR {:.3}
scale {:.2}

surface
pixelFormat {}
wantsEDR {}

cocoa-cb-output-csp（选项读回） {}",
        dash(&seed.screen.name),
        seed.screen.max_potential_edr,
        seed.screen.max_current_edr,
        seed.screen.scale,
        dash(&seed.layer.pixel_format),
        seed.layer.wants_edr,
        dash(&seed.layer.colorspace),
    )
}

/// 单条证据。面板逐条显示，失败项一眼可见。
#[derive(Clone, Debug, PartialEq)]
pub struct Check {
    pub label: &'static str,
    pub ok: bool,
    pub detail: String,
}

/// 结论。`evidence_source`：1 = 像素回读，2 = 管线状态（ADR-0010 §4）。
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Verdict {
    pub pipeline_hdr: bool,
    pub on_screen_hdr: bool,
    pub evidence_source: u8,
    pub headline: String,
    pub checks: Vec<Check>,
}

impl Verdict {
    /// 一行写进 m1.log 的口径。
    pub fn log_line(&self) -> String {
        format!(
            "pipeline_hdr={} on_screen_hdr={} evidence_source={} headline={}",
            self.pipeline_hdr, self.on_screen_hdr, self.evidence_source, self.headline
        )
    }
}

/// 判定：六项管线证据 → `pipeline_hdr`；再加屏幕 headroom → `on_screen_hdr`。
///
/// 空值 = 证据不足 = 不成立（绝不把「取不到」当成「通过」）。
pub fn judge(seed: &ProbeSeed) -> Verdict {
    let target = &seed.target;
    let layer = &seed.layer;

    // 渲染目标格式：优先读图层（ADR-0010 的公式就是 layer.pixelFormat），
    // 图层读不到时退回 mpv 报的 video-target-params/pixelformat。
    let render_format = if layer.pixel_format.trim().is_empty() {
        target.pixelformat.trim().to_string()
    } else {
        layer.pixel_format.trim().to_string()
    };
    let render_source = if layer.pixel_format.trim().is_empty() {
        "video-target-params/pixelformat"
    } else {
        "layer.pixelFormat"
    };

    let checks = vec![
        Check {
            label: "video-target-params/gamma ∈ {pq, hlg}",
            ok: is_pq_or_hlg(&target.gamma),
            detail: format!("video-target-params/gamma = {}", dash(&target.gamma)),
        },
        Check {
            label: "video-target-params/max-luma > 100 cd/m²",
            ok: target.max_luma.is_some_and(|v| v > SDR_REFERENCE_WHITE),
            detail: match target.max_luma {
                Some(v) => format!("video-target-params/max-luma = {v:.1} cd/m²"),
                None => "video-target-params/max-luma = n/a".to_string(),
            },
        },
        Check {
            label: "video-target-params/primaries == bt.2020",
            ok: is_bt2020(&target.primaries),
            detail: format!(
                "video-target-params/primaries = {}",
                dash(&target.primaries)
            ),
        },
        Check {
            // ADR-0010 v3：10-bit XR 族都算（本机 mpv 实测 bgr10a2Unorm，不是 16F）
            label: "surface.pixelFormat ∈ 10-bit XR 族 {bgr10a2Unorm, rgba16Float}",
            ok: is_10bit_xr_surface(&render_format),
            detail: format!("{render_source} = {}", dash(&render_format)),
        },
        Check {
            label: "layer.wantsExtendedDynamicRangeContent",
            ok: layer.wants_edr,
            detail: format!("layer.wantsEDR = {}", layer.wants_edr),
        },
        Check {
            // 这条不是图层实测：值来自我们自己设的 mpv 选项读回（cocoa-cb-output-csp），
            // 标签必须写明，否则是自证。
            label: "cocoa-cb-output-csp（选项读回，非图层实测）∈ PQ/HLG 族",
            ok: is_pq_or_hlg(&layer.colorspace),
            detail: format!("csp(opt) = {}", dash(&layer.colorspace)),
        },
    ];

    let pipeline_hdr = checks.iter().all(|check| check.ok);

    let screen = &seed.screen;
    let on_screen_hdr =
        pipeline_hdr && screen.max_potential_edr > 1.0 && screen.max_current_edr > 1.0;

    // 1 = 像素回读（screenshot-raw 给 16F 浮点），2 = 管线状态。M1 只能拿到 2。
    // 8bit 回读（bgra8unorm 之类）不能算「像素回读证据」，只能落到 2 —— 否则会把
    // 「8bit 回读拿到 0.9」说成像素证据，验收时会吵。
    let float_surface = matches!(
        render_format
            .trim()
            .to_ascii_lowercase()
            .replace(['_', '-'], "")
            .as_str(),
        "rgba16float" | "rgba16f" | "rgba16" | "rgba64f"
    );
    let evidence_source = if seed.pixel_readback_max.is_some() && float_surface {
        1
    } else {
        2
    };

    let headline = if pipeline_hdr && on_screen_hdr {
        format!(
            "HDR 直通上屏：管线成立，屏幕 headroom = {:.2}（潜力 {:.2}）",
            screen.max_current_edr, screen.max_potential_edr
        )
    } else if pipeline_hdr {
        format!(
            "HDR 管线已通、未上屏：屏幕 EDR headroom = {:.2}（本机为 SDR 屏，非失败）",
            screen.max_current_edr
        )
    } else {
        let failing: Vec<&str> = checks
            .iter()
            .filter(|check| !check.ok)
            .map(|check| check.label)
            .collect();
        format!("未直通：{} 不成立", failing.join("、"))
    };

    Verdict {
        pipeline_hdr,
        on_screen_hdr,
        evidence_source,
        headline,
        checks,
    }
}

fn dash(value: &str) -> &str {
    if value.trim().is_empty() {
        "n/a"
    } else {
        value.trim()
    }
}

/// mpv 的字符串属性取「不可用」时会回 `no` / 空串，这里统一成 `None`。
pub fn str_or_none(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed == "no" || trimmed == "n/a" || trimmed == "unknown" {
        None
    } else {
        Some(trimmed.to_string())
    }
}

/// `NaN` 当作取不到（mpv 对不可用数值属性会报错，但不排除回 NaN）。
pub fn f64_or_none(value: f64) -> Option<f64> {
    if value.is_finite() { Some(value) } else { None }
}

/// mpv 用 `i64::MIN` 表示「没有」。
pub fn i64_or_none(value: i64) -> Option<i64> {
    if value == i64::MIN { None } else { Some(value) }
}

/// PQ / HLG 族：mpv 的 `gamma` 取值与 macOS 色彩空间名都收敛到这里。
pub fn is_pq_or_hlg(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().replace('_', "-").as_str(),
        "pq" | "smpte2084"
            | "smpte-st-2084"
            | "bt2100-pq"
            | "bt-2100-pq"
            | "bt.2100-pq"
            | "display-p3-pq"
            | "dci-p3-pq"
            | "bt2020-pq"
            | "hlg"
            | "arib-std-b67"
            | "bt2100-hlg"
            | "bt-2100-hlg"
            | "bt.2100-hlg"
            | "display-p3-hlg"
            | "bt2020-hlg"
    )
}

pub fn is_bt2020(value: &str) -> bool {
    matches!(
        value
            .trim()
            .to_ascii_lowercase()
            .replace(['_', '.', '-'], "")
            .as_str(),
        "bt2020" | "bt2020nc" | "bt2020c"
    )
}

/// 渲染目标是不是「10-bit XR 族」——ADR-0010 v3 的口径。
///
/// 本机实测 mpv 0.42 的 cocoa-cb 层是 `bgr10a2Unorm`（10-bit BGRA XR），
/// 不是 `RGBA16Float`；写死 16F 会让本机恒假，把「管线正常」误判成「未直通」。
/// 两个都算合格，8bit 一律不合格。
pub fn is_10bit_xr_surface(value: &str) -> bool {
    matches!(
        value
            .trim()
            .to_ascii_lowercase()
            .replace(['_', '-'], "")
            .as_str(),
        // 16F 半浮点
        "rgba16float" | "rgba16f" | "rgba16" | "rgba64f"
        // 10-bit XR 族（mpv 报 bgr10a2Unorm；Metal 的 BGRA10_XR 变体也归这里）
        | "bgr10a2unorm" | "bgra10_xr" | "bgra10xr" | "bgra10xrsrgb" | "bgr10xr" | "bgr10xrsrgb"
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn source_fixture() -> SourceParams {
        SourceParams {
            gamma: "pq".to_string(),
            primaries: "bt.2020".to_string(),
            pixelformat: "p010".to_string(),
            width: 1920,
            height: 1080,
        }
    }

    fn seed_with_values() -> ProbeSeed {
        ProbeSeed {
            target: TargetParams {
                gamma: "pq".to_string(),
                primaries: "bt.2020".to_string(),
                max_luma: Some(1000.0),
                min_luma: Some(0.005),
                pixelformat: "rgba16f".to_string(),
            },
            layer: LayerState {
                pixel_format: "bgr10a2Unorm".to_string(),
                wants_edr: true,
                colorspace: "bt.2100-pq".to_string(),
            },
            screen: ScreenState {
                max_potential_edr: 2.0,
                max_current_edr: 1.0,
                name: "Built-in Retina Display".to_string(),
                scale: 2.0,
            },
            pixel_readback_max: None,
        }
    }

    /// 播放中必须每秒留一条证据 —— 即使关键字段没变（这是验收要看的 target.* 来源）。
    #[test]
    fn playing_always_logs_at_least_once_per_second() {
        assert!(should_log_probe(true, false, Duration::from_millis(1000)));
        assert!(!should_log_probe(true, false, Duration::from_millis(300)));
    }

    /// 静止时只在字段变化时写（不刷屏）。
    #[test]
    fn idle_logs_only_on_change() {
        assert!(should_log_probe(false, true, Duration::from_millis(1000)));
        assert!(!should_log_probe(false, false, Duration::from_millis(5000)));
    }

    /// 证据行与 UI 无关：给定 seed + verdict 就能出完整一行，target.* 必须有值。
    #[test]
    fn probe_log_line_carries_target_values_without_ui() {
        let seed = seed_with_values();
        let verdict = judge(&seed);
        let line = probe_log_line(&seed, &source_fixture(), &verdict);

        assert!(line.starts_with("probe: "));
        assert!(line.contains("target.gamma=pq"), "实际：{line}");
        assert!(line.contains("target.primaries=bt.2020"), "实际：{line}");
        assert!(
            line.contains("target.max-luma=1000.0 cd/m²"),
            "实际：{line}"
        );
        assert!(line.contains("surface.pixfmt=bgr10a2Unorm"), "实际：{line}");
        assert!(line.contains("csp(opt)=bt.2100-pq"), "实际：{line}");
        assert!(line.contains("currentEDR=1.000"), "实际：{line}");
        assert!(line.contains("pipeline_hdr=true"), "实际：{line}");
    }

    /// 8bit 像素回读不能算「像素回读证据」。
    #[test]
    fn eight_bit_readback_still_reports_pipeline_evidence_source() {
        let mut seed = seed_with_values();
        seed.layer.pixel_format = "bgra8unorm".to_string();
        seed.target.pixelformat = "bgra".to_string();
        seed.pixel_readback_max = Some(0.9);
        assert_eq!(judge(&seed).evidence_source, 2, "8bit 回读只能算管线证据");
    }

    /// target.* 为 n/a 时必须写清原因：属性不存在 vs 存在但为空，以及锁屏时的「预期」。
    #[test]
    fn target_unavailable_note_separates_missing_from_empty_and_marks_locked_screen() {
        let diag = VoDiagnostics {
            current_vo: "gpu-next".to_string(),
            video_params: "存在且非空".to_string(),
            target_params: "不存在".to_string(),
        };
        let note = target_unavailable_note(&diag, Some(true));
        assert!(note.contains("video-params=存在且非空"), "实际：{note}");
        assert!(note.contains("video-target-params=不存在"), "实际：{note}");
        assert!(
            note.contains("锁屏") && note.contains("预期"),
            "锁屏时必须写明「预期」，实际：{note}"
        );

        let unlocked = target_unavailable_note(&diag, Some(false));
        assert!(unlocked.contains("未锁屏"), "实际：{unlocked}");
        assert!(
            !unlocked.contains("属预期"),
            "未锁屏时不许赖给锁屏，实际：{unlocked}"
        );
    }

    /// 面板 MACOS 列不许把选项读回写成图层实测。
    #[test]
    fn mac_rows_labels_option_readback_not_layer_snapshot() {
        let seed = seed_with_values();
        let rows = mac_rows(&seed);
        assert!(
            rows.contains("cocoa-cb-output-csp（选项读回）"),
            "实际：{rows}"
        );
        assert!(!rows.contains("layer.colorspace"), "实际：{rows}");
    }

    /// 证据行必须同时给出源侧与目标侧：没有源侧，就没法复核「源是不是 PQ」。
    #[test]
    fn probe_log_line_carries_source_and_target_side_by_side() {
        let seed = seed_with_values();
        let verdict = judge(&seed);
        let source = source_fixture();
        let line = probe_log_line(&seed, &source, &verdict);

        // 源侧
        assert!(line.contains("source.gamma=pq"), "实际：{line}");
        assert!(line.contains("source.primaries=bt.2020"), "实际：{line}");
        assert!(line.contains("source.pixfmt=p010"), "实际：{line}");
        assert!(line.contains("source.size=1920x1080"), "实际：{line}");
        // 目标侧
        assert!(line.contains("target.gamma=pq"), "实际：{line}");
        assert!(line.contains("target.primaries=bt.2020"), "实际：{line}");
        assert!(
            line.contains("target.max-luma=1000.0 cd/m²"),
            "实际：{line}"
        );
    }

    /// 任一侧缺失时必须明写 missing，不许省略字段。
    #[test]
    fn probe_log_line_marks_missing_side_explicitly() {
        let seed = seed_with_values();
        let verdict = judge(&seed);
        let line = probe_log_line(&seed, &SourceParams::default(), &verdict);
        assert!(line.contains("source.gamma=missing"), "实际：{line}");
        assert!(line.contains("source.pixfmt=missing"), "实际：{line}");
        assert!(line.contains("source.size=missing"), "实际：{line}");
        assert!(
            line.contains("target.gamma="),
            "目标侧仍要出现，实际：{line}"
        );

        let mut seed = seed_with_values();
        seed.target = TargetParams::default();
        let verdict = judge(&seed);
        let line = probe_log_line(&seed, &source_fixture(), &verdict);
        assert!(line.contains("target.gamma=missing"), "实际：{line}");
        assert!(line.contains("target.primaries=missing"), "实际：{line}");
    }

    /// 色彩空间那条不能写成「图层实测」——它是我们设的选项读回。
    #[test]
    fn colorspace_check_is_labelled_as_option_readback() {
        let verdict = judge(&seed_with_values());
        let check = verdict
            .checks
            .iter()
            .find(|check| check.label.to_lowercase().contains("csp"))
            .expect("必须有一条色彩空间证据");
        assert!(
            check.label.contains("选项读回"),
            "标签必须写明是选项读回，实际：{}",
            check.label
        );
    }
}
