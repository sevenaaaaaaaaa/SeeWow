//! 编译 Slint 组件（M1 只有 app.slint 一个根文件 + 它 import 的两个）。
//!
//! 根文件只放 import（HLD §3.3）；其它 .slint 由各自所有者在自己的任务里追加 import。

fn main() {
    println!("cargo:rerun-if-changed=ui/app.slint");
    println!("cargo:rerun-if-changed=ui/skeleton.slint");
    println!("cargo:rerun-if-changed=ui/probe_panel.slint");

    slint_build::compile("ui/app.slint").expect("Slint 组件编译失败（crates/ui/ui/app.slint）");
}
