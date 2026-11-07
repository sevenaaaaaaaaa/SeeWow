# T-01 · QA 用例（走通骨架：mpv 自持窗口 + Slint 透明叠层 + HDR 探针）

对应任务：`docs/tasks/tasks.md` 的 **T-01**；HDR 口径：**ADR-0010 v3** + **PRD v2 §10 的更正**。

## 怎么跑

```sh
bash qa/T-01/run-all.sh          # 全部用例；blocked / 手工待做 不算失败
bash qa/T-01/case-05-chrome-geometry.sh   # 单条
SEEWOW_QA_REBUILD=1 bash qa/T-01/case-01-bundle.sh   # 顺带重新打包
```

需要：本机 Rust 工具链、Homebrew 的 libmpv（`/opt/homebrew/lib`）、`python3`、`ffmpeg`（只有重新生成样片才需要）。
样片在 `fixtures/`，重新生成用 `fixtures/gen-fixtures.sh`。

## 用例与 DoD 的对应

| 用例 | 覆盖的 DoD | 自动化 |
|---|---|---|
| case-01-bundle | 能双击启动的物质前提：包结构 / libmpv 进包 / ad-hoc 签名 | 是 |
| case-02-cargo-tests | DoD 指定的 `cargo test` 命令 | 是 |
| case-03-clippy | DoD 指定的静态检查 | 是 |
| case-04-probe-adr | 探针判定必须按 ADR-0010 v3 算（含 SDR 屏口径「管线已通、未上屏」） | 是（纯函数） |
| case-05-chrome-geometry | 红绿灯 80×32 热区、页头 3 秒/8px 规则、控制条 3 秒、220ms | 是（纯函数 + slint 几何） |
| case-06-lifecycle | 启动→播放→全屏进/出→关闭→进程消失；日志有开始与结束；无系统标题栏/透明壳 | 是（vo=null） |
| case-07-probe-log | 面板背后的四类数值 + 两个布尔 + 证据来源真的采到了 | 是（日志） |
| case-08-mpv-options | mpv 选项回归（Q-02：force-window 必须不在） | 是（静态） |
| case-09-pixel-format-labels | 面板 pixfmt 名字与 Metal SDK 定义一致（证据不谎报） | 是 |
| case-10-manual-shell | DoD 1/2：无系统标题栏、无白底闪屏、画面区播放 | 手工 |
| case-11-manual-hdr-panel | DoD 6：面板读数 pipeline_hdr=true / on_screen_hdr=false / headroom 1.0 | 手工 |
| case-12-manual-chrome | DoD 3/4/5：红绿灯热区、页头淡出淡入、控制条暂停 | 手工 |
| case-13-manual-fullscreen | DoD 7：全屏进出、第二块屏/拔屏 | 手工 |

## 已知环境限制（为什么四条是 blocked）

本机 GUI 会话锁屏（`CGSSessionScreenIsLocked=1`）：`vo=gpu/gpu-next` 拿不到 drawable，卡在 `swapBuffer`；
`screencapture` 报 `could not create image from display`。**画面类用例一律记 blocked，不记失败**（证据见 Q-02）。
自动化的部分用 `SEEWOW_MPV_VO=null`（关掉视频输出，其余路径照跑）与纯函数 / 日志口径覆盖。

## 解锁屏幕后的手工步骤

统一准备：

1. 解锁并让屏幕保持唤醒：`caffeinate -d &`。
2. 确认显示输出正常：`screencapture -x /tmp/t.png && ls -l /tmp/t.png`（应得到一个非空 PNG）。
3. 截图目录：`mkdir -p qa/T-01/evidence`，文件名用 `case-NN-步骤号.png`。
4. 打开应用（任选其一）：
   - 双击 `apps/seewow-rs/dist/SeeWow.app`；或
   - `open -a apps/seewow-rs/dist/SeeWow.app --args "$PWD/qa/T-01/fixtures/clip-lifecycle.mp4"`

### case-10 · 壳窗口（DoD 1、2）

- 打开 `dist/SeeWow.app`，**不要**给参数：应出现 SeeWow 风格的空壳（序号 + 中文衬线标题 + 等宽大写英文标签 + 右侧动作 + hairline）。
- 看什么：① 顶部**没有**「只有标题 + 三个按钮」的横条；② 内容一直延伸到窗口顶边；③ 启动瞬间**没有白底闪一下**（可录屏后逐帧看）。
- 点「打开文件」，选 `qa/T-01/fixtures/clip-sdr.mp4`：画面区应正常播放。
- 截图：`case-10-1-空壳.png`、`case-10-2-播放中.png`；白屏问题交 `case-10-3-启动瞬间.mov`（`Cmd+Shift+5` 录屏）。

### case-11 · 探针面板（DoD 6）

- 播 `qa/T-01/fixtures/clip-hdr10.mp4`（HDR10、bt2020/PQ；本机 SDR 屏）。
- 点右上的动作按钮打开探针面板，看三块：
  - **MPV** 列：`video-params`（源）与 **`video-target-params`**（目标侧）两组，带单位（`cd/m²`）。
  - **MACOS** 列：`screen`（potentialEDR / currentEDR）、`layer`（pixfmt / wantsEDR / colorspace）。
  - **判定** 列：六条 ✓/✗ + `evidence_source`。
- 本机合格值（PRD v2 §10：**这不是失败**）：
  - `PIPELINE ✓`（`pipeline_hdr = true`）
  - `ON SCREEN ✗`（`on_screen_hdr = false`）
  - `currentEDR 1.000`（headroom = 1.0）
  - `evidence_source 2` 且文字说明「= 管线状态（非像素回读）」
  - 面板 headline 一行写「HDR 管线已通、未上屏」
- 截图：`case-11-1-面板全图.png`（面板与影片同框）。若 `PIPELINE ✗`，把六条里打 ✗ 的那几条也截下来。
- 反证（同一屏）：播 `clip-sdr.mp4`，面板必须显示 `pipeline_hdr = false`（SDR 内容不该被判成 HDR）→ `case-11-2-SDR反证.png`。

### case-12 · 页头 / 红绿灯 / 控制条（DoD 3、4、5）

按顺序做，每步一张图：

1. 播放中，指针移到画面中间静止 3 秒：页头与红绿灯一起淡出（**220ms**，看不出卡顿）→ `case-12-1-淡出.png`。
2. 指针一移动：页头与红绿灯淡入 → `case-12-2-淡入.png`。
3. 按 `Esc`：淡入；再静止 3 秒：淡出。
4. 暂停（空格）：页头常显；恢复播放后 3 秒再淡出。
5. 指针移到屏幕顶部 8px 内：页头淡入。
6. 窗口化（不要全屏）：页头常显（方便拖窗）；把指针放在页头空白处拖动，窗口跟着走；按到右侧按钮上拖不动。
7. **红绿灯热区**：先把指针移开、等 3 秒让红绿灯淡出；再把指针移到窗口左上角 **80×32** 的范围内（约等于三个圆点那一小块）：红绿灯淡入；指针往右移到 x≈100px（超出 80）或往下移到 y≈40px（超出 32）：红绿灯淡出 → `case-12-3-热区内.png` / `case-12-4-热区外.png`。
   > case-05 目前报这条不成立（热区实测为 84×56），这一步请顺手复核：截图里指针在 y=40 时红绿灯是否还亮着。
8. 指针移到底部：控制条出现；点一下 → 暂停（画面停住、按钮变播放）；再点 → 继续；不动 3 秒 → 控制条自动收起 → `case-12-5-控制条.png`。
9. 快捷键兜底：`Cmd+W` 退出、`Cmd+M` 最小化、`Cmd+Ctrl+F` 全屏。

### case-13 · 全屏与换屏（DoD 7）

1. `Cmd+Ctrl+F` 或双击画面区：画面与界面**一起**进全屏，界面不出屏、不闪黑 → `case-13-1-全屏.png`。
2. 再按一次退出全屏，壳层回到窗口化 → `case-13-2-退出全屏.png`。
3. 若有外接屏：播放中把窗口拖到第二块屏上，界面与画面都在第二块屏内，不崩 → `case-13-3-第二块屏.png`。
4. 若没有外接屏：播放中拔掉/接上任意显示器（或系统设置里改分辨率）：不崩，界面回到内置屏 → `case-13-4-换屏后.png`。

## 失败时怎么报

每条失败请带上：`case-xx` 名字、截图/日志路径、期望值与实际值。自动化用例的原始输出在 `.artifacts/`：
`probe-verdict.log`、`workspace-test.log`、`clippy.log`、`lifecycle.log`、`probe.log`、`make-app.log`。
