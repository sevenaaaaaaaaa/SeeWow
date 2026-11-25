# 改进建议账本

> 单一真相源。一条建议一行，状态单向推进，不回滚。
> 状态：`queued`（已登记未定级）→ `graded`（定级待开工）→ `doing` → `verify`（待验证）→ `done` / `dropped`（附理由）/ `blocked`（附原因，等用户）
> 铁律：Done 判据必须机器可判（命令 / 文件 / 数字）；每条带「不做清单」；证据写真实输出，不写「应该没问题」。

## 协议：每条建议的固定九步（灵魂卡第五节）

0. **复述 + 判据**：用用户的原话复述需求一句；写可观察、可复现的 Done 判据；写不做清单。
1. **定级**：P0 / P1 / P2（判据见下表），定级决定后面花多少力气。
2. **侦查**：先找已有实现与真实文件。证据分级 A（本机实测/文件原文/git）/ B（官方文档，注版本日期）/ C（推断，写推理链）/ D（记忆与常识，只能决定去哪查）。
3. **建模**：涉及代码时写清边界、数据流、现有实现、失败模式。四五行，不写小说。
4. **方案**：P0 必须 ≥2 个并比成本/风险/回滚/演化；P1 一次验证即可；P2 直接做。
5. **todo**：每项对应一个可验证产物；同一时刻只有一个 in_progress。
6. **执行**：一次只改一件事，改完即验，通过再动下一处。
7. **验证**：跑命令、看退出码与产物；留一条别人能重跑的验证命令。
8. **汇报**：真实数字 + 未做项与原因 + 下次入口。

## 防跑飞五条（loop-design-check 的五个崩法，对着自查）

1. **目标可判定**：退出条件机器能判 yes/no，否则先改目标再动手。
2. **验证方独立于被验方**：证据用外部事实（构建、测试、真实运行、截图、数字），不用「看着对」。
3. **每条带边界**：写明不做什么——不删/不改测试、不改范围外文件、不动发布链与版本号。
4. **澄清前置**：开工前一次问清，不指望中途再问（中途我不会停下来问）。
5. **账本单一真相源**：状态只前进，收尾必更新，不留口头结论。

## 定级表

| 级别 | 判据（一句） | 流程重量 | 禁止 |
|---|---|---|---|
| P0 | 错了会丢数据 / 花钱 / 发布事故 / 对外契约破裂，且难回滚 | 建模 + ≥2 方案 + 回滚路径 + 可重跑验证 + 边界用例 | 直接开干、说「应该没问题」 |
| P1 | 错了代价是返工一次，用户看得见但能修 | 一次验证 + 留一条复跑命令 | 写方案对比、写设计文档 |
| P2 | 错了只是不好看或不合口味，随时能改 | 直接做，一次通过 | 反复确认、二次美化、问「这样可以吗」 |

## 只会在这三种情况停下来问用户

1. 不可逆且影响用户 / 钱 / 数据（删库、发版、改对外契约、动别人账号）。
2. 用户的口味与边界——事实不在文件里，只能问。
3. 两条路代价相当且都不可逆，判不出哪条更不后悔。

其余一律自己决定，并写明「我定了 X，理由是 Y，不同意就说」。

## 登记表

| # | 日期 | 建议（用户原话摘要） | 定级 | Done 判据 | 不做清单 | 状态 | 证据 / 产物 |
|---|---|---|---|---|---|---|---|
| 1 | 2026-11-25 | 「界面上的说明文字太多，占大量空间」 | P1 | 8 处页面顶部说明块删除或压缩；`flutter analyze` 0 error；全量测试绿；截图可见首屏内容上移 | 不改卡片功能、不改文案含义、不动发布链 | done | `trim-2026-11-25-*.png`；test 534 passed / 2 skipped |
| 2 | 2026-11-25 | 「片源管理不用单独拿出来，放全局右上角」 | P1 | 导航里没有「片源」席；窄屏顶栏有片源入口、一点直达；宽屏保留「连接片源」；测试绿 | 不改片源页内容、不动其他导航席、不改宽屏已有入口 | done | `trim-2026-11-25-sources.png`；test 534 passed / 2 skipped |
| 3 | 2026-11-25 | 「精彩帧收藏后看不到在哪，也不能回到播放进度」 | P1 | 片库首格有「精彩帧」入口；收藏成功提示带「查看」；列表每条可「播放这一帧」并带到该秒；测试绿 | 不改数据格式、不改播放器内「本片精彩帧」、不新增独立页面 | done | `frames-2026-11-25-library.png`；test 535 passed / 2 skipped |
| 4 | 2026-11-25 | 「播放界面里最想直接用的 agent 不行；陪伴的宠物应该做成浮窗」 | P1 | 点开后影片不暂停；浮窗可拖动、可收成头像球、点球能再展开；收起不掐断会话；测试绿 | 不改 AI 协议 / 密钥 / 提示词；不做跨页面全局浮层 | done | `companion_dock.dart`；2 tests；561 passed / 2 skipped |
| 5 | 2026-11-25 | 「播放和暂停按键应该放在播放界面，而不是播放控件上」 | P1 | 画面中央就有播放/暂停键；播放中淡至 0.26、暂停满不透明；点击回调 _togglePlay；测试能被改坏 | 不删控件条里那个按钮；不改单击手势（仍是切控件条）；不动播放内核 | done | lib/playback/play_pause_orb.dart；538 passed / 2 skipped |
| 6 | 2026-11-25 | 「最希望有音频频谱和进度条结合的功能，一直做不出来」 | P1 | 进度条游标显示真分频能量（1024 点 FFT、16 段对数）；拿不到频段退回白点；测试能被改坏；analyze 0 error / 0 warning；全量绿 | 不改播放内核；不动 console 里的旧电平表；不引入第三方 FFT；不做整条时间轴频谱图 | done | spectrum-2026-11-25-scrubber.png；9 tests；547 passed / 2 skipped |
| 7 | 2026-11-25 | 「上滑调节音量和明亮度没有做」 | P1 | 左半边上滑调亮度、右半边调音量（上滑为加）；竖向滑动不跳进度；HUD 显示百分比；锁定不响应；测试能被改坏；analyze 0 error / 0 warning；全量绿 | 不改系统亮度、不引入亮度插件；不改音量的敏感内容与耳机规则；不动横向 seek / 长按倍速 / 双击静音 | done | 4 条手势测试；551 passed / 2 skipped |
| 8 | 2026-11-25 | 「怎么实现画中画和后台播放，现在我测试 iOS 端没办法实现」 | P1 | 真机上点 PiP 能起小窗；失败时 Console 有可定位日志；模拟器构建通过 | 不改 Android/桌面实现；不改 Dart 侧交接协议；不引入新依赖 | doing（待真机确认） | `AppDelegate.swift:125/154/181/213`；`flutter build ios --simulator` EXIT=0 |
| 9 | 2026-11-25 | 「lut 中增加冷白、粉白、国漫风、日漫风、美漫风、今敏风」 | P1 | 六款画风出现在画风条里；矩阵合法、互不重复、各自行为符合定义；测试能被改坏；全量绿 | 不改既有八款；不引入 3D LUT 文件或新依赖 | done | look-2026-11-25-sheet.png；7 tests；559 passed / 2 skipped |

## 逐条记录

### 1. 页面顶部说明文字占空间（P1，done）

- **复述**：每个页面顶部都有「英文小标签 + 30px 标语 + 一行说明」，首屏被文字吃掉，内容要往下滚才看得到。
- **判据**：8 处 `PageIntro` 全部瘦身；`flutter analyze` 0 error；`flutter test` 全绿；截图首屏内容上移 ≥100px。
- **不做清单**：不改任何按钮功能；不改卡片副标题（功能解释）；不动发布链与版本号。
- **定级理由**：视觉改动、可回退、用户直接看见 → P1；一次验证即可。
- **侦查（A 级）**：`grep PageIntro` 命中 8 处；组件定义 `cinema_widgets.dart:46`，结构为 eyebrow(10px) + 12 + title(30px) + 8 + description(13px)，手机端约 100–120px；AppBar 已有页名（`app_shell.dart:154`），页内标题与它重复。
- **方案**：
  - A. PageIntro 瘦身为「可选 22px 标题 + 可选说明 + action」一行，eyebrow 与营销句删除 —— **选它**（切掉说明而不动布局骨架，可逆）。
  - B. 整块删除、按钮下沉内容区 —— 省更多，但要重排 5 个按钮，视觉可能显空，风险中。
  - C. 首次显示、之后折叠 —— 引入状态与动画，收益递减，不选。
- **执行**：
  - `design/cinema_widgets.dart`：PageIntro 去掉 eyebrow，title 30→22，description 变可选。
  - `home_view.dart`：三件套 + 提示行合并为一行（提示 + 调整口味按钮）。
  - `settings_view.dart` / `sources_view.dart`：整块删除。
  - `short_drama_view.dart` / `agent_view.dart` / `library_view.dart`（2 处）：只留 action 或真实内容（片单名、统计）。
- **验证**：`flutter analyze` → 468 info / 0 warning / 0 error（与基线同级，无新增 error）；`flutter test` → 534 passed, 2 skipped；`flutter test test/design_shots_test.dart` 出 5 张图。
- **省下空间**：首页 ≈180px→40px；片源页 ≈120px→0；Agent ≈130px→44px；媒体库 ≈100px→70px（统计保留）。
- **未做（待定）**：Agent 卡内 3 行规则说明、设置页每项副标题、空态长文案——属"功能解释"，删前需用户确认。

### 2. 片源管理从导航移到全局右上角（P1，done）

- **复述**：片源是配置不是内容，不该占底部导航一席；改到顶栏右上角常驻。
- **判据**：底部导航无「片源」席；窄屏顶栏能一点进片源页；宽屏保留原「连接片源」；全量测试绿。
- **不做清单**：不改片源页内容与文案；不动其余导航席的语义；不改宽屏入口。
- **定级理由**：导航结构调整、可回退、用户直接看见 → P1。
- **侦查（A 级）**：`app_shell.dart:58` 目的地表 10 项；底部 5 席映射 `[home, library, agent, sources]` + 第五席溢出表；第五席默认站 online；宽屏 (≥760) 顶栏本来就有「连接片源」OutlinedButton。
- **方案**：
  - A. 撤出导航席 → 顶栏加 hub 图标（<760），空出的第 4 席给「在线源」—— **选它**（在线源原本就靠第五席直达，不能退回「更多」，否则重演 1.21.2 的「装了看不到」）。
  - B. 只删席位不加顶栏 —— 用户无路可进，否决。
  - C. 塞回「更多」菜单 —— 与 1.21.2 的修复方向相反，否决。
- **执行（`app_shell.dart`）**：
  - `_overflowMeta`：加入 `Section.sources`，移除 `Section.online`；`_overflowSeat` 默认改 `shortDramas`。
  - `_navIndex`：`online => 3`；`_navSelect` 第 4 席映射改 `online`；第 4 个 `LiquidTab` 标签改「在线源」。
  - 顶栏：`if (width < 760 && _section != Section.sources)` 加 `IconButton(tooltip: '片源与订阅')`，`visualDensity: compact`。
  - 第五席标签跟随当前 section：站在溢出分区上就写它自己的名字。
- **测试改动（行为变更，不是放宽断言）**：
  - `online_entry_test.dart`：断言的座位从「第五席」改为「常驻席」，并新增「导航里没有片源」；点一下直达在线源的意图断言原样保留。
  - `design_shots_test.dart`：截图入口从点导航「片源」改为点顶栏 tooltip；第五席截图前先回首页。
- **验证**：第一次跑红 2 个（375 宽顶栏溢出 2px；全量并发下宽屏 3px），加 `compact` 与间距余量后 `flutter analyze` 0 error / 0 warning，`flutter test` 534 passed / 2 skipped / 0 failed（2 分 05 秒）。
- **未做**：片源页标题仍叫「片源与订阅」；宽屏入口文案仍是「连接片源」。

### 3. 精彩帧：找不到入口 + 回不到进度（P1，done）

- **复述**：在播放器里收藏了画面，之后不知道去哪个页面找；就算在列表里看到了，也只能看大图，回不到影片的那个瞬间。
- **判据**：片库筛选条第一格有「精彩帧」；收藏成功后提示里能直接点「查看」；列表每条有「播放这一帧」，点了打开所属影片并从该秒开始；全量测试绿。
- **不做清单**：不改帧索引格式（index.json）；不改播放器内「本片精彩帧」的既有行为；不新建独立路由页。
- **定级理由**：功能可用性缺陷、可回退、用户直接感知 → P1。
- **侦查（A 级）**：
  - 入口只有 `settings_view.dart:212` 一处，且 `showFrameBookmarks(context)` 没传 `onSelect`。
  - `player_screen.dart:519` 的 `_showFrames` 传了 `onSelect → _seekTo`，所以"回进度"在播放器内本来就通，只是播放器外没有。
  - `PlayerScreen` 有 `startAt`（`player_screen.dart:51`），`_playLive` 却没有把它透出来。
  - `FrameBookmark` 已存 `itemId` 与 `seconds`，数据够用，不需要迁移。
- **方案**：
  - A. 补三处：库页入口 + 收藏提示带「查看」+ `_playLive(startAt)` 打通 —— **选它**（每处都是缺口本身，不动数据与路由）。
  - B. 只加入口不改跳转 —— 用户能看见却回不去，只修一半。
  - C. 新建独立页面 + 侧栏入口 —— 为一个列表开页面，成本高，且与设置里已有入口重复。
- **执行**：
  - `frame_bookmarks_view.dart`：`showFrameBookmarks` 增 `onOpen`，条目增「播放这一帧」。
  - `player_screen.dart`：`_message` 支持 `SnackBarAction`；收藏成功给「查看」。
  - `library_view.dart`：筛选条第一格「精彩帧」（null 时不渲染，音乐库不受影响）。
  - `settings_view.dart`：透传 `onOpenFrame`。
  - `app_shell.dart`：`_playLive` 增 `startAt`；新增 `_openFrame`（找不到影片就直说）；库页与设置接上。
- **验证**：
  - `flutter analyze`：468 issues / 0 error / 0 warning（与基线一致）。
  - 新增 `test/frame_bookmarks_flow_test.dart`：内存替身驱动列表，断言「播放这一帧」回调带回 `itemId=dune2` 与 `seconds=1793.25`，且选完列表关闭。
  - 全量分两批：522 passed / 2 skipped（除 `custom_metadata_test`）+ 13 passed（该文件单独跑）= **535 passed / 2 skipped / 0 failed**。
  - 一次整跑时 `custom_metadata_test` 在并发下卡在第 526 例两轮零增长，单独跑 1 秒全过——既有并发脆弱，与本次改动无关，已记录。
- **未做**：列表没有批量导出/分享；帧还在，但影片被移出片库时只提示不清理（保留用户数据）。

### 4. 播放器里的 agent 能力用不了；小映应该是浮窗（P1，blocked）

- **复述**：在播放器里，我最想直接用的 agent 能力用不上；陪伴的宠物（小映）应该做成浮窗。
- **判据（形态定了才生效）**：点开小映时影片不暂停；浮窗可拖动、可收成头像球、点球能再展开；收起不再 stop() 掐断回答；flutter analyze 0 error / 0 warning；全量绿。
- **不做清单**：不改 AI 协议、密钥与配置存储、系统提示词里的小映人格；不做跨页面全局 Overlay；不动字幕渲染。
- **定级理由**：交互形态调整、可回退、每次看片都会碰到 → P1。
- **侦查（A 级）**：
  - player_screen.dart:827 打开面板先 await _player.pause()，:852 关闭才恢复。
  - :832–839 用 showModalBottomSheet + height: .86，盖住 86% 屏高。
  - :849 关闭时 _watchAi.stop() → watch_ai_controller.dart:228 client.cancel()，正在生成的回答当场断。
  - 入口是 :1792 的 face 图标；未配置时只弹一句「AI 陪看尚未配置」（:707）。
  - 面板正文是 Expanded + ListView（watch_ai_view.dart:415），塞进小尺寸浮窗不需要重写内容。
- **方案**：
  - A. 播放器内浮窗（右下、可拖动、收起成 56px 头像球），影片不停，收起不 stop —— 推荐。
  - B. 只去掉 pause()、保留底部大面板 —— 半屏仍被盖，等于没解决。
  - C. 全局 Overlay 常驻宠物（跨页面）—— 范围大一个量级，先不做。
- **执行**：新增 `lib/playback/companion_dock.dart`（Positioned 卡片：抓手拖动、安全区与键盘内夹紧、收起成 56px 气泡、生成中显示状态点）；`player_screen.dart` 用浮窗替换 `showModalBottomSheet`，去掉 `pause()` 与关闭时的 `stop()`；`watch_ai_view.dart` 增 `onCollapse`/`onClose`，让面板的「收起」与 Esc 不再 pop 播放器路由。
- **验证（实跑）**：flutter analyze 467 issues / 0 error / 0 warning；新增 `test/companion_dock_test.dart` 2 passed（抓手拖动、越界夹紧、气泡展开、收起/关闭回调、无回调时不摆关闭按钮）；全量 539 passed / 2 skipped（其余）+ 22 passed（`custom_metadata*` 单独跑）= **561 passed / 2 skipped / 0 failed**。
- **未做**：不做跨页面全局浮层（要一层全局 Overlay）；浮窗位置不持久（每次进播放器回默认右下）。

### 5. 播放／暂停键长在画面上（P1，done）

- **复述**：播放和暂停的按键应该在播放界面（画面）上，而不是只在播放控件条里。
- **判据**：画面中央常驻播放/暂停键；播放中淡至 0.26，暂停时满不透明；点击调用 _togglePlay；测试能被改坏（红过）；analyze 0 error / 0 warning；全量绿。
- **不做清单**：不删控件条里那个小按钮；不改单击画面的含义（仍是显示／隐藏控件条）；不动播放内核与手势（长按倍速、横向拖动调进度）。
- **定级理由**：纯 chrome 改动、可回退、每看一次片都会用到 → P1。
- **侦查（A 级）**：PlaybackGestures.onTap（player_screen.dart:1262）只切控件条显隐；暂停只有控件条底部那个 44px 图标（:1958–1962）；画面中央原本只在暂停时才有一个 76px 播放键，且被 AnimatedScale(0.001) 收掉（:1587–1612），所以「播放中」画面里根本没有暂停键。
- **方案**：
  - A. 中央按钮改为真控件：播放中即显示暂停键、淡至 0.26，暂停时满不透明 —— 选它（控件在画面上，且不新增常驻边框）。
  - B. 单击画面直接播放/暂停 —— 与「单击显隐控件条」冲突，会拿走现有的隐藏方式。
  - C. 顶栏常驻小按钮 —— 仍是角落小图标，不解决「按不到」直觉。
- **执行**：新建 lib/playback/play_pause_orb.dart（PlayPauseOrb，复用 Pressable：按钮语义、Enter/Space、减弱动态效果）；player_screen.dart 用 Center(child: PlayPauseOrb(...)) 替换原 AnimatedScale 块（+14 / −26）。
- **验证（实跑）**：
  - flutter analyze → 468 issues / 0 error / 0 warning（与基线同数，无新增）。
  - 新增 test/play_pause_orb_test.dart → 3 passed（暂停键 + 回调、播放键 + 不透明、tooltip 随状态切换）。
  - 证明测试会红：opacity 改成恒 1 → 该条失败；图标改成恒播放键 → 该条失败；两次都已还原（restored: true）。
  - flutter test → 538 passed / 2 skipped / 0 failed（1 分 40 秒，EXIT=0）。
- **未做**：播放器没有截图通道，这次没有新图；控件条底部那个按钮保留（两处调同一个 _togglePlay）；画中画迷你条未改。

### 6. 音频频谱和进度条结合（P1，done）

- **复述**：最希望有一个「音频频谱 + 进度条」结合的功能，一直做不出来。
- **判据**：进度条游标显示真实分频能量（FFT，不是单一电平塑形）；拿不到频段时退回白点且拖动不变；测试能被改坏；analyze 0 error / 0 warning；全量绿；出一张可看的图。
- **不做清单**：不改播放内核与解码参数；不动 console 里那台旧电平表；不引入第三方 FFT 依赖；不做整条时间轴的频谱图。
- **定级理由**：新增渲染但纯读、可回退、用户点名最想要 → P1。
- **侦查（A 级）——「做不出来」的三个真原因**：
  1. 原来那台「频谱」不是频谱：SpectrumShape.bands（player_console.dart:11–27）拿单一 RMS 标量按固定斜率摊成条，注释自己写着「不是频率分析，也不假装是」——只有一格数据，怎么调样式都不像频谱。
  2. 它长在播放器控制台面板里（player_screen.dart:1866–1878，且受 _prefs.meter 控制），从来没长在进度条上，所以「结合」这件事没发生过。
  3. 缺的不是画，是分析：PCM 其实已经在手上——AudioCapture.capture（audio_capture.dart:109 起）用第二个 mpv 实例 ao=pcm 落盘 16 kHz 单声道 WAV，AudioLevel 每 4 秒一个窗口、100 ms 采一次；只差对这帧数据做 FFT。
- **方案**：
  - A. 游标上做真频谱：当前窗口 1024 点 Hann + 迭代 radix-2 FFT，55–7000 Hz 对数 16 段、段内取峰值、-60 dB 归一化 —— 选它（复用已有 PCM，零新增解码、零新增依赖）。
  - B. 整条时间轴频谱图（SoundCloud 那种）：要扫完整轨，一次采样 ≤8 s、每次起一个解码器（1–2 s），2 分钟歌 ≈ 15–20 次、2 小时片 ≈ 900+ 次 → 只能给短音频做且必须落盘缓存，成本高一个量级，本轮不做。
  - C. 继续把 RMS 塑形成更好看的条 —— 不是频谱，用户的原话已经否掉这条路。
- **执行**：新增 lib/playback/spectrum_analysis.dart（分析）、lib/playback/spectrum_thumb.dart（游标）；audio_level.dart 增 bands（同一帧 PCM 顺手算）；player_screen.dart 的 _scrubber 换游标并把行高 16→32（否则 28px 游标被 Stack 裁掉）。
- **验证（实跑）**：
  - flutter analyze：467 issues / 0 error / 0 warning（基线 468，少一条——顺手给 audio_level 的 if 补了花括号）。
  - 新增 3 个测试文件共 9 passed：分析 5（1 kHz 落第 8–11 段、静音为零、越界为零、幅度单调、段数为零）、游标 3（重采样与夹紧、满能量满高、空频段退回白点）、截图 1。
  - 改坏证明：分析恒 0 → 2 条红；重采样恒 0 → 2 条红；两次都还原（restored: true）。
  - flutter test：547 passed / 2 skipped / 0 failed，EXIT=0（3 分 32 秒）。
- **未做**：只有「此刻」的频谱，没有整条时间轴；译配中走的是译音电平，这条线没接 FFT（退回白点）；暂停没有音频所以也没有频谱；截图只画了进度条本身（播放器是平台视图，整屏截不到）。

### 7. 上滑调音量与亮度（P1，done）

- **复述**：播放器里「上滑调节音量和明亮度」没有做。
- **判据**：左半边上滑调亮度、右半边调音量，上滑为加；竖向滑动不跳进度；有 HUD 显示百分比；锁定时完全不响应；测试能被改坏；analyze 0 error / 0 warning；全量绿。
- **不做清单**：不改系统亮度、不引入亮度插件；不改音量的敏感内容与耳机规则；不动横向 seek、长按倍速、双击静音。
- **定级理由**：新增手势与一层渲染，可回退，用户点名 → P1。
- **侦查（A 级）**：
  1. playback_gestures.dart 的 _move 里竖直方向被显式丢弃（原注释「Vertical gestures never turn into an unexpected seek」，dx.abs() <= dy.abs() 就 return）——所以从来没有竖向手势，不是坏了，是没写。
  2. 全库 grep brightness / 亮度 零命中，pubspec 也没有屏幕亮度插件 → 系统亮度这条路在 Flutter 里本来就改不了。
  3. 音量不是裸字段：_volume = _privacy.effectiveVolume，_changeVolume 里带敏感内容外放保护、耳机确认与落盘。手势必须走它，不能直给播放器。
- **方案**：
  - A. 左亮度 / 右音量（行业惯例）+ 应用内压黑 + 拖动 HUD —— 选它（不新增依赖、不动系统权限）。
  - B. 只做音量 —— 用户点名要亮度，等于只做一半。
  - C. 装 screen_brightness 类插件改真机亮度 —— 新依赖 + 平台权限 + 桌面/移动行为不一，属发布风险，不做。
- **执行**：
  - PlaybackGestures：新增 onVerticalBegin / onVerticalUpdate / onVerticalEnd 与纯函数 verticalValue；16px 阈值后按主轴定边（竖向才开始走竖分支），定了不再改，避免「调音量顺手跳进度」。
  - player_screen：_brightness 压黑层（最多 80%，在画面与控件之间）、HUD 700ms 后收起、音量只在整百分点变化时提交（避免每个 move 事件写盘）、敏感内容屏蔽时不动音量。
- **验证（实跑）**：
  - flutter analyze：467 issues / 0 error / 0 warning（与改动前同数）。
  - test/playback_gestures_test.dart 增 4 条：左半边上滑报亮度（fraction 0.2）、右半边下滑报音量（-0.2）、横向拖动不被抢、锁定不给回调；连同原有的 6 条共 10 passed。原有「vertical swipe rejects seeking」仍绿，竖向依旧不跳进度。
  - 改坏证明：把竖分支写成 `_vertical = false` → 左半边那条当场红；已还原。
  - flutter test：551 passed / 2 skipped / 0 failed，EXIT=0（3 分 27 秒）。
- **未做**：亮度不持久（离开播放器复位 1.0）；没有整屏截图（播放器是平台视图，截不到）；没有真机手感验证（拖动灵敏度 1 屏幕高 = 100%，可能需要按手感再调）。

### 8. iOS 画中画起不来（P1，doing，待真机确认）

- **复述**：画中画与后台播放「怎么实现」——三平台其实都实现了，但用户在 iOS 上试不出来。
- **判据**：真机上点「系统画中画」能起小窗；失败时 Console 有三条定位日志之一；模拟器构建通过。
- **不做清单**：不改 Android 与桌面的实现；不改 Dart 侧的 `pip/background/update` 交接协议；不引入新依赖。
- **定级理由**：平台功能不可用、改动集中在原生一个文件、可回退 → P1。
- **侦查（A 级）——找到的真原因**：
  1. `startPip` 建好 AVPlayer、seek 完就只等 `isPictureInPicturePossible`，**从头到尾没有 `play()`**。AVKit 只从正在播的画面起 PiP，这个标志因此永远不翻转，10 秒后走「画中画准备超时」。而 Dart 在请求前还主动 `pause()` 了主播放器——两边都不在播。
  2. `presenter?.view` 在 scene 架构（Info.plist 有 UISceneManifest + SceneDelegate）下可能不在窗口层级，AVPlayerLayer 没上屏 → 同样等不到 possible。
  3. 请求 PiP 时不立音频会话：只有开「后台播放」才 `setCategory/setActive`，其余情况 PiP 可能没声或起不来。
- **执行**：`hostView` 退化到 key window（:125）；`startPip` 里立音频会话（:154）；seek 完后 `isMuted = true` + `play()` 再观察 possible（:181）；`didStart` 放开声音并回到用户原本的播放/暂停（:213）；补三条 NSLog 供真机排查。
- **验证**：`swiftc -parse` 通过；`flutter build ios --simulator --debug` 成功（96.5s，EXIT=0）。**PiP 本身在模拟器上不可能验**，真机确认待用户。
- **未做**：iOS PiP 仍只接受本机文件或可代理的地址（认证头那条限制没动）；PiP 里依旧没有 AI 字幕/译配。

### 9. 画风：冷白、粉白、国漫、日漫、美漫、今敏（P1，done）

- **复述**：在 LUT（画风）里增加冷白（白皙）、粉白（粉里透红、白皙）、国漫风、日漫风、美漫风、今敏风。
- **判据**：六款出现在画风条里；每张矩阵合法；互不重复（取样板上最大通道差 > 14）；冷白更亮更冷、粉白更亮更红、美漫压黑；中灰不被染彩；测试能被改坏；全量绿；出一张对照图。
- **不做清单**：不改既有八款；不引入 3D LUT 文件、不新增依赖；不动播放器里的画风切换动效。
- **定级理由**：纯矩阵数据 + 一个可选参数，可回退、用户直接看得见 → P1。
- **侦查（A 级）**：画风 = 4x5 颜色矩阵 + 可选叠层（`video_look.dart:19`）；`grade(contrast, sat, tint, lift)` 只能做全局对比/饱和/染色/偏置（`:148`）；`LookChipBar` 直接遍历 `VideoLook.presets`（`player_console.dart:289`），所以加进 presets 就出现在条上。
- **方案**：
  - A. 给 `grade` 加可选 3x3 通道串扰（mix），用它把三种动画分开 —— **选它**（仍然是纯矩阵，不破坏既有八款）。
  - B. 只调对比/饱和 —— 三款动画会变成换皮：实测「国漫 vs 日漫」最大通道差只有 8.6。
  - C. 引 3D LUT 贴图 —— 要新依赖 + 贴图管线，收益不等于成本。
- **执行**：`grade` 增 `mix`（先串扰、再对比/饱和/染色）；新增六款：冷白 `coolwhite`、粉白 `pinkwhite`、国漫 `guoman`（奶白黑位 + 青玉阴影）、日漫 `riiman`（饱和 + 冷高光）、美漫 `meiman`（压死黑 + 凶原色 + 晕影）、今敏 `kon`（洋红影子 + 高对比 + 轻颗粒）。
- **调参依据（不是拍脑袋）**：国漫最初 sat 1.30 与日漫太像（8.6），改成 sat 1.14 + lift .045（奶白）后差异升到 30.8；全体最差一对（冷白 vs 国漫）15.2，刚好过线。
- **验证（实跑）**：
  - flutter analyze：467 issues / 0 error / 0 warning（与改动前同数）。
  - 新增 `test/video_look_grade_test.dart` 7 passed（矩阵合法/原色恒等/取样板互不重复/冷白冷暖/中灰不染彩/美漫压黑/未知 id 退回原色）；`test/look_sheet_test.dart` 1 passed，出 `look-2026-11-25-sheet.png`（1800×840，32846 bytes）。
  - 既有 `test/video_look_test.dart` 的「八款」断言改成 14 —— 这次真的加了六款，属行为变更，不是放宽断言。
  - 全量：一次整跑在 +558 处并发卡死（日志 100 秒零增长，第 2 次撞到同一个点），分两批得 537 passed / 2 skipped / 0 failed（其余文件，3 分 29 秒）+ 22 passed（`custom_metadata*` 两个文件单独跑，14 秒）= **559 passed / 2 skipped / 0 failed**。
- **未做**：国漫/日漫/美漫/今敏是「颜色 + 叠层」的分级，做不出真动画的描边与色块化；今敏那款取的是他常见的洋红/高对比色彩气质，不是对某一部片的逐帧匹配。
