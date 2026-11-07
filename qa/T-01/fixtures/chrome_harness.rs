//! T-01 的 QA harness：壳层几何与自动隐藏规则（纯函数，不需要看画面）。
//!
//! 参数：width height header_h gutter controls_h traffic_w traffic_h probe_w probe_h top_edge header_actions_w
//! 这些数字由 case-05-chrome-geometry.sh 从 crates/ui/ui/skeleton.slint 里读出来传进来，
//! 所以断言的是「产品里真实的几何」，不是我手写的常数。
//!
//! 判据来源：T-01 DoD 第 3/4/5 条 + CRD-0003 §3/§4。
use seewow_ui::hit::{self, Flags, Layout, Region};
use std::time::Duration;

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

fn arg(args: &[String], i: usize) -> f64 {
    args.get(i).and_then(|v| v.parse().ok()).unwrap_or(0.0)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 12 {
        println!("用法: chrome_harness <11 个几何值>");
        std::process::exit(2);
    }
    let layout = Layout {
        width: arg(&args, 1) as f32,
        height: arg(&args, 2) as f32,
        header_h: arg(&args, 3) as f32,
        gutter: arg(&args, 4) as f32,
        controls_h: arg(&args, 5) as f32,
        traffic_w: arg(&args, 6) as f32,
        traffic_h: arg(&args, 7) as f32,
        probe_w: arg(&args, 8) as f32,
        probe_h: arg(&args, 9) as f32,
        top_edge: arg(&args, 10) as f32,
        header_actions_w: arg(&args, 11) as f32,
    };
    println!(
        "  几何（来自 skeleton.slint）: {}x{} header_h={} traffic_w={} traffic_h={} top_edge={} controls_h={}",
        layout.width, layout.height, layout.header_h, layout.traffic_w, layout.traffic_h, layout.top_edge, layout.controls_h
    );

    let idle_short = Duration::from_millis(500);
    let idle_long = Duration::from_millis(3500);

    // ---- DoD 第 3 条：红绿灯热区就是左上 80×32 ----
    check(
        "红绿灯热区宽度 = 80（T-01 DoD）",
        (layout.traffic_w - 80.0).abs() < 0.5,
        &format!("skeleton.slint 的 traffic-w = {}", layout.traffic_w),
    );
    check(
        "红绿灯热区高度 = 32（T-01 DoD）",
        (layout.traffic_h - 32.0).abs() < 0.5,
        &format!("skeleton.slint 的 traffic-h = {}", layout.traffic_h),
    );
    check(
        "热区内 (40,20) 有红绿灯",
        hit::traffic_visible(false, idle_long, 40.0, 20.0, &layout),
        "热区里应当显示",
    );
    check(
        "热区外 (81,31) 没有红绿灯（80 宽以内才算热区）",
        !hit::traffic_visible(false, idle_long, 81.0, 31.0, &layout),
        "指针已经离开 80px 宽的热区，红绿灯仍然显示",
    );
    check(
        "热区外 (40,33) 没有红绿灯（32 高以内才算热区）",
        !hit::traffic_visible(false, idle_long, 40.0, 33.0, &layout),
        "指针在热区下方 1px，红绿灯仍然显示 —— 热区用的是 header 高度而不是 32",
    );
    check(
        "静止 3 秒、指针不在热区 → 红绿灯看不见（默认隐藏）",
        !hit::traffic_visible(false, idle_long, 900.0, 500.0, &layout),
        "默认应当隐藏",
    );
    check(
        "全屏 → 红绿灯一律不显示（CRD-0003 §3）",
        !hit::traffic_visible(true, idle_short, 1.0, 1.0, &layout),
        "全屏不该出现红绿灯",
    );

    // ---- 命中区域：热区外的页头顶部应当算拖窗，不是点红绿灯 ----
    let flags = Flags { header_visible: true, ..Default::default() };
    check(
        "(40,33) 落在页头拖动区而不是红绿灯区",
        hit::region_at(40.0, 33.0, &layout, &flags) == Region::HeaderDrag,
        &format!("实际区域 = {:?}", hit::region_at(40.0, 33.0, &layout, &flags)),
    );
    check(
        "(40,20) 落在红绿灯区",
        hit::region_at(40.0, 20.0, &layout, &flags) == Region::Traffic,
        &format!("实际区域 = {:?}", hit::region_at(40.0, 20.0, &layout, &flags)),
    );
    check(
        "页头空白处算拖窗（按到按钮上不拖）",
        hit::region_at(layout.width / 2.0, 10.0, &layout, &flags) == Region::HeaderDrag,
        "中间应当是拖动区",
    );
    check(
        "页头最右是按钮区（交给 Slint）",
        hit::region_at(layout.width - 20.0, 10.0, &layout, &flags) == Region::HeaderActions,
        "右侧应当是按钮区",
    );

    // ---- DoD 第 4 条：页头显隐 ----
    check("窗口化时页头常显", hit::header_visible(true, false, idle_long, false), "窗口化必须常显");
    check("暂停时页头常显（全屏也算）", hit::header_visible(false, true, idle_long, false), "暂停必须常显");
    check(
        "播放中 + 全屏 + 静止 3.5 秒 → 页头淡出",
        !hit::header_visible(true, true, idle_long, false),
        "该隐藏时仍然显示",
    );
    check(
        "播放中 + 全屏 + 指针在画面里动过（0.5 秒前）→ 页头在",
        hit::header_visible(true, true, idle_short, false),
        "动指针该唤出页头",
    );
    check(
        "播放中 + 全屏 + 指针在顶部 8px → 页头在",
        hit::header_visible(true, true, idle_long, true),
        "指针到屏幕顶部 8px 该唤出页头",
    );

    // ---- DoD 第 5 条：控制条 3 秒无操作自动隐藏 ----
    check("控制条 2.9 秒内有操作 → 显示", hit::controls_visible(Duration::from_millis(2900)), "不该提前收");
    check("控制条 3.0 秒 → 收起", !hit::controls_visible(Duration::from_millis(3000)), "3 秒应当收起");
    check("控制条 3.1 秒 → 收起", !hit::controls_visible(Duration::from_millis(3100)), "应当收起");

    // ---- 静止阈值就是 3 秒 ----
    check(
        "静止阈值 IDLE_HIDE = 3000ms（DoD 的「3 秒」）",
        hit::IDLE_HIDE == Duration::from_millis(3000),
        &format!("实际 = {:?}", hit::IDLE_HIDE),
    );

    unsafe {
        if FAILED == 0 {
            println!("\ncase-05: 全部通过");
        } else {
            println!("\ncase-05: 失败 {n} 项", n = { FAILED });
            std::process::exit(1);
        }
    }
}
