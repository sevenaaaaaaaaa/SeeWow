# SeeWow 质检与复盘 · 2026-11-17

> 范围：GitHub 仓库（releases / issues / PR / CI）+ 本地代码 `apps/seewow`（Flutter 五端主线）+ `apps/seewow-rs`（Rust 内核线）+ `docs/` 全部规划与发布文档。
> 方法：`gh release view` 全量拉取 18 个 tag 的资产与日期；`git log`/`git tag` 还原节奏；逐文件读资源管理链路（`sources_view.dart`、`library_store.dart`、`local_scanner.dart`、`plex_scanner.dart`）；`flutter test` 实跑。**结论全部附文件行号或命令输出，不写"感觉"。**
> 配套：[docs/release-index.md](../release-index.md)（版本汇总）、[docs/roadmap.md](../roadmap.md)（路线图）。

---

## 0. 三十秒结论

你感觉"发了很多版、功能没改善、bug 没修"——**这是三个结构性缺口叠加的必然结果，不是哪一版不努力**：

1. **缺陷没有入口**：仓库 0 个 issue、0 个 PR。bug 只存在于对话里，换一次会话就归零，所以"上次说过的那条"永远不会被下一版检查。
2. **CI 不跑测试**：`.github/workflows/flutter.yml` 只有 `flutter build`，没有 `flutter test`、没有 `flutter analyze`。CI 全绿只证明"能编译"，不证明"没坏"。1.15 之后三个版本改的是资源入口周边，没有任何自动化拦住回归。
3. **注意力被两条线分掉**：Flutter 五端（用户在用）+ Rust macOS 内核（用户拿不到）。1.17、1.18 两版全部产能落在元数据与构建身份上，**资源管理一行没动**。

结果就是：版本号在走（11 天 17 个版本），用户摸得到的资源管理缺陷一个没修。

---

## 1. 复盘：为什么"发了很多版"不等于"在变好"

| # | 现象 | 机制（为什么必然发生） | 证据 |
| --- | --- | --- | --- |
| 1 | 同一类问题反复出现在发布说明里 | 没有 issue 编号，修复无法被引用、被回归、被验收；下一版只能靠记忆决定做什么 | `gh issue list` 空；`docs/releases` 17 份文档无一条缺陷编号 |
| 2 | 版本号涨、体验没涨 | 发布以"主题"为单位（1.16 手势、1.17 元数据、1.18 版本号），不是以"缺陷清零"为单位。1.18.0 明确写"没有功能变更" | `docs/releases/1.18.0.md` |
| 3 | 修了 A 坏了 B 无人知 | CI 无测试；307 项测试只在本地手动跑，且**没有一条覆盖"加来源→重扫→编辑→断开"整链** | `.github/workflows/flutter.yml`；`test/` 51 个文件逐个核对 |
| 4 | 用户装到旧包 | 17 个 1.x 版本里 15 个标 Pre-release，GitHub Latest 因此仍是 `v1.1.0`（11-09）。首页点 Releases 默认给的是 16 个版本之前的包 | `gh api releases/latest` → `v1.1.0` |
| 5 | 平台越更新越少 | 五端齐全只出现过 2 次（1.1.0、1.17.0）；1.18.0 只有 macOS+iOS；Windows/Linux 在 1.1→1.16 之间断档 12 个版本 | 见 release-index 矩阵 |
| 6 | 规划文档多头 | `docs/plan/` 有 2 份计划、`docs/parity.md` 停在 1.15、无 CHANGELOG、无路线图；Rust 线另有自己的里程碑表 | `ls docs/plan`；`docs/parity.md` 首行"1.15.0 更新" |

**一句话**：过去两周优化的是"发布动作"，不是"产品质量"。版本多，是因为每件事都值得单独发一版；没改善，是因为没有人负责把缺陷清到零。

---

## 2. 资源管理缺陷清单（你点名的那块）

全部在 `apps/seewow` 主线（移动端与桌面端共用同一套代码，所以**这些缺陷两端同时存在**）。严重级：S1 阻塞 / S2 高 / S3 中。

### RM-01 · 断开来源没有二次确认，一点就丢观看进度和收藏（S2）

`lib/features/sources_view.dart:549-558` 的弹出菜单直接把 `remove` 交给 `_remove()`；`_remove()`（同文件 758-761）立刻调用 `removeSource` 并删除凭据。`library_store.dart:175-183` 里 `removeSource` 会 `items.removeWhere((i) => i.sourceId == source.id)`——**条目连同 position（续播点）、isFavorite（收藏）、duration 一起被删除**，只写回 library.json。

- 用户看到的文案是"断开来源（不删除文件）"，容易理解成"只是不再扫描"。
- 误触一次，整库续播点与收藏不可恢复（没有回收站、没有 undo）。
- **修法**：确认弹窗 + 文案改为"断开后将移除该来源的 N 个条目与观看记录"；或先软删除（标记 `removedAt`）保留 7 天。

### RM-02 · 父子目录重叠添加会产生重复条目，且进度只写进其中一条（S2）

- 本地条目 id 由**文件绝对路径**哈希得到：`lib/data/local_scanner.dart:113-117`（`sha1(path)`）。
- `addSource` 只拦截"location + rootPath + kind 完全相同"的重复：`library_store.dart:139-151`。
- 所以先加 `/Movies`、再加 `/Movies/2024`，同一个文件会被扫出两条**同 id、不同 sourceId** 的条目。
- 后果：片库出现重复卡片（`movies` getter 不去重，`library_store.dart:33-35`）；`updatePosition` 用 `indexWhere` 只更新第一条（`library_store.dart:306`），另一条永远停在旧进度；`current()` 又按 id 取第一条（`library_store.dart:65-66`），所以点开重复卡片看到的是另一条的进度；断开其中一个来源只删掉自己那份。
- 现有测试没有覆盖这种重叠（`test/library_intelligence_test.dart`、`test/local_scanner_robust_test.dart` 都没有父子目录用例）。
- **修法**：入库前按"是否为已存在来源的子路径"拦截并提示；或在 `addItems` 层按 id 全局去重并记录多来源归属。

### RM-03 · 来源无法停用：断网 NAS 会拖住每次刷新（S2）

`MediaSource.enabled` 字段存在，`refreshAll` 也遵守它（`library_store.dart:289-298`），`metadata_dialog.dart:432` 同样跳过停用来源——**但没有任何界面能把它设成 false**。新建来源时一律 `enabled: previous?.enabled ?? true`（`sources_view.dart:156`、`1093`）。

- 后果：一个离线的 NAS/SMB 会让每次"刷新片库"都等它超时；用户唯一的办法是删掉来源（连带丢进度，见 RM-01）。
- **修法**：列表项加开关；停用后不参与刷新与刮削，但保留条目与进度。

### RM-04 · Plex 改资料库选择必须重新登录，且登录成功即自动提交+全量重扫（S2）

`sources_view.dart:915-922`：`_plexSignIn` 读完资料库列表后弹选择框，选完立刻 `_connect()`。编辑弹窗里**没有独立入口**"重新选择资料库"，只能再点「使用 Plex 账号登录」走一遍验证码流程；一旦登录成功就立刻保存并触发全库重扫，不能"只改选择不重扫"。

- 后果：只想把 3 个资料库缩到 1 个，要重新拿验证码、重新登录、等一次全库扫描；中途想改主意只能取消整个登录。
- 1.16 计划里写的是"编辑可改"（`docs/plan/v1.16-plan.md:103`），实际路径存在但代价过高。
- **修法**：编辑弹窗对有 token 的来源直接提供「重新选择资料库」按钮（复用已存 token 调 `PlexScanner.sections`），选择结果只走 `updateSource`，不重登录。

### RM-05 · Plex 返回重复 ratingKey 会让整次扫描失败（S3）

`lib/sources/plex_scanner.dart:87-88`：任何一条 item 的 `ratingKey` 为空或与已见 id 重复，直接 `throw FormatException`。`ids` 集合跨资料库累积，两个资料库有重叠内容（同一个文件被两次入库）时会命中。

- 后果：该来源每次重扫都失败，条目停在旧数据上，界面只显示一句"扫描失败，已保留原有条目"。
- **修法**：重复时跳过该条并记一条警告，不中断整次扫描。

### RM-06 · 离线/大库场景下，播放进度触发整库 JSON 重写（S3）

`player_screen.dart:163-165` 每移动 ≥5 秒回调一次；`app_shell.dart:388-390` 直接 `updatePosition`；`library_store.dart:120-137` 每次 `save()` 都把**全部 items + sources + collections + taste** 序列化成一份 JSON 再原子替换。

- 后果：1 万条片库（几十 MB JSON）播放时每 5 秒一次全量编码+落盘；写入是串行队列（`_writes`），磁盘慢时会堆积。
- **修法**：进度单独存一个小文件（或 SQLite），节流到 10–15 秒 + 退出时补写一次。

### RM-07 · 来源列表每次重建都做 O(来源×条目) 统计（S3）

`sources_view.dart:528` 在每个来源行里 `store.items.where((i) => i.sourceId == s.id).length`。10 个来源 × 1 万条目 = 每次 rebuild 10 万次遍历；扫描进度 tick 会持续触发 notifyListeners。

- **修法**：在 store 里维护 `Map<sourceId,int> counts`，或扫描结束时缓存一次。

### RM-08 · 重扫时手工重建 MediaSource，已经因此丢过字段（S3，已咬过一次）

`library_store.dart:262-275` 用 10 个字段逐个重建 source，而不是 `copyWith`。1.16 审计里已经发现过同类问题（`_rescan` 丢 `folders`，见 `docs/plan/v1.16-plan.md:117`），当时的修法是"把漏的字段补上"——结构没改，下次加字段还会再丢一次。

- **修法**：`MediaSource.copyWith`，或在 rescan 里只改 `lastScan` 一个字段（`sources[index] = source.copyWith(lastScan: now)`）。

### RM-09 · 本地扫描用文件名子串 `sample` 过滤，会误杀正片（S3）

`local_scanner.dart:63`：`if (name.toLowerCase().contains('sample')) continue;`。片名含 Sample 的正常影片（如 `The Sampler`、`Sample This`）会被静默跳过，且没有任何提示。

- **修法**：改为匹配独立 token（`-sample`、`sample.`、`[sample]`）且仅在同目录存在正片时生效。

---

## 3. 流程与分发缺陷（比单个 bug 更贵）

| ID | 问题 | 证据 | 影响 |
| --- | --- | --- | --- |
| Q-01 | CI 不跑测试也不跑 analyze | `.github/workflows/flutter.yml` 五个 job 只有 `build` | 回归无人拦；绿勾给人虚假安全感 |
| Q-02 | GitHub Latest 指向 `v1.1.0` | `gh api repos/.../releases/latest` → `v1.1.0` | 新用户默认下载 17 版之前的包 |
| Q-03 | 无 issue / 无 PR / 无 CHANGELOG | `gh issue list` 空；仓库无 `CHANGELOG.md` | 缺陷不可追踪、变更不可汇总 |
| Q-04 | 平台资产不稳定 | 1.18.0 只有 2 个资产且无 SHA256SUMS | 用户不确定该装哪个；校验靠正文复制 |
| Q-05 | 对齐文档过期 | `docs/parity.md` 停在 1.15.0，正文写"231 项测试"（当前 307+） | 跨端承诺无法核对 |
| Q-06 | 规划分散 | `docs/plan/` 2 份 + Rust 独立里程碑 + 无路线图 | 同一优先级在两处各说一套 |

---

## 4. 跨端对齐：真实状态

Flutter 主线是**一套代码五端**，所以功能层面天然对齐；不对齐的是三件事：

1. **入口与交互**：桌面侧栏 / 移动底部导航 + 「更多」面板（1.14 已对齐入口，但窄屏仍有差异）。
2. **系统能力**：SMB（仅桌面）、遥控主机（仅桌面）、迷你窗（仅桌面）、SAF/媒体权限（仅移动）、系统 PiP（仅移动）。`docs/parity.md` 列过，结论仍成立。
3. **内核分叉（最大的未来风险）**：Rust 线只认 macOS（决策 D-12，`docs/plan/rust-rewrite-plan.md`）。一旦桌面迁到 Rust，**桌面与移动将不再是同一套 UI 代码**，"一套代码两端一致"的红利消失，需要设计令牌与行为清单双份维护。

> 现在不存在"桌面修了移动没修"的代码级差异（同一份 Dart），**但存在"桌面在改 Rust、移动完全拿不到"的产能级差异**——这正是 D-12 记录的那次误判。

---

## 5. 已有资产（不要重做）

- **测试基线真实存在**：`apps/seewow/test` 51 个文件，本次实跑结果为 **307 通过 / 2 跳过 / 0 失败**（见 §6）。
- **1.16 有过一次独立代码审计**，7 条阻塞项全修（`v1.16-plan.md:113-125`），说明审计流程本身可用，只是没被制度化。
- **Rust 线有硬门禁**：fmt / clippy / test 三条写进 CI（`.github/workflows/rust.yml`），比 Flutter 线更严。
- **发布说明写得很诚实**：每版都有"本次没有做的事"。问题不是不说，是**没有把"没做"变成待办**。

---

## 6. 本次实跑

```
$ cd apps/seewow && flutter test --concurrency=1
05:52 +307 ~2: All tests passed!
EXIT=0
```

**307 通过 / 2 跳过 / 0 失败，耗时 5 分 52 秒，与 1.18.0 发布说明声称的基线完全一致。** 测试本身是诚实的——问题在覆盖面和门禁：

- 307 项里没有一条覆盖"父子目录重叠""断开确认""Plex 改选资料库""进度写入量"（见 §2 RM-02/01/04/06）；
- 这 307 项在 CI 里**从不执行**（Q-01），只在本地手动跑，所以它们的保护作用完全依赖人记得跑。

CI 侧：`gh run list` 最近 15 次全绿——但这个"绿"只覆盖编译，不覆盖行为。

---

## 7. 建议的第一版（1.19.0）验收口径

只做资源管理与门禁，**不加任何新功能**：

1. RM-01 断开有确认，文案写明会移除多少条目与记录。
2. RM-02 父子目录重叠被拦截，或全局按 id 去重后不出现重复卡片。
3. RM-03 来源可停用，停用后不参与刷新，条目与进度保留。
4. RM-04 Plex 不重登录即可改资料库选择，且不强制重扫全库。
5. RM-05 重复 ratingKey 跳过并提示，不整库失败。
6. Q-01 CI 增加 `flutter test` 与 `flutter analyze`（阻塞），并补 3 条链路测试：重叠目录、断开确认、Plex 改选。
7. Q-02 Latest 指向 1.19.0；五平台资产齐全或逐项写明缺口；附 SHA256SUMS.txt。
8. 移动端真机记录：iOS / Android 各一台，跑"加本地目录 → 重扫 → 播放 → 断开"四步，截图或日志入档。

**这 8 条不做完，不发 1.20。**

---

## 8. P0 首日进展（2026-11-17）

与 §2/§3 的编号一一对应。每条都先有测试、再看它红、再改到绿。

| 编号 | 状态 | 改了什么 | 测试 |
| --- | --- | --- | --- |
| RM-01 | 已修 | `_remove` 增加确认框，写明将移除 N 个条目与观看记录 | `test/source_actions_test.dart`（取消/确认两条路径） |
| RM-02 | 已修 | `LibraryStore.sourceCovering` + `addSource` 拒绝父子目录重叠 | `test/source_management_p0_test.dart`（3 条：子目录、父目录、前缀不误判） |
| RM-03 | 已修 | 菜单「停用/启用来源」+ 列表「已停用」标记；停用即时重绘再落盘 | 单测（持久化）+ widget 测试（重新启用路径） |
| RM-04 | 待办 | 需要给 `PlexScanner` 注入点才能写自动化测试 | — |
| RM-05 | 已修 | 重复/空 ratingKey 跳过并计数（`lastSkipped`），不再整库失败 | `test/plex_duplicate_key_test.dart`（真实 HTTP 服务器） |
| RM-06 | 待办 | 进度写盘要动持久化结构，单独一批 | — |
| RM-07 | 待办 | 来源计数缓存，跟随 RM-06 一起做 | — |
| RM-08 | 已修 | 新增 `MediaSource.copyWith`；`_rescan` 只改 `lastScan` | 两条回归测试（字段全等、重扫不丢） |
| RM-09 | 已修 | `sample` 改为词元匹配，The Sampler 不再被跳过 | `test/local_sample_filter_test.dart` |

**流程侧**

- Q-01：`.github/workflows/flutter.yml` 的 macOS job 增加 Analyze（error/warning 阻塞、历史 info 不阻塞）与 Test 两步。红/绿两侧都验过：故意写坏断言 → `exit 1`；真实日志 → 通过。
- Q-02：`gh release edit v1.18.0 --prerelease=false --latest`。GitHub 明确拒绝让 prerelease 当 Latest（HTTP 422），所以 v1.18.0 的 prerelease 标记被取消——这是为了让默认下载不再指向 1.1.0 的必要动作，已记录在路线图 §7。
- Issue：#2–#12 已建，标签 `bug` + `P0`。
