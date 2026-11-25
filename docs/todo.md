# 待办总表（问题 1–9 的悬而未决项）

> 派生视图：真相在 `docs/improvements.md`（每条九步记录）与 git 历史。
> 这里只回答一个问题：**现在还有哪些没落地，卡在谁身上。**
> 更新：2026-11-25 · HEAD `723bec4` · 工作区干净

## 一、九条问题的状态

| # | 状态 | 落地位置 |
|---|---|---|
| 1 文案收敛 | done | `c0b070e` |
| 2 片源撤出导航 | done | `c0b070e` |
| 3 精彩帧回得去 | done | `c678270` |
| 4 小映做成浮窗 | done | `723bec4` |
| 5 播放暂停键在画面上 | done | `75debe6` |
| 6 频谱 + 进度条 | done | `ea380d7` |
| 7 上滑调音量/亮度 | done | `dcf3ae0` |
| 8 画中画 / 后台播放 | **doing**（代码完工，等真机确认） | `f56f036` |
| 9 六款画风 | done | `eeda1e8` |

## 二、等你一句话

- [ ] 推送 / 打 tag：本地已提交 10 刀，**一个都没 push**。push 与 tag 各需要单独一次点头。

## 三、等外部确认（我改不到）

- [ ] **T3 iOS 真机验 PiP**：真机点「系统画中画」。失败就看 Console 过滤 `SeeWow`，抓 `pip unsupported:` / `pip timeout: status=… possible=…` / `pip audio session failed:` 三行之一回来。模拟器永远不行。
- [ ] **T4 亮度灵敏度手感**：现在「一屏高 = 100%」。真机觉得太钝/太灵，改 `player_screen.dart` 里 `-delta.dy / _height` 的系数。
- [ ] **T5 六款画风的数值**：按取样板调的；真片肤色要微调就改 `video_look.dart` 里对应 `grade(...)` 的数字。

## 四、判断为不做的（记账，不是遗漏）

- 整条时间轴的频谱图（SoundCloud 式）：要扫完整轨，2 小时的片 ≈ 900+ 次采样，只适合短音频 + 落盘缓存。
- 桌面系统 PiP：macOS 只把 AVKit PiP 给 `AVPlayerLayer`，任意播放器做不到；置顶小窗就是终态。
- iOS PiP 播带认证头的网络流：只能本机文件或本地代理（原生会明确拒绝）。
- 动画风的描边与色块化：4×5 矩阵 + 叠层做不到，要上 shader。
- 问题 1 遗留的「功能解释类文案」（Agent 卡 3 行规则、设置页副标题、空态长文案）：删前需确认。

## 五、技术债

- [ ] **T6 `custom_metadata*` 并发卡死 —— 已降级**：`CI` 本来就跑 `flutter test --concurrency=1`（`.github/workflows/flutter.yml:73`），所以发布流水线不会撞；只有本机默认并发会。两次复现（+526、+558 处日志零增长），单独跑 14–28 秒 22 passed。
  - 本机建议：`flutter test --concurrency=1`，或分批跑；若要根治，再按「拆文件 / 改共享 fake」两条路查。
  - 结论：不是发布阻塞，是开发体验问题 → P2。

