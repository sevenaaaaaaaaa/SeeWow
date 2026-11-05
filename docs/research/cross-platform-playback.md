# SeeWow 跨平台播放器技术调研

> 调研日期：2026-11-05 · 版本 v1.0
> 关联文档：`docs/ADR-001-cross-platform.md`（本文对该 ADR 做验证与修正，不替代其决策记录职责）
> 证据口径：所有版本号均来自 2026-11-05 实时抓取的 pub.dev / GitHub / 官方文档；无法确认的地方显式标注「待验证」，不做推测性断言。
> 源码证据基于 media_kit 仓库 main 分支与已发布 tag，二者不一致处会单独说明。

---

## 0. 一页结论

**结论：坚持 Flutter，但放弃「纯 Flutter 播放器」这个架构假设。** Flutter 负责表现层（导航、动效、片库、设置、播放器叠层 UI），**播放与传输必须下沉为原生核心**。ADR-001 的五端选型方向正确，但有三处需要修正。

### 三条红旗（会决定项目成败）

| # | 红旗 | 证据 | 影响 |
|---|---|---|---|
| R1 | **media_kit 的纹理路径在结构上无法交付 HDR** | mpv 渲染 API 不支持 gpu-next（[mpv#10810](https://github.com/mpv-player/mpv/issues/10810) OPEN），Windows 纹理是 `DXGI_FORMAT_B8G8R8A8_UNORM`、Linux 是 `GL_RGBA8` | HDR10 / 杜比视界只能 tone-map 成 SDR；DV Profile 5 还会偏色（[media_kit#1354](https://github.com/media-kit/media-kit/issues/1354) OPEN） |
| R2 | **Linux 上视频纹理会阻塞 Flutter raster 线程** | [media_kit#1439](https://github.com/media-kit/media-kit/issues/1439)：30fps 素材每帧阻塞 17–25ms，UI 掉到 43–51Hz | 「60fps 动画」在 Linux 上直接不成立；修复只在 main，2.0.1 未发 |
| R3 | **`smb://` 不能直接播** | 本机 FFmpeg 9.0.2 `-protocols` 无 smb；libmpv 未链接 libsmbclient；FFmpeg 的 smb 协议依赖 Samba libsmbclient | 必须做「挂载点 / 本地 HTTP 桥」二选一，SMB 是工程量最大的一块 |

### 五条可执行判断

1. **播放内核**：v1 用 media_kit 1.2.6 + 本地补丁（`block_for_target_time=0`），不自建播放器；但**必须 fork 或用 git dependency**，不能直接吃 pub 版本。
2. **HDR**：v1 明确不承诺 HDR，做「高质量 SDR tone-map + 正确色彩管理」；把 HDR 作为 v2 的独立工作流（Apple 走 AVPlayer 原生层，桌面走原生 mpv 窗口 / swapchain），而不是试图在 Flutter 纹理里解决。
3. **SMB**：桌面用系统挂载（macOS NetFS / Windows WNet / Linux gvfs），移动端用 libsmb2（当前可评估 `dart_smb2` 0.2.4）+ 本地 HTTP Range 桥；**所有媒体源在进入播放器前统一收敛成 `file://` 或 `http://127.0.0.1:PORT/`**。
4. **性能**：真正的敌人是「视频纹理 + 全屏模糊/颗粒叠加」的带宽，不是 Impeller 本身；建立帧预算红线并进 CI。
5. **分发**：macOS 走 Developer ID + notarytool（不上 MAS）；Windows MSIX + Inno 双轨；Linux 先 AppImage 后 Flatpak；iPadOS 只考虑 TestFlight/App Store，不做侧载幻想。

### 与 ADR-001 的差异

| ADR-001 原判断 | 本次调研结论 |
|---|---|
| 「Flutter + media_kit 可作为五端统一内核」 | 方向对，但 media_kit 只能作为**桌面/Android 的 v1 内核**；iPadOS 的 HDR 与高码率需要 AVPlayer 分支 |
| 「SMB 分三阶段」 | 阶段划分正确，但需补充：移动端必须走 libsmb2 + HTTP 桥，桌面系统挂载要写三套平台代码，**没有一条代码路径能覆盖五端** |
| 「HDR 后续再做」 | 同意推迟，但必须现在决定「是否做原生播放窗」，因为这决定播放器页面是否要保留一个非 Flutter 的视图槽位 |

---

## 1. media_kit：版本、后端与真实能力边界

### 1.1 版本矩阵（pub.dev，2026-11-05）

| 包 | 最新稳定版 | 发布时间 | 备注 |
|---|---|---|---|
| `media_kit` | **1.2.6** | 2025-12-13 | Dart 侧 API；此后无新发布 |
| `media_kit_video` | **2.0.1** | 2025-12-02 | 视频输出实现（各平台原生代码在此） |
| `media_kit_libs_windows_video` | 1.0.11 | 2025-03-24 | 预编译 libmpv |
| `media_kit_libs_linux` | 1.2.1 | 2025-03-24 | 依赖系统 libmpv（apt/dnf） |
| `media_kit_libs_macos_video` | 1.1.4 | 2023-09-27 | **近三年未更新** |
| `media_kit_libs_ios_video` | 1.1.4 | 2023-09-27 | **近三年未更新** |
| `media_kit_libs_android_video` | 1.3.8 | 2025-10-05 | 预编译 .so |

判读：
- 维护活跃度低。1.2.6 的 CHANGELOG 只有一条 `fix(windows): long file path support`，且 1.2.4 / 1.2.5 / 1.2.6 是同一修复的重复发版。
- GitHub Releases 页的 tag 列表落后于 pub（停在 media_kit-v1.1.10 / media_kit_video-v1.2.3），**版本判断以 pub.dev 为准**。
- macOS/iOS 的 libs 包自 2023-09 未动，意味着 Darwin 侧捆绑的 libmpv 版本较旧 —— 这与 [media_kit#777](https://github.com/media-kit/media-kit/issues/777) 的结论一致（Darwin 构建用旧 mpv 且只有 OpenGL）。

**行动项**：`pubspec.yaml` 锁定精确版本 + 提交 `pubspec.lock`；升级策略为「季度人工评估」，不做 `^1.2.6` 自动跟随。

### 1.2 各平台后端差异

| 平台 | 视频输出路径 | 中间纹理 / 位深 | 解码 | Flutter 侧 |
|---|---|---|---|---|
| **Windows** | libmpv render API → D3D11 共享纹理（`D3D11_RESOURCE_MISC_SHARED`，双缓冲）→ ANGLE 转 OpenGL ES 采样 | `DXGI_FORMAT_B8G8R8A8_UNORM`，**8-bit SDR** | mpv `hwdec`（D3D11VA） | `Texture` widget |
| **Linux** | libmpv render API → GL FBO → `glTexImage2D(GL_RGBA, GL_UNSIGNED_BYTE)` | `GL_RGBA8`，**8-bit SDR** | VAAPI / NVDEC（随 mpv 构建） | `Texture` widget |
| **macOS** | libmpv render API → OpenGL（`gl/` 目录）或 Metal（`TextureHW.swift`）纹理 | 8-bit（Metal 路径的具体 pixel format **待验证**） | VideoToolbox | `Texture` widget |
| **iOS/iPadOS** | 同上（`TextureHW.swift`） | 8-bit（**待验证**） | VideoToolbox | `Texture` widget |
| **Android** | `vo=gpu` + SurfaceTexture / ImageReader | 8-bit | MediaCodec | `Texture` widget |

证据：
- Windows 纹理格式见 [`angle_surface_manager.cc`](https://github.com/media-kit/media-kit/blob/main/media_kit_video/windows/angle_surface_manager.cc)。
- Linux 纹理格式见 [`texture_gl.cc`](https://github.com/media-kit/media-kit/blob/main/media_kit_video/linux/texture_gl.cc)。
- `VideoControllerConfiguration` 的 `vo` 默认值：桌面与 iOS 为 `libmpv`，Android 为 `gpu`（[#573 讨论](https://github.com/media-kit/media-kit/issues/573) 引用了源码注释）。

**关键结构性事实**：五个平台全部走 Flutter 外部纹理，没有一个是原生视图（native view / platform view）。这意味着：

1. 视频帧永远要先落到一张由 Flutter 合成的纹理上；
2. 纹理格式由 media_kit 决定（8-bit），Flutter 再把它当普通图片采样；
3. 没有任何路径把 HDR metadata（PQ/HLG、MasteringDisplay、MaxCLL）送给窗口系统。

### 1.3 HDR 与杜比视界：为什么这不是「调参问题」

因果链（每一环都有独立证据）：

```
HDR 源 (PQ/HLG + BT.2020)
   │
   ├─ ① mpv 渲染 API 只有 gpu(OpenGL) 后端，没有 gpu-next/libplacebo
   │     → 无 DV reshape、无 libplacebo 高级 tone mapping
   │     (mpv#10810 OPEN, 2022-10-29 创建, 2026-10-13 仍有更新)
   │
   ├─ ② 输出纹理是 8-bit UNORM
   │     → 量化精度损失、无法承载 HDR 传递函数
   │
   └─ ③ Flutter 合成层是 SDR swapchain
         → OS 拿不到 HDR 信号，Windows 不会切 HDR10、macOS 不会开 EDR
```

具体表现：

| 内容 | media_kit 实际结果 | 说明 |
|---|---|---|
| HDR10 (PQ, BT.2020) | tone-map 到 SDR，颜色基本正确但高光被压缩 | 可接受，取决于 tone-mapping 算法 |
| HLG | 同上 | — |
| **DV Profile 5**（IPTPQc2，无兼容层） | **偏色/发绿**，无法正确还原 | 需 libplacebo reshape；[#1354](https://github.com/media-kit/media-kit/issues/1354) OPEN，用户即使传 `vo:'gpu-next'` 仍错色，原生 mpv 正常 |
| DV Profile 8.1（HDR10 兼容层） | 退化为 HDR10 → 再 tone-map 到 SDR | 可看，但不是 DV |
| DV Profile 7（BL+EL） | 只解 BL | 可看 |
| 10-bit HEVC/AV1 SDR | 正常（解码 10-bit，输出 8-bit） | 有轻微 banding 风险 |

**为什么 `vo:'gpu-next'` 救不了**：media_kit 是把 `vo` 传给 libmpv，但在 render API 模式下 mpv 忽略 `vo`，只用内置的 render API 后端。[#1093](https://github.com/media-kit/media-kit/issues/1093)（Android 设 gpu-next 后黑屏有声）与 [#1354] 都印证了这一点。[#777](https://github.com/media-kit/media-kit/issues/777) 的维护者结论更直接：「gpu-next 不被渲染 API 支持」。

**三条出路（按成本排序）**：

| 方案 | 做法 | 代价 | 适用 |
|---|---|---|---|
| A. 接受 SDR | 设 `tone-mapping=bt.2390`（或 `hable`）+ `hdr-compute-peak=yes`，UI 上标注「HDR→SDR」 | 无架构改动，画质打折 | v1 默认 |
| B. 原生播放窗 | 播放 HDR 时切到一个原生 surface：macOS `AVPlayerLayer`（HDR/EDR 原生支持）、Windows 自建 D3D11 swapchain + `DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020`、Linux 用 mpv 独立窗口（`--vo=gpu-next`） | 播放页需要预留一个非 Flutter 视图槽位；叠层 UI 需重新设计（Flutter 无法在其上绘制） | HDR 作为卖点时的唯一正解 |
| C. 换内核 | 桌面改用 libmpv 的独立窗口 + IPC 控制，Flutter 只做「遥控器」 | 播放页不再是 Flutter，等于放弃一半的视觉一致性 | 不推荐 |

**建议**：v1 走 A，但在播放器页面架构上**现在就把 B 的槽位留出来**（一个可被原生层接管的 `PlatformView`/子窗口区域），否则 HDR 立项时要重构整个播放页。

### 1.4 硬件解码

- 开关：`VideoControllerConfiguration(hwdec: 'auto-safe')`；`enableHardwareAcceleration` 控制的是**渲染**（D3D11/GL 路径），不是解码，两者独立。
- 官方 README 明确「video playback uses hardware acceleration i.e. GPU by default」，但**未在任何地方承诺 HDR**。
- 已知硬解问题：
  - Android HDR10 + `hwdec:'auto-safe'` 画面错乱，`hwdec:'no'` 正常（[#1207](https://github.com/media-kit/media-kit/issues/1207) OPEN）。
  - Android TV / NVIDIA Shield 硬解异常（[#1243](https://github.com/media-kit/media-kit/issues/1243) OPEN）。
  - Windows 硬渲染下固定位置出现细黑色虚线残影，关掉 `enableHardwareAcceleration` 消失（[#1471](https://github.com/media-kit/media-kit/issues/1471) OPEN）。
  - Linux Wayland + Intel Xe2：GL 初始化成功但画面全黑，根因是对 media_kit 的纹理创建 `EGLImageKHR` 导致 Mesa 停止渲染（[#1463](https://github.com/media-kit/media-kit/issues/1463) OPEN，含 ~200 行复现）。

**建议配置**：
- 桌面默认 `hwdec: 'auto-safe'`；检测到 `hwdec-current` 为 `no` 时回退软解并提示用户。
- Android 遇到 HDR10 内容时主动切 `hwdec: 'no'`（规避 #1207），或按机型黑名单。
- 暴露「硬解开关」给高级用户 —— 这类问题短期内不会全修完。

### 1.5 字幕、音轨、音频

| 能力 | 状态 | 说明 |
|---|---|---|
| 内嵌 ASS/SSA | ✅ | libass 随包（bundle 内有 `libass.9.dylib`），样式/特效可用 |
| 内嵌 PGS/VOBSUB | ✅ | mpv 位图字幕 |
| 外挂字幕 | ✅ | `setSubtitleTrack(SubtitleTrack.uri(...))` |
| 字幕样式自定义 | ⚠️ 受限 | 只能通过 ASS override / `--sub-*` 选项；无法用 Flutter 渲染字幕（会失去 libass 排版能力） |
| 多音轨切换 | ✅ | `setAudioTrack` |
| 外挂音轨 | ✅ | `AudioTrack.uri` |
| 音轨直通（DTS/TrueHD/Atmos） | ❌ 未暴露 | 需要自定义 mpv 选项/构建；且 Flutter 侧音频走 mpv 的 AO，直通需要独占设备 |
| TrueHD 无声 | ⚠️ 历史问题 | [#952](https://github.com/media-kit/media-kit/issues/952) 已 CLOSED，但需回归验证 |

字幕的工程建议：字幕渲染发生在 mpv 内部（CPU + libass），4K 复杂特效字幕会占 1–3 个核心；**不要试图用 Flutter 重绘字幕**，那会丢掉 ASS 的全部排版能力，也会让「字幕位置随窗口缩放」变得不可控。

### 1.6 已知坑清单（按严重度）

| 严重度 | Issue | 平台 | 现象 | 状态 |
|---|---|---|---|---|
| P0 | [#1472](https://github.com/media-kit/media-kit/issues/1472) | Windows | 同一帧内 dispose 3–5 个 Player → **use-after-free 原生崩溃、进程直接退出**（9 路 4K H.265 RTSP 网格场景复现；不 dispose 复用则不崩） | OPEN 2026-11-04 |
| P0 | [#1439](https://github.com/media-kit/media-kit/issues/1439) | Linux | <60fps 视频把 Flutter raster 拖到 43–51Hz | CLOSED，修复仅在 main |
| P1 | [#1463](https://github.com/media-kit/media-kit/issues/1463) | Linux/Wayland | GL 初始化成功但全黑 | OPEN |
| P1 | [#1354](https://github.com/media-kit/media-kit/issues/1354) | 全平台 | DV P5 偏色 | OPEN |
| P1 | [#1207](https://github.com/media-kit/media-kit/issues/1207) | Android | HDR10 + 硬解花屏 | OPEN |
| P2 | [#1471](https://github.com/media-kit/media-kit/issues/1471) | Windows | 硬渲染虚线残影 | OPEN |
| P2 | [#1445](https://github.com/media-kit/media-kit/issues/1445) | Android | 直播流渲染一次后永久黑屏 | OPEN |
| P2 | [#68](https://github.com/media-kit/media-kit/issues/68) | Linux | dispose 不释放内存 | OPEN |
| P3 | [#1243](https://github.com/media-kit/media-kit/issues/1243) | Android TV | Shield 硬解异常 | OPEN |

#1472 对 SeeWow 的直接约束：**播放器页面必须做到「单实例 Player + 复用」**，禁止在列表/网格里为每个 tile 建 Player。缩略图/预览必须走独立解码器（ffmpeg/mpv screenshot），不能靠 N 个 Player。#1472 的场景（9 路 4K 网格）与 SeeWow 的「片库网格 + Hero 预览」高度相似。

### 1.7 对 ADR-001 的修正建议

1. 把「五端统一内核」改为「**桌面 + Android 用 media_kit；iPadOS 预留 AVPlayer 分支**」。
2. 增加一条 ADR：「播放器页面保留原生视图槽位」——为 HDR 与极端码率留后路。
3. 增加一条工程约束：「media_kit 以 git dependency 锁定 commit，携带 #1439 补丁」。

---
## 2. SMB：四条路线与推荐架构

### 2.1 结论先行

**没有任何一条代码路径能同时覆盖 macOS / Windows / Linux / iPadOS / Android。** 可行的组合是：

- **桌面（macOS / Windows / Linux）**：系统挂载。稳定、吞吐最好、SMB3 加密与签名由系统负责、mpv 直接读普通文件路径，seek 走内核缓存。
- **移动（iPadOS / Android）**：libsmb2（in-process）+ 本地 HTTP Range 桥。系统没有可用的 SMB 挂载 API，只能自己实现传输层。
- **直接播 `smb://`**：不可行，见 2.5。

### 2.2 路线对比

| 维度 | 系统挂载 | libsmb2 FFI | 纯 Dart 包（smb_connect） | 自建 FFmpeg 协议 |
|---|---|---|---|---|
| 覆盖平台 | macOS ✅ / Windows ✅ / Linux ⚠️(gvfs) / 移动 ❌ | 五端 ✅ | 五端 ✅ | 五端（需自编译 libmpv/FFmpeg） |
| 依赖 | OS 内置 | 每平台预编译 .a/.so（~250KB/架构） | 无 | 需改 FFmpeg + 重打包 libmpv |
| 协议版本 | SMB2/3（系统客户端） | 2.0–3.1.1 | **1.0/2.0/2.1，无 SMB3** | 取决 libsmbclient |
| 加密/签名 | ✅ 系统负责 | ✅ `seal`/`sign` | ❌ | 取决 libsmbclient |
| 吞吐 | ★★★★★（内核/用户态客户端 + 预读） | ★★★（需自己做预读） | ★★ | ★★★★ |
| 凭据管理 | Keychain / DPAPI / libsecret | 自己加密存储 | 自己存 | 自己存 |
| 工程量 | 3 套平台代码 + 卸载清理 | 1 套 + HTTP 桥 | 最小 | 最大（构建链） |
| 主要风险 | 沙箱/Flatpak 限制、断线重连、路径差异 | LGPL 合规、性能、包太新 | SMB3 缺失，现代 NAS 可能拒绝 | 构建链失控 |

### 2.3 系统挂载：逐平台细节

#### macOS — NetFS.framework

- 头文件：`MacOSX.sdk/System/Library/Frameworks/NetFS.framework/Headers/NetFS.h`
  - `NetFSMountURLSync` 第 312 行、`NetFSMountURLAsync` 第 341 行、`NetFSMountURLCancel` 第 358 行
  - 可用性标注 `__OSX_AVAILABLE_STARTING(__MAC_10_8, __IPHONE_NA)` → **仅 macOS**
- iPhoneOS SDK 中**没有** NetFS.framework（已用 `ls` 验证）→ iPadOS 彻底没有系统 SMB 挂载 API。

```swift
// 参数顺序以 NetFS.h 为准；此处为形状示意
var mountpoints: CFArray?
let rc = NetFSMountURLSync(
    url as CFURL,          // smb://user@host/share
    nil,                   // mountpath，nil = 系统默认 /Volumes
    user as CFString,
    passwd as CFString,
    nil,                   // open_options（kNetFSNoUserPromptKey 等）
    nil,                   // mount_options
    &mountpoints
)
```

要点：
- 挂载点通常在 `/Volumes/<share>`；返回值是 `CFArray<CFURL>`，用第一个作为根路径。
- 必须在**非沙箱**的 Developer ID 构建下使用；App Sandbox 下挂载行为**待验证**（沙箱只保证 `com.apple.security.network.client` 出网，卷挂载很可能被拒）。这也是「不上 MAS」的一个理由。
- 断开重连：NetFS 不做自动重连，需要自己监听 `NSWorkspace.didUnmountNotification` 或文件 IO 失败后重挂。
- 卸载：`NetFSUnmountURLSync` 或 `NSWorkspace.unmountAndEjectDevice`。

#### Windows — WNetAddConnection2W

[`WNetAddConnection2W`](https://learn.microsoft.com/en-us/windows/win32/api/winnetwk/nf-winnetwk-wnetaddconnection2w) 可以把网络资源重定向到本地设备，也可以**只建立连接、不分配盘符**（`lpLocalName = NULL`），之后直接用 UNC 路径访问。

```dart
// 关键在 lpLocalName = NULL：不占盘符，返回后直接用 \\host\share\path
// 结构体 NETRESOURCEW: dwType=RESOURCETYPE_DISK, lpRemoteName=L"\\\\host\\share"
final rc = WNetAddConnection2W(ptrRes, passwordPtr, usernamePtr, 0 /* CONNECT_TEMPORARY */);
// 断开：WNetCancelConnection2W(remoteName, 0, TRUE)
```

要点：
- `CONNECT_TEMPORARY` 不写入用户持久连接，退出时清理。
- 需要 `mpr.dll`；Dart 侧用 `dart:ffi` 即可，不需要 C 插件。
- Windows 11 默认禁用 SMB 来宾访问（guest），匿名共享会失败 → 必须支持用户名/密码。
- SMB1 默认关闭，正好；目标协议是 SMB2/3。
- UNC 路径对 mpv 是普通路径，seek/缓存表现最好。

#### Linux — gvfs（唯一不需要 root 的方案）

```bash
gio mount smb://user@host/share
# 挂载点：/run/user/$UID/gvfs/smb-share:server=host,share=share[,user=user]
```

要点：
- 依赖 `gvfs-smb` 包 + 一个运行中的 D-Bus 会话；headless / 精简发行版常常没有。
- `mount.cifs` 需要 root / `CAP_SYS_ADMIN`，桌面应用不可用（除非配 polkit helper，工程量与安全风险都高）。
- Flatpak 沙箱内看不到 `/run/user/$UID/gvfs`，必须 `--filesystem=/run/user/1000/gvfs`（或 broader）才能读。这是 Flatpak 分发的一个真实痛点。
- 路径里有逗号与冒号，**必须当作不透明字符串处理**，不要自己拼。

#### 系统挂载的通用工程问题

| 问题 | 处理 |
|---|---|
| 凭据存储 | macOS Keychain / Windows Credential Manager / Linux libsecret；绝不落明文配置文件 |
| 断线 | IO 错误 → 指数退避重挂 → 恢复后从上次位置 seek |
| 挂载点冲突 | 同名 share 已挂载时复用，不要重复挂 |
| 应用退出 | 卸载自己挂的卷；但不要卸载用户手动挂的 |
| 路径编码 | SMB 文件名可能是 UTF-16/非法 UTF-8 → 统一走字节路径，Dart 侧用 `Uri` 而非 `String` 拼接 |

### 2.4 libsmb2 / `dart_smb2`

[`libsmb2`](https://github.com/sahlberg/libsmb2) 是纯 C 的 SMB2/3 客户端：
- 协议：`vers=2`、`3`、`2.02`、`2.10`、`3.00`、`3.02`、`3.1.1`
- 选项：`seal`（SMB3 加密）、`sign`（强制签名）、`quic` / `rdma`（**仅 Linux**）
- 许可：仓库 `COPYING` 首行写明「Libsmb2 components fall under separate licences」，`lib/` 与 `include/` 为客户端库许可（LGPL-2.1，**以仓库 COPYING 原文为准**）。iOS 上静态链接 LGPL 库有合规争议，需法务确认（或改用动态框架 + 允许替换）。

**`dart_smb2` 0.2.4**（pub.dev，published 2026-11-02，距调研约 44 小时）：
- 用 Dart build hooks 打包五端原生库（每架构 235–271 KB），要求 Dart 3.10 / Flutter 3.47
- `Smb2Pool` 多 isolate 连接池、`streamFile` / `downloadToFile`、取消 token、类型化 NT status、零拷贝、SMB3 NTLM + 加密 + 签名、最高 3.1.1、目录/范围读/句柄/写/重命名/时间戳/共享空间
- 风险：**v0.x、发布两天、无社区验证**。可以评估，但必须：pin 精确版本 + 保留自建 FFI 的退路 + 用真实 NAS（Synology/QNAP/Windows Server）做兼容矩阵

**`smb_connect` 0.0.9**（2025-01-25，页面显示 21 个月前）：纯 Dart，只到 SMB 2.1，**无 SMB3、无加密/签名**；pub 评分 120、下载约 2k。现代 NAS 普遍要求 SMB3 或至少签名，**不适合生产**。

**`libdsm` 系列**（`libdsm_dart3` 1.1.10 / `libdsm` 1.1.8）：只支持 SMB1，已被主流 NAS 默认关闭，**淘汰**。

### 2.5 直接播 `smb://` 为什么不可行

证据链：

1. mpv 的网络协议全部来自 FFmpeg。FFmpeg 的 SMB 支持是 [`libsmbclient` 协议](https://ffmpeg.org/ffmpeg-protocols.html#libsmbclient)，依赖 Samba 的 `libsmbclient`。
2. 本机验证：`/opt/homebrew/bin/ffmpeg -protocols`（FFmpeg 9.0.2）输出中**没有 smb**（只有 http/https/rtmp/rtp/srtp/tcp/udp 等）。
3. 本机验证：`otool -L dist/SeeWow.app/Contents/Frameworks/libmpv*.dylib` **没有 libsmbclient** 依赖。
4. media_kit 的预编译 libmpv（Windows/Android/macOS/iOS）为控制体积，同样不带 libsmbclient（macOS 已实测；其余平台**待验证**，但构建脚本未见该依赖）。

结论：`player.open(Media('smb://user:pass@host/share/a.mkv'))` 会失败。且即使自编译带上 libsmbclient，也有两个问题：
- Samba 是 GPLv3，与闭源分发/App Store 不兼容；
- `libsmbclient` 不支持 SMB3 加密的细粒度控制，凭据也只能塞在 URL 里。

### 2.6 推荐架构：`MediaSource` → `PlayableUri`

把所有来源统一收敛成两种可播 URI，播放器只认这两种：

```dart
sealed class PlayableUri {}
class LocalFile extends PlayableUri { final String path; }          // file://
class LoopbackHttp extends PlayableUri { final Uri uri; }           // http://127.0.0.1:PORT/...

abstract class MediaResolver {
  Future<PlayableUri> resolve(MediaSource source);
  Future<void> release(PlayableUri uri);
}
```

各来源的落地方式：

| 来源 | 解析为 | 说明 |
|---|---|---|
| 本地文件 | `file://` | 直接给 mpv |
| SMB（桌面） | `file:///Volumes/share/...` 或 `file:////host/share/...` | 系统挂载后的路径 |
| SMB（移动） | `http://127.0.0.1:PORT/token` | libsmb2 + Range 桥 |
| WebDAV | `http://127.0.0.1:PORT/token` | 统一走本地桥（可注入 Authorization，避免把凭据写进 URL） |
| Emby/Jellyfin | 直连 `http://host/Videos/{id}/stream?static=true` | 支持 Range，mpv 可直接播；需要 `X-Emby-Token` 头 → 走桥或 `--http-header-fields` |
| Plex | 直连 `/library/parts/...` + `X-Plex-Token` | 同上 |
| DLNA | `http://host:port/...` | 通常是直连 HTTP |
| IPTV | `http://` / `rtsp://` / `udp://` | 直连；注意 #1445（Android 直播黑屏） |

**本地 HTTP Range 桥的最小实现**：

```
GET /<token>
  → libsmb2 open + stat
  → 200 + Content-Length + Accept-Ranges: bytes
  → 若带 Range: bytes=a-b → 206 + Content-Range

预读策略：
  - 顺序读：read-ahead 8–32 MB 的分块缓存（按 1 MB 块）
  - seek：丢弃预读、直接 pread，允许 1 次 RTT 的延迟
  - 并发上限：每个文件 1 个读协程 + 4 个 in-flight 请求
```

为什么不用「把整个文件下载到临时目录」：4K 原盘 60–90 GB，下载等待不可接受，且移动端存储不够。

### 2.7 iOS / iPadOS / Android 限制对照

| 能力 | iPadOS | Android |
|---|---|---|
| 系统 SMB 挂载 API | ❌（NetFS 标注 `__IPHONE_NA`，SDK 无该 framework） | ❌ |
| 用户手动连服务器 | ✅ 文件 App「连接服务器」，但只给用户自己用，App 拿不到可浏览的卷 | ❌ |
| 通过文档选择器取文件 | ✅ `UIDocumentPicker` + security-scoped URL（单文件，非片库） | ✅ SAF（同样单文件） |
| 局域网访问权限 | iOS 14+ 需 `NSLocalNetworkUsageDescription`；访问局域网 IP 会弹权限框 | `INTERNET` 权限即可 |
| 后台传输 | 受限（BGTaskScheduler，不保证） | 前台服务 + 通知 |
| DLNA 发现（SSDP 组播） | 需 `com.apple.developer.networking.multicast` 特权（需向 Apple 申请） | 需 `WifiManager.MulticastLock` |
| 结论 | libsmb2 + HTTP 桥；DLNA 组播是额外审批风险 | libsmb2 + HTTP 桥 |

iPadOS 的 DLNA 组播权限是一个容易被忽略的坑：没有 multicast entitlement，SSDP 发现直接不可用，只能退化为「手动输入 IP」。

### 2.8 分阶段落地（对 ADR-001 的细化）

| 阶段 | 范围 | 交付 | 风险 |
|---|---|---|---|
| P0（v1，2–3 周） | 本地 + WebDAV + Emby/Jellyfin/Plex + 直连 HTTP/IPTV | `MediaResolver` 抽象 + 直连路径 | 低 |
| P1（3–4 周） | 桌面 SMB 系统挂载（macOS + Windows） | 三端中的两端；凭据存 Keychain/DPAPI | 中（沙箱、断线） |
| P2（4–6 周） | 移动 SMB：`dart_smb2` 或自建 libsmb2 FFI + HTTP 桥 | iPadOS + Android 可用 | 高（包太新、LGPL、性能） |
| P3 | Linux gvfs、DLNA 发现、Flatpak 适配 | 补齐 | 中 |

关键决策点：**P2 是否等 `dart_smb2` 成熟**。建议先做一个 2 天的 spike（真实 NAS、20 GB 4K 文件、测 seek 延迟与吞吐），再决定是依赖它还是自建 FFI。不要在没有 spike 的情况下把它写进排期。

---
## 3. Flutter 桌面/平板 UI 的性能边界

### 3.1 Impeller 现状（2026-11）

来自 [docs.flutter.dev/perf/impeller](https://docs.flutter.dev/perf/impeller)：

| 平台 | 状态 | 能否回退 Skia |
|---|---|---|
| iOS | 默认且**唯一**渲染后端（3.27 起，实际更早） | 不能 |
| Android（API 29+） | 3.27 起默认 | 可（`--no-enable-impeller`） |
| macOS | **Flutter 3.47 起默认** | 可，`Info.plist` 设 `FLTEnableImpeller=false` |
| Linux | **Flutter 3.47 起默认** | 可，`my_application.cc` 调 `fl_dart_project_set_enable_impeller(project, FALSE)` |
| Windows | **Flutter 3.47 起默认** | 可，`main.cpp` 设 `project.set_impeller_switch(ImpellerSwitch::Disabled)` |

官方同时写明「future release 将移除 opt-out」。**结论：按 Impeller-only 做设计与测试**，不要把「回退 Skia」写进风险缓解方案。

Impeller 的已知弱点恰好撞上 SeeWow 的视觉语言：
- [flutter/flutter#161297](https://github.com/flutter/flutter/issues/161297)：iOS BackdropFilter 性能问题
- [flutter/flutter#126353](https://github.com/flutter/flutter/issues/126353)：Impeller 下 BackdropFilter 模糊性能退化

官方性能建议（[best-practices](https://docs.flutter.dev/perf/best-practices)）明确指出 `saveLayer()` 昂贵（分配离屏缓冲），`Opacity` 与 `clip` 要少用，能用半透明颜色就不要用 `Opacity`。

### 3.2 一帧的旅程：视频纹理的真实成本

```
mpv 解码 ──► GPU 渲染到共享纹理 ──► Flutter raster 线程采样该纹理 ──► 合成 UI 图层 ──► 上屏
   (硬解)      (D3D11 / GL FBO)        (TextureLayer)              (Impeller)
```

带宽估算（这是硬上限，不是优化建议）：

| 分辨率 | 单帧字节数（BGRA/RGBA8） | 60fps 采样带宽 | 120fps |
|---|---|---|---|
| 1080p | 1920×1080×4 ≈ 8.3 MB | ≈ 0.50 GB/s | ≈ 1.0 GB/s |
| 1440p | 2560×1440×4 ≈ 14.7 MB | ≈ 0.88 GB/s | ≈ 1.8 GB/s |
| 4K | 3840×2160×4 ≈ 33.2 MB | ≈ **1.99 GB/s** | ≈ 4.0 GB/s |

这还只是「采样一次」。叠一层全屏模糊就是 2 次以上读写，叠颗粒是再一次全屏采样。集显（Intel Iris / Apple M 系列 base）的有效带宽在扣除合成、UI、系统占用后，4K + 模糊 + 颗粒 + 120Hz 是**不可能同时成立**的。

### 3.3 帧预算杀手 #1：raster 线程上的同步等待

[media_kit#1439](https://github.com/media-kit/media-kit/issues/1439) 是最重要的一条证据，因为它把「感觉卡」变成了可测量的数字：

- 根因：`texture_gl_populate_texture` 在 Flutter **raster 线程**上同步调用 `mpv_render_context_render`，且没有传 `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME`，mpv 取默认值 1 → **阻塞到该帧的目标呈现时间**。
- 实测：30fps 素材每帧阻塞 **17–25 ms**，raster 吞吐减半，Flutter 只有 **43–51 Hz**；60fps 素材只阻塞约 0.6 ms，几乎无感。
- 修复：传 `block_for_target_time = 0`。该修复**已在 main 分支**（`media_kit_video/linux/texture_gl.cc` 中可见 `int block_for_target_time = 0;`），但 **2.0.1 发布版没有**。

推论（对整个项目的意义）：
1. 只要播放内容不是 60fps（电影 23.976/24fps 就是典型），Linux 上 UI 就会掉到 40 多帧 —— 恰好是 SeeWow 最常播的内容。
2. 这不是「优化」，是**必须打的补丁**。用 `dependency_overrides` 指到 fork，或用 git dependency 锁 commit。
3. 同样的模式可能存在于其他平台（同步 render 调用），需要在 macOS/Windows 上用同样的方法测量（**待验证**）。

### 3.4 视觉效果的代价表

| 效果 | 直接做法 | 成本 | 建议做法 |
|---|---|---|---|
| 全屏模糊（毛玻璃） | `BackdropFilter` 压视频 | ❌ 极高：每帧全屏 offscreen + 多 pass | 只压在**静态海报/背景**上；视频层上方用预模糊的静态图做交叉淡入 |
| 胶片颗粒 | 每帧 shader 生成噪声 | 中高（全屏 pass + 高频采样） | 预生成 noise PNG，`BlendMode.overlay` 低透明度平铺，放 `RepaintBoundary` 内且**不随视频重绘** |
| 暗角 | `RadialGradient` 叠加 | 低（一个全屏 quad + blend） | 保留，但用 `BlendMode.multiply` 的静态层 |
| 圆角视频 | `ClipRRect` 包 `Video` | 中（可能触发 saveLayer） | `clipBehavior: Clip.hardEdge`（无 AA）或 shader 圆角；实测对比 |
| 半透明叠层 | `Opacity` 包 `Video` | 中高（saveLayer） | 用带 alpha 的颜色/图片替代 |
| 海报 3D 倾斜 | `Transform` + 透视 | 低 | 保留；但倾斜时不要同时播视频 |
| Hero 转场 | 直接 Hero 视频纹理 | 高（两处同时解码/合成） | **转场用海报替身**，落地后再挂视频 |
| 帧预览缩略图 | N 个 Player | ❌ 灾难（还触发 #1472 崩溃） | 单个离屏解码器（ffmpeg/mpv screenshot），异步生成 + 磁盘缓存 |

### 3.5 60 / 120fps 的硬性规则

帧预算：60fps = 16.67 ms，120fps = 8.33 ms（build + raster + 合成全含）。

规则（建议直接写进 `docs/PERF.md` 并进 code review checklist）：

1. **视频纹理尺寸 ≤ 显示尺寸**。用 `VideoControllerConfiguration(width:, height:)` 让 mpv 在 GPU 侧先缩放，例如 1080p 屏就给 1920×1080，省 4 倍带宽。
2. **视频层上方只允许一个全屏叠加 pass**（暗角或颗粒，二选一）。两个同时开必须降级到 60fps 模式。
3. **禁止 `BackdropFilter` 覆盖视频区域**。控制栏的毛玻璃背景用「当前帧截图 + 静态模糊」实现，而不是实时模糊。
4. **播放页只允许一个 Player 实例**（#1472）。多路预览用独立解码器。
5. **动画与视频位置解耦**：不要用 `player.stream.position` 驱动 60Hz 动画；用 `Ticker` + 本地插值，避免每帧跨 isolate 通信。
6. **不要在 `AnimatedBuilder` 里重建 `Video` widget**。播放器 widget 树要在动画期间保持 const/稳定。
7. **120fps 自适应**：iPad Pro（ProMotion）与高刷 Android 上，视频播放中把 UI 动画降到 60fps；暂停/浏览态再放开 120。Android 需要 `flutter_displaymode` 主动请求高刷（系统默认常为 60）。
8. **列表滚动**：片库网格用 `SliverGrid` + 固定 `itemExtent` + 预缓存图片；海报用 `cacheWidth` 解码到显示尺寸，避免 4K 海报原图进内存。

### 3.6 怎么测量（可执行）

| 层 | 手段 | 通过标准 |
|---|---|---|
| 帧级 | `SchedulerBinding.instance.addTimingsCallback` + `FrameTiming`，上报 build/raster 分位 | 60fps 目标：raster p95 < 8 ms，jank < 1% |
| 交互 | DevTools Performance（profile 模式），看 raster 线程 | 无 >16ms 的 raster 事件 |
| 平台 | macOS Instruments（Core Animation）、`adb shell dumpsys gfxinfo`、Windows GPU View | 无掉帧尖峰 |
| CI 回归 | `integration_test` + 30fps 测试素材（专门触发 #1439 类问题） | 连续 60s 播放，raster p95 < 12ms |

**必须放进 CI 的一条用例**：用 23.976fps 的 1080p H.264 播放 60 秒，同时在视频上叠加控制栏动画，采样 FrameTiming。这条用例能同时抓住 #1439 回归与模糊/颗粒叠加导致的掉帧。

---
## 4. 打包与签名

### 4.1 macOS：Developer ID + 公证（不上 MAS）

Apple 的 [公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) 明确：2023-11-01 起 notary service 不再接受 `altool` 或 Xcode 13 及更早版本上传，**必须用 `notarytool` 或 Xcode 14+**；macOS 10.15 起 Developer ID 分发必须公证；公证产生的 ticket 可以 `staple` 到 app 上以支持离线首次启动。

标准流水线：

```bash
flutter build macos --release

# 1) 先签内嵌的每一个 dylib/framework（media_kit 的预编译 libmpv 是 ad-hoc 签名，必须重签）
find build/macos/Build/Products/Release/SeeWow.app -name "*.dylib" -o -name "*.framework" \
  | while read f; do
      codesign --force --options runtime --timestamp \
        --sign "Developer ID Application: <TEAM>" "$f"
    done

# 2) 再签主 bundle（不要依赖 --deep，它会掩盖签名缺失）
codesign --force --options runtime --timestamp \
  --entitlements macos/Runner/Release.entitlements \
  --sign "Developer ID Application: <TEAM>" build/macos/Build/Products/Release/SeeWow.app

# 3) 打包 + 公证 + 装订
ditto -c -k --keepParent build/macos/Build/Products/Release/SeeWow.app SeeWow.zip
xcrun notarytool submit SeeWow.zip --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple build/macos/Build/Products/Release/SeeWow.app
spctl -a -vvv -t install build/macos/Build/Products/Release/SeeWow.app
```

Entitlements 要点：
- `com.apple.security.network.client`（SMB/WebDAV/Emby）
- `com.apple.security.files.user-selected.read-write`（本地文件）
- 如果需要加载第三方 dylib 且签名团队不一致，才需要 `com.apple.security.cs.disable-library-validation`；**先尝试不加**，加了会被审核/安全工具标记。
- 沙箱：Developer ID 分发**不强制** App Sandbox；SeeWow 需要挂载网络卷，**建议不开沙箱**（MAS 版本才强制，而 MAS 版本会因 NetFS 挂载受限而不建议做）。

**不上 MAS 的理由**：沙箱下 NetFS 挂载行为待验证、libmpv 的动态库加载、以及 SMB 直连的权限模型都会成为审核风险；而 SeeWow 的分发不依赖商店。

### 4.2 Windows：MSIX + Inno 双轨

[MSIX 签名要求](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)：MSIX **必须**用有效代码签名证书签名，且证书必须链到设备信任根才能安装。

| 场景 | 方案 | 成本 |
|---|---|---|
| 内部测试 | 自签名证书 + 手动安装根证书 | 免费 |
| 生产（推荐） | **Azure Artifact Signing（原 Trusted Signing）Basic** | 约 $10/月 |
| 生产（传统） | OV 代码签名证书 | $300–500/年 |
| Microsoft Store | 商店代签 | 免费 |

工程要点：
- `msix` 包生成 MSIX；`Publisher` 必须与证书 Subject **逐字一致**，否则安装报 `0x800B0109`。
- 同时产出 Inno Setup 的 `.exe` 安装包给直下用户；两条线都要 Authenticode 签名，否则 SmartScreen 会拦。
- 注意：**签名不等于立刻没有 SmartScreen 警告**。OV 证书需要积累下载信誉，EV 证书才有即时信誉；Azure Trusted Signing 属于身份型信誉，随 publisher 累积。
- Windows ARM64：media_kit 的 ARM64 ANGLE 支持仍在 PR 阶段（[#1436](https://github.com/media-kit/media-kit/pull/1436) OPEN，2026-08-02），**v1 只发 x64**。

### 4.3 Linux：AppImage 优先，Flatpak 二期

Flutter 官方 Linux 部署页主推 Snap，同时列出 `fastforge`（AppImage/deb/pacman/rpm）与 `flatpak-flutter`。

| 格式 | 优点 | 坑 |
|---|---|---|
| **AppImage** | 单文件、免安装、CI 简单 | 需在**老 glibc** 上构建（用 `ubuntu-22.04` runner）；不集成桌面菜单；FUSE 依赖 |
| **.deb** | 系统集成好 | 需要维护 Debian 打包；依赖声明 |
| **Flatpak** | 沙箱、自动更新 | **Flathub 要求从源码构建**（不能直接塞预编译 libmpv）；需要自己编 mpv/FFmpeg；gvfs 路径不可见 |
| **Snap** | 官方推荐 | 需要 Snap Store 账号；`--classic` 或严格模式的设备访问 |

Flatpak 权限（[sandbox-permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html)）至少需要：

```
--socket=wayland --socket=fallback-x11 --share=ipc
--device=dri                 # GPU / VAAPI 硬解必需
--share=network
--socket=pulseaudio
--filesystem=home            # 或用 portal（更安全但路径处理更麻烦）
--filesystem=/run/user/1000/gvfs   # 否则看不到 gvfs 挂载的 SMB
```

**建议**：v1 只发 AppImage + deb（在 `ubuntu-22.04` 上构建以保证 glibc 兼容），Flatpak 放到 v2 并单独评估 Flathub 的源码构建要求。

### 4.4 iPadOS：没有侧载这条路

| 方式 | 限制 |
|---|---|
| App Store | 需审核；媒体播放器本身合规，但需处理版权内容相关条款 |
| TestFlight | 外部测试最多 10,000 人，首个 build 需 Beta App Review |
| Ad Hoc | 需在开发者账号登记设备 UDID，**每产品族每年 100 台**（Apple 公开规则；[官方页面](https://developer.apple.com/help/account/devices/devices-overview) 未在正文给出数字，此数字标注为「公开规则，待以账号后台为准」） |
| Enterprise Program | 仅限内部员工，公开分发违反协议 |
| 免费个人签名 | 7 天有效、最多 3 个 App，仅开发用 |
| EU 侧载（DMA） | 仅限欧盟区、需公证与替代市场；[*具体条款待验证*]（Apple 的 DMA 页面当前只返回导航壳，未能抓到正文） |

**结论**：iPadOS 的真实分发路径只有 TestFlight（beta）与 App Store（正式）。这意味着：
- 不能依赖「用户自己装 IPA」；
- 任何需要越权的能力（后台常驻、系统级挂载）都不要设计进 iPad 版；
- 审核周期要计入发布节奏。

### 4.5 Android

- Play 要求 AAB；用 `--split-per-abi` 控制体积（media_kit 的 .so 每架构数 MB）。
- 需 64-bit；`abiFilters` 只保留 `arm64-v8a` + `armeabi-v7a`（平板可只发 arm64）。
- **16 KB 页大小**：Google Play 对面向 Android 15+ 的应用有 16 KB page size 要求（2025-11 起生效）；media_kit 预编译 `.so` 是否已 16 KB 对齐 **待验证**，这会影响能否上架。
- 平板适配：`android:resizeableActivity="true"`、`supports-screens` 大屏、ChromeOS。

### 4.6 CI 矩阵建议（GitHub Actions）

Runner 事实（[actions/runner-images README](https://github.com/actions/runner-images)，2026-11）：macOS 26 / macOS 26 Arm64 / macOS 15 / macOS 15 Arm64 可用，**macOS 14 已 deprecated**；Windows Server 2025 / 2022；Ubuntu 26.04 / 24.04 / 22.04（含 Arm64）。label 形如 `macos-15`、`macos-15-arm64`、`windows-2025`、`ubuntu-22.04`。

| Job | Runner | 产物 | 关键步骤 |
|---|---|---|---|
| `build-macos-arm64` | `macos-15-arm64` | `.app` → `.dmg` | flutter build → 逐 dylib 签名 → notarytool → staple |
| `build-macos-x64` | `macos-15` | `.app` | 同上（若需 universal，两个产物 `lipo` 合并，**Flutter 插件双架构支持待验证**） |
| `build-windows` | `windows-2025` | `.msix` + Inno `.exe` | flutter build → 签名 → msix pack → iscc |
| `build-linux` | `ubuntu-22.04` | `.AppImage` + `.deb` | 装 GTK/mpv 依赖 → build → fastforge |
| `build-linux-arm64` | `ubuntu-22.04-arm64` | `.AppImage` | 可选，平板/ARM 笔记本 |
| `build-android` | `ubuntu-24.04` | `.aab` + split APKs | JDK 17 → gradle 缓存 → 签名 |
| `build-ios` | `macos-15` | `.ipa`（TestFlight） | 证书用 fastlane match 或 App Store Connect API Key |
| `perf-regression` | `macos-15` | 报告 | 23.976fps 素材 60s + 控制栏动画，FrameTiming 采样 |

通用建议：
- `subosito/flutter-action` 锁死 Flutter 版本（不要 `channel: stable` 漂移）。
- 缓存：pub cache、CocoaPods、Gradle、`~/.cargo`（若引入 Rust）。
- 密钥全部走 GitHub Environments + OIDC（Android/Apple 均支持免长期密钥），不要放 repo secrets 明文。
- 公证凭据用 `notarytool store-credentials` 存到 runner 的临时 keychain，或用 App Store Connect API Key。

---
## 5. 结论：坚持 Flutter，还是混合？

### 5.1 判定框架：哪些能力「必须在原生层」

把需求逐条过一遍「Flutter 能不能做」：

| 需求 | 纯 Flutter 可行？ | 必须下沉原生？ |
|---|---|---|
| 片库 / 导航 / 动画 / 设计语言 | ✅ 完全可行，且是 Flutter 的强项 | 否 |
| 播放（解码 / seek / 音轨字幕） | ✅ 通过 media_kit | 否，但需要 patch |
| SMB 传输 | ❌ 无系统 API（移动），桌面需三套平台代码 | **是** |
| HDR / 杜比视界 | ❌ 结构性不可能（纹理 8-bit + 无 gpu-next） | **是**（若要真 HDR） |
| 音频直通（Atmos/DTS-X） | ❌ media_kit 未暴露 | **是**（若要家庭影院） |
| DLNA 组播发现 | ⚠️ 需平台权限 + 插件 | 部分 |
| 帧预览缩略图 | ⚠️ 可用 ffmpeg 子进程/库，但要自己搭 | 部分 |

结论：**表现层 100% 留在 Flutter，能力层（播放宿主、传输、HDR）下沉原生**。这不是「混合开发」的妥协，而是把 Flutter 用在它最强的地方。

### 5.2 推荐的三种架构对比

| | A. 纯 Flutter | B. Flutter UI + 原生能力层（推荐） | C. Rust 核心 + Flutter 壳 |
|---|---|---|---|
| 架构 | Dart 调 media_kit | Dart UI + 少量 C/C++/Swift/Kotlin 插件 | Rust 实现播放/传输，FFI 到 Flutter |
| 工期（v1） | 最短 | 中（+4–6 周） | 最长（+3–4 月） |
| HDR | ❌ | ✅ 可增量做 | ✅ |
| SMB 五端 | ❌ | ✅ | ✅ |
| 风险 | 卡在 HDR/SMB，返工 | 平台代码分散（3–5 套） | Rust 音视频生态不成熟、招人难、调试成本高 |
| 团队要求 | Flutter | Flutter + 各平台基础 | Flutter + Rust + 音视频 |

**选 B。** 理由：
1. media_kit 已经把「libmpv 跨端」这件事做完了，重写不划算；它的缺陷集中在**输出层**与**传输层**，而这两层恰好可以单独替换。
2. HDR 的正确解法是「用平台原生播放器」（AVPlayer / D3D11 swapchain），这本身就是原生代码，与是否用 Rust 无关。
3. Rust 的收益主要在「一套代码覆盖五端的网络/解析核心」；但 SMB 已经有 libsmb2（C），Emby/Jellyfin/Plex 是 HTTP + JSON，用 Dart 写完全够。Rust 在这里的边际收益低于它的引入成本。

### 5.3 目标架构

```mermaid
flowchart TB
  subgraph Flutter["Flutter 表现层（Dart）"]
    UI[片库 / 播放器 UI / 动效]
    RES[MediaResolver<br/>统一 PlayableUri]
    UI --> RES
  end

  subgraph Native["原生能力层"]
    MOUNT[SMB 挂载<br/>NetFS / WNet / gvfs]
    BRIDGE[HTTP Range 桥<br/>libsmb2]
    PLAYER[播放宿主<br/>media_kit / AVPlayer]
    HDR[HDR 输出<br/>AVPlayerLayer / D3D11 swapchain]
  end

  RES --> MOUNT
  RES --> BRIDGE
  MOUNT --> PLAYER
  BRIDGE --> PLAYER
  PLAYER -.HDR 内容.-> HDR
```

分层原则：
- **Dart 层不出现平台判断**（除能力探测）；所有平台差异收敛在 `MediaResolver` 与 `PlaybackHost` 两个接口后面。
- **播放器只接受 `file://` 或 `http://127.0.0.1`**，这是防火墙式的约束，能避免后续每加一个源就改播放器。
- **HDR 是一条旁路**：默认走 media_kit（SDR），检测到 HDR/DV 且用户开启「HDR 模式」时，切到原生宿主。UI 上必须有明确的降级提示。

### 5.4 十条决策要点

1. **坚持 Flutter，但重新定义它的边界**：Flutter 只做表现层；播放宿主与传输层是原生能力层，不是「以后再说」。
2. **media_kit 锁 1.2.6 + 本地补丁**（`block_for_target_time=0`，#1439），用 git dependency 固定 commit；禁止 `^` 自动升级。
3. **播放器页面单实例 Player**，#1472（Windows 多 Player 同帧 dispose 崩溃）是硬约束；网格预览用独立解码器。
4. **v1 不承诺 HDR**，但播放页必须预留原生视图槽位；HDR 立项时走 AVPlayer（Apple）/ 原生 swapchain（桌面），不在 Flutter 纹理里挣扎。
5. **SMB 三轨并行**：桌面系统挂载（NetFS/WNet/gvfs），移动 libsmb2 + 本地 HTTP Range 桥，**永不直接播 `smb://`**。
6. **所有媒体源收敛为 `file://` 或 `http://127.0.0.1:PORT/`**，由 `MediaResolver` 统一负责凭据、重连与清理。
7. **性能红线进 CI**：23.976fps 素材 + 控制栏动画跑 60s，raster p95 < 12ms、jank < 1%；视频纹理尺寸不得超过显示尺寸。
8. **视觉规范硬约束**：禁止 BackdropFilter 压视频；颗粒/暗角静态化并隔离在 RepaintBoundary；Hero 转场用海报替身。
9. **分发策略**：macOS Developer ID + notarytool（放弃 MAS）；Windows MSIX + Inno 双轨（Azure Trusted Signing）；Linux 先 AppImage/deb、Flatpak 二期；iPadOS 只走 TestFlight/App Store。
10. **不引入 Rust**，除非出现「Dart/原生都解决不了」的具体问题（例如自建 FFmpeg 协议栈）；届时以独立 crate + FFI 增量引入，不重写播放器。

---

## 6. 风险登记与待验证清单

### 6.1 待验证（按优先级）

| # | 事项 | 验证方式 | 影响 |
|---|---|---|---|
| V1 | `dart_smb2` 0.2.4 在真实 NAS 上的吞吐与 seek 延迟 | 2 天 spike：Synology/QNAP + 20GB 4K 文件，测顺序读、随机 seek、断线重连 | 决定 P2 是依赖它还是自建 FFI |
| V2 | macOS 沙箱下 NetFS 挂载是否被拒 | 开沙箱跑 `NetFSMountURLSync` | 决定是否放弃 MAS |
| V3 | media_kit iOS 纹理的实际 pixel format（是否 8-bit BGRA） | 读 `TextureHW.swift` + 真机抓帧 | 确认 iOS 也无 HDR |
| V4 | media_kit 预编译 `.so` 是否 16 KB page 对齐 | `llvm-readelf -l` 检查 PT_LOAD 对齐 | 决定能否上架 Google Play（Android 15+） |
| V5 | Windows ARM64 的 libmpv/ANGLE 可用性 | 跟 [#1436](https://github.com/media-kit/media-kit/pull/1436) 进展 | 决定是否发 ARM64 包 |
| V6 | Flatpak 内 gvfs SMB 路径可见性 | 打一个 Flatpak 包，`--filesystem=/run/user/1000/gvfs` 后读挂载点 | 决定 Flatpak 的 SMB 支持 |
| V7 | macOS 上是否存在与 #1439 同类的 raster 阻塞 | Instruments + FrameTiming 测 23.976fps 素材 | 决定是否需要 macOS 补丁 |
| V8 | Flutter macOS 双架构（universal）构建 | `ARCHS="arm64 x86_64"` 构建 + media_kit 插件验证 | 决定 CI 是否需要两个 macOS job |
| V9 | EU DMA 侧载的具体条款 | Apple 官方开发者页面（当前抓取只返回导航壳） | 影响 iPadOS 分发策略（低） |

### 6.2 主要风险

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| media_kit 停止维护 | 中 | 高 | 保持 fork 能力；播放接口抽象成 `PlaybackHost`，可替换为自建 libmpv 封装 |
| `dart_smb2` 夭折 | 高（v0.x，两天新） | 中 | 自建 libsmb2 FFI 的成本可控（~2 周），保留退路 |
| HDR 需求被提前 | 中 | 高（架构返工） | 现在就在播放页留原生槽位 |
| Linux Wayland 兼容性 | 中 | 中 | 优先 X11 兜底 + 记录 #1463；Flatpak 二期 |
| 签名/公证流程拖慢发布 | 低 | 中 | CI 里从第一天就跑签名流水线，不要等到发布前 |

---

## 7. 参考来源

**media_kit / mpv**
- [media_kit on pub.dev](https://pub.dev/packages/media_kit)（1.2.6，2025-12-13）
- [media_kit_video on pub.dev](https://pub.dev/packages/media_kit_video)（2.0.1，2025-12-02）
- [media_kit_video/linux/texture_gl.cc](https://github.com/media-kit/media-kit/blob/main/media_kit_video/linux/texture_gl.cc)
- [media_kit_video/windows/angle_surface_manager.cc](https://github.com/media-kit/media-kit/blob/main/media_kit_video/windows/angle_surface_manager.cc)
- [mpv#10810 — Support for libplacebo (gpu-next) in the rendering API](https://github.com/mpv-player/mpv/issues/10810)
- media_kit issues: [#1472](https://github.com/media-kit/media-kit/issues/1472)、[#1471](https://github.com/media-kit/media-kit/issues/1471)、[#1463](https://github.com/media-kit/media-kit/issues/1463)、[#1439](https://github.com/media-kit/media-kit/issues/1439)、[#1354](https://github.com/media-kit/media-kit/issues/1354)、[#1243](https://github.com/media-kit/media-kit/issues/1243)、[#1207](https://github.com/media-kit/media-kit/issues/1207)、[#1445](https://github.com/media-kit/media-kit/issues/1445)、[#1093](https://github.com/media-kit/media-kit/issues/1093)、[#952](https://github.com/media-kit/media-kit/issues/952)、[#777](https://github.com/media-kit/media-kit/issues/777)、[#573](https://github.com/media-kit/media-kit/issues/573)、[#184](https://github.com/media-kit/media-kit/issues/184)、[#68](https://github.com/media-kit/media-kit/issues/68)
- [PR #1436 — feat(windows): ARM64 ANGLE + libmpv 0.41.0](https://github.com/media-kit/media-kit/pull/1436)

**SMB**
- [libsmb2](https://github.com/sahlberg/libsmb2)
- [dart_smb2 on pub.dev](https://pub.dev/packages/dart_smb2)（0.2.4，2026-11-02）
- [smb_connect on pub.dev](https://pub.dev/packages/smb_connect)（0.0.9，2025-01-25）
- [FFmpeg protocols — libsmbclient](https://ffmpeg.org/ffmpeg-protocols.html)
- [WNetAddConnection2W](https://learn.microsoft.com/en-us/windows/win32/api/winnetwk/nf-winnetwk-wnetaddconnection2w)
- macOS SDK：`NetFS.framework/Headers/NetFS.h`（`NetFSMountURLSync` 第 312 行，`__IPHONE_NA`）

**Flutter / Impeller / 性能**
- [Impeller](https://docs.flutter.dev/perf/impeller)
- [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices)
- [What's new in Flutter 3](https://flutter.dev/blog/whats-new-in-flutter-3)（iOS ProMotion）
- [flutter#161297](https://github.com/flutter/flutter/issues/161297)、[flutter#126353](https://github.com/flutter/flutter/issues/126353)

**打包与签名**
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [MSIX signing package overview](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)
- [Flatpak sandbox permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html)
- [Flutter Windows deployment](https://docs.flutter.dev/deployment/windows)
- [Flutter Linux deployment](https://docs.flutter.dev/deployment/linux)
- [actions/runner-images](https://github.com/actions/runner-images)

---

## 附录：给 lead 的五条关键结论

1. **media_kit 1.2.6 可用作 v1 内核，但 HDR/杜比视界在 Flutter 纹理路径上结构性不可行**（mpv 渲染 API 无 gpu-next + 8-bit 纹理 + 无 HDR metadata 送 OS），必须靠 AVPlayer / 原生 swapchain 旁路解决。
2. **Linux 上 30fps 视频会把 UI 拖到 43–51Hz**（#1439，每帧阻塞 17–25ms），修复仅在 main 分支，必须 fork 或 patch，这是「60fps 动画」能否成立的先决条件。
3. **`smb://` 不能直连播放**（FFmpeg 无 libsmbclient、libmpv 未链接），SMB 必须走「桌面系统挂载 + 移动 libsmb2 + 本地 HTTP Range 桥」，没有一条代码路径覆盖五端。
4. **性能瓶颈是视频纹理带宽与叠加特效，而非 Impeller 本身**：4K@60 单次采样就需约 2 GB/s，禁止 BackdropFilter 压视频、颗粒/暗角必须静态化并隔离重绘。
5. **结论是「Flutter UI + 原生能力层」，不是纯 Flutter，也不是 Rust 重写**；v1 不引入 Rust，把播放宿主与传输层抽成可替换接口即可。
