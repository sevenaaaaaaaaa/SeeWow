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
            label: "layer.pixelFormat ∈ 10-bit XR 族 {bgr10a2Unorm, rgba16Float}",
            ok: is_10bit_xr_surface(&render_format),
            detail: format!("{render_source} = {}", dash(&render_format)),
        },
        Check {
            label: "layer.wantsExtendedDynamicRangeContent",
            ok: layer.wants_edr,
            detail: format!("layer.wantsEDR = {}", layer.wants_edr),
        },
        Check {
            label: "layer.colorspace ∈ PQ/HLG 族",
            ok: is_pq_or_hlg(&layer.colorspace),
            detail: format!("layer.colorspace = {}", dash(&layer.colorspace)),
        },
    ];

    let pipeline_hdr = checks.iter().all(|check| check.ok);

    let screen = &seed.screen;
    let on_screen_hdr =
        pipeline_hdr && screen.max_potential_edr > 1.0 && screen.max_current_edr > 1.0;

    // 1 = 像素回读（screenshot-raw 给 16F），2 = 管线状态。M1 只能拿到 2。
    let evidence_source = if seed.pixel_readback_max.is_some() {
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
