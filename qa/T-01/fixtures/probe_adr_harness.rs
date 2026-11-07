//! T-01 的 QA harness：直接对 seewow_player::probe::judge 跑 ADR-0010 v3 的口径。
//!
//! 为什么单独写：任务表要求「QA 用例在 qa/T-01 里」，而产品目录不归 QA 改。
//! 这个文件由 case-04-probe-adr.sh 用 rustc 直接编到已经构建好的 rlib 上。
//!
//! 判据全部来自：ADR-0010 §1/§2/§4（v3）、PRD v2 §10 的更正、T-01 的 DoD。
use seewow_player::probe::{judge, LayerState, ProbeSeed, ScreenState, TargetParams};

static mut FAILED: u32 = 0;

fn check(name: &str, cond: bool, detail: &str) {
    unsafe {
        if cond {
            println!("  [ok]   {name}");
        } else {
            FAILED += 1;
            println!("  [FAIL] {name} —— {detail}");
        }
    }
}

fn sdr_screen() -> ScreenState {
    ScreenState {
        max_potential_edr: 2.0,
        max_current_edr: 1.0,
        name: "Built-in Retina Display".to_string(),
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

/// 本机实测的表面：bgr10a2Unorm（ADR-0010 §实测记录），不是 RGBA16Float。
fn machine_seed(screen: ScreenState) -> ProbeSeed {
    ProbeSeed {
        target: TargetParams {
            gamma: "pq".to_string(),
            primaries: "bt.2020".to_string(),
            max_luma: Some(1000.0),
            min_luma: Some(0.005),
            pixelformat: "bgr10a2unorm".to_string(),
        },
        layer: LayerState {
            pixel_format: "bgr10a2Unorm".to_string(),
            wants_edr: true,
            colorspace: "bt.2100-pq".to_string(),
        },
        screen,
        pixel_readback_max: None,
    }
}

fn main() {
    // 1. 本机口径（PRD v2 §10 + ADR-0010 §2）：SDR 屏 + 管线齐 = 已通未上屏，不是失败。
    let v = judge(&machine_seed(sdr_screen()));
    check(
        "SDR 屏 + 完整管线证据 → pipeline_hdr = true（T-01 DoD：本机必须显示 true）",
        v.pipeline_hdr,
        &format!("headline={}", v.headline),
    );
    check(
        "SDR 屏 headroom=1.0 → on_screen_hdr = false",
        !v.on_screen_hdr,
        "headroom = 1.0 时不许判上屏",
    );
    check(
        "结论写「管线已通、未上屏」且如实带出 headroom 1.00",
        v.headline.contains("管线已通") && v.headline.contains("未上屏") && v.headline.contains("1.00"),
        &v.headline,
    );
    check(
        "证据来源 = 2（M1 没有像素回读，按管线状态；ADR-0010 §4）",
        v.evidence_source == 2,
        &format!("evidence_source={}", v.evidence_source),
    );
    check(
        "六条证据逐条可对上（面板要能指出是哪一条不成立）",
        v.checks.len() == 6,
        &format!("len={}", v.checks.len()),
    );
    check("全齐时六条都是 ok", v.checks.iter().all(|c| c.ok), "有检查项不成立");

    // 2. EDR 屏 + 同样管线 = 真的上屏。
    let v2 = judge(&machine_seed(edr_screen()));
    check(
        "EDR 屏（headroom > 1.0）+ 管线齐 → on_screen_hdr = true",
        v2.pipeline_hdr && v2.on_screen_hdr,
        &v2.headline,
    );

    // 3. ADR-0010 v3：10-bit XR 族里的 rgba16Float 也合格（不能因为本机是 bgr10a2 就把 16F 判死）。
    let mut seed = machine_seed(sdr_screen());
    seed.layer.pixel_format = "rgba16float".to_string();
    seed.target.pixelformat = "rgba16f".to_string();
    check("rgba16Float 表面同属合格族", judge(&seed).pipeline_hdr, "16F 必须也算合格");

    // 4. 8bit 表面一律不成立（不能把 SDR 表面误判成 HDR 管线）。
    let mut seed = machine_seed(sdr_screen());
    seed.layer.pixel_format = "bgra8unorm".to_string();
    seed.target.pixelformat = "bgra".to_string();
    check("8bit 表面 → pipeline_hdr = false", !judge(&seed).pipeline_hdr, "8bit 不可能是 HDR 管线");

    // 5. HLD §9.5 的失败判据：目标侧被压成 SDR。
    let mut seed = machine_seed(sdr_screen());
    seed.target.gamma = "srgb".to_string();
    check("目标侧 gamma=srgb（被压成 SDR）→ false", !judge(&seed).pipeline_hdr, "压缩必须判未直通");

    // 6. 证据不足 ≠ 通过（空值不得当合格）。
    let empty = judge(&ProbeSeed::default());
    check(
        "全部取不到时两个布尔都是 false（证据不足不当通过）",
        !empty.pipeline_hdr && !empty.on_screen_hdr && empty.checks.iter().all(|c| !c.ok),
        "空输入被判成通过了",
    );

    // 7. max-luma 的边界：100 cd/m² 不算 HDR 目标，100.5 算。
    let mut seed = machine_seed(sdr_screen());
    seed.target.max_luma = Some(100.0);
    check("max-luma = 100.0（SDR 参考白）不算 HDR 目标", !judge(&seed).pipeline_hdr, "边界应当排除");
    seed.target.max_luma = Some(100.5);
    check("max-luma = 100.5 算 HDR 目标", judge(&seed).pipeline_hdr, "严格大于 100 就成立");

    unsafe {
        if FAILED == 0 {
            println!("\ncase-04: 全部通过");
        } else {
            println!("\ncase-04: 失败 {n} 项", n = { FAILED });
            std::process::exit(1);
        }
    }
}
