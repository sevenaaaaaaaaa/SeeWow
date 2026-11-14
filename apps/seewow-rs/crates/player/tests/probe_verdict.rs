//! T-01 的失败测试（先写）：探针判定函数。
//!
//! 口径见 ADR-0010：两个布尔（pipeline_hdr / on_screen_hdr）+ 证据来源，
//! 只用 `video-target-params`，`max-luma` 单位 cd/m²，不用 deprecated 的 `sig-peak`。
//!
//! 最要紧的一条是本机（SDR 屏）口径：**管线证据齐 + headroom = 1.0
//! = 「HDR 管线已通、未上屏」，不是失败。**

use seewow_player::probe::{LayerState, ProbeSeed, ScreenState, TargetParams, judge};

fn pq_target() -> TargetParams {
    TargetParams {
        gamma: "pq".to_string(),
        primaries: "bt.2020".to_string(),
        max_luma: Some(1000.0),
        min_luma: Some(0.005),
        pixelformat: "rgba16f".to_string(),
    }
}

fn metal_16f_layer() -> LayerState {
    LayerState {
        pixel_format: "rgba16float".to_string(),
        wants_edr: true,
        colorspace: "bt.2100-pq".to_string(),
    }
}

fn sdr_screen() -> ScreenState {
    ScreenState {
        max_potential_edr: 1.0,
        max_current_edr: 1.0,
        name: "Color LCD".to_string(),
        scale: 2.0,
    }
}

fn edr_screen() -> ScreenState {
    ScreenState {
        max_potential_edr: 1.6,
        max_current_edr: 1.2,
        name: "Pro Display XDR".to_string(),
        scale: 2.0,
    }
}

fn complete_pipeline(screen: ScreenState) -> ProbeSeed {
    ProbeSeed {
        target: pq_target(),
        layer: metal_16f_layer(),
        screen,
        pixel_readback_max: None,
    }
}

/// 本机口径（PRD v2 §10 的更正）：SDR 屏 + 管线证据齐 = 管线已通、未上屏。
#[test]
fn sdr_screen_with_complete_pipeline_evidence_is_pipeline_ok_not_on_screen() {
    let v = judge(&complete_pipeline(sdr_screen()));

    assert!(v.pipeline_hdr, "四项管线证据齐时必须判管线已通");
    assert!(!v.on_screen_hdr, "headroom = 1.0 时不许判上屏 HDR");
    assert!(
        v.headline.contains("管线已通") && v.headline.contains("未上屏"),
        "结论必须写成「管线已通、未上屏」，实际：{}",
        v.headline
    );
    assert!(
        v.headline.contains("1.00"),
        "结论要如实写出 headroom = 1.00，实际：{}",
        v.headline
    );
}

/// EDR 屏 + 同样的管线证据 = 真的上屏。
#[test]
fn edr_screen_with_complete_pipeline_evidence_is_on_screen() {
    let v = judge(&complete_pipeline(edr_screen()));

    assert!(v.pipeline_hdr);
    assert!(v.on_screen_hdr, "headroom > 1.0 且管线成立时必须判上屏");
    assert!(
        v.headline.contains("上屏") && !v.headline.contains("未上屏"),
        "结论必须是正面上屏，实际：{}",
        v.headline
    );
}

/// 目标侧被压成 SDR（gamma = srgb）—— 即使源是 PQ，也判未直通（HLD §9.5 的失败判据）。
#[test]
fn target_gamma_srgb_means_not_pipeline() {
    let mut seed = complete_pipeline(edr_screen());
    seed.target.gamma = "srgb".to_string();

    let v = judge(&seed);

    assert!(!v.pipeline_hdr, "target gamma = srgb 时不许判管线已通");
    assert!(!v.on_screen_hdr);
    assert!(v.headline.contains("未直通"), "实际：{}", v.headline);
}

/// HLG 也算 HDR 传输函数。
#[test]
fn hlg_target_is_accepted() {
    let mut seed = complete_pipeline(sdr_screen());
    seed.target.gamma = "hlg".to_string();
    seed.layer.colorspace = "bt.2100-hlg".to_string();

    let v = judge(&seed);

    assert!(v.pipeline_hdr, "HLG 目标必须算进 PQ/HLG 族");
    assert!(!v.on_screen_hdr);
}

/// 目标 primaries 不是 bt.2020 → 不成立。
#[test]
fn non_bt2020_primaries_breaks_pipeline() {
    let mut seed = complete_pipeline(edr_screen());
    seed.target.primaries = "bt.709".to_string();

    let v = judge(&seed);

    assert!(!v.pipeline_hdr);
    assert!(!v.on_screen_hdr);
}

/// max-luma 必须严格大于 SDR 参考白 100 cd/m²；等于 100 不算。
#[test]
fn max_luma_must_exceed_sdr_white() {
    let mut seed = complete_pipeline(edr_screen());
    seed.target.max_luma = Some(100.0);

    assert!(!judge(&seed).pipeline_hdr, "max-luma = 100.0 不算 HDR 目标");

    seed.target.max_luma = Some(100.5);
    assert!(judge(&seed).pipeline_hdr, "max-luma > 100 必须算成立");

    seed.target.max_luma = None;
    assert!(
        !judge(&seed).pipeline_hdr,
        "取不到 max-luma 时按证据不足处理"
    );
}

/// ADR-0010 v3：10-bit XR 族也算合格 —— 本机实测 mpv 的 cocoa-cb 层就是 `bgr10a2Unorm`。
/// 写死 `RGBA16Float` 会让本机恒假，把「管线正常」误判成「未直通」。
#[test]
fn bgr10a2unorm_surface_is_accepted() {
    let mut seed = complete_pipeline(sdr_screen());
    seed.layer.pixel_format = "bgr10a2Unorm".to_string();

    let v = judge(&seed);

    assert!(
        v.pipeline_hdr,
        "bgr10a2Unorm（10-bit XR）必须算表面格式合格"
    );
    let surface = v
        .checks
        .iter()
        .find(|check| check.label.contains("pixelFormat"))
        .expect("必须有一条表面格式的证据");
    assert!(surface.ok, "表面格式这条证据应当 ok，实际：{surface:?}");
    assert!(
        surface.detail.contains("bgr10a2Unorm"),
        "证据里要如实写出读到的格式，实际：{}",
        surface.detail
    );
}

/// 16F 仍然合格（旧口径不能倒退）。
#[test]
fn rgba16float_surface_is_still_accepted() {
    let mut seed = complete_pipeline(sdr_screen());
    seed.layer.pixel_format = "rgba16float".to_string();
    assert!(judge(&seed).pipeline_hdr, "rgba16float 必须继续算合格");
}

/// 8bit 表面（bgra8unorm 之类）仍然不合格。
#[test]
fn eight_bit_surface_is_rejected() {
    let mut seed = complete_pipeline(sdr_screen());
    seed.layer.pixel_format = "bgra8unorm".to_string();
    seed.target.pixelformat = "bgra".to_string();

    let v = judge(&seed);

    assert!(!v.pipeline_hdr, "8bit 渲染目标不可能是 HDR 管线");
    let surface = v
        .checks
        .iter()
        .find(|check| check.label.contains("pixelFormat"))
        .expect("必须有一条表面格式的证据");
    assert!(!surface.ok, "8bit 时表面格式这条必须失败");
}

/// 图层没有请求 EDR → 不成立。
#[test]
fn layer_must_request_edr() {
    let mut seed = complete_pipeline(edr_screen());
    seed.layer.wants_edr = false;

    assert!(!judge(&seed).pipeline_hdr);
}

/// 图层色彩空间不在 PQ/HLG 族 → 不成立。
#[test]
fn layer_colorspace_must_be_pq_or_hlg_family() {
    let mut seed = complete_pipeline(edr_screen());
    seed.layer.colorspace = "srgb".to_string();

    assert!(!judge(&seed).pipeline_hdr);
}

/// 证据来源必须标出来：没有像素回读就是 2（管线状态），有就是 1（像素回读）。
#[test]
fn evidence_source_is_reported() {
    let mut seed = complete_pipeline(sdr_screen());
    assert_eq!(
        judge(&seed).evidence_source,
        2,
        "M1 没有像素回读，来源必须是 2"
    );

    seed.pixel_readback_max = Some(1.85);
    assert_eq!(judge(&seed).evidence_source, 1, "有像素回读时来源是 1");
}

/// 每一条证据都要能单独对上面板显示（失败项要能指出是哪一条）。
#[test]
fn checks_cover_every_condition() {
    let v = judge(&complete_pipeline(sdr_screen()));
    assert_eq!(
        v.checks.len(),
        6,
        "六项管线证据 + 零漏项，实际：{:?}",
        v.checks
    );
    assert!(v.checks.iter().all(|c| c.ok), "全齐时每条都该是 ok");

    let mut broken = complete_pipeline(sdr_screen());
    broken.layer.wants_edr = false;
    let v = judge(&broken);
    let failed: Vec<&str> = v.checks.iter().filter(|c| !c.ok).map(|c| c.label).collect();
    assert_eq!(
        failed,
        vec!["layer.wantsExtendedDynamicRangeContent"],
        "只应有一项失败"
    );
}
