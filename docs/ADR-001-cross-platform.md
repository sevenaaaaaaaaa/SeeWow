# ADR-001：SeeWow 跨平台架构（macOS / Windows / Linux / 平板）

- 状态：已采纳
- 日期：2026-11-05
- 背景：现有 `Sources/SeeWow` 是 SwiftUI macOS 原型，视觉与交互已成型，但无法覆盖 Windows、Linux 与平板。

## 决策

采用 **Flutter + media_kit（libmpv）** 作为唯一客户端代码库，覆盖：

| 平台 | 产物 | 播放内核 |
|---|---|---|
| macOS | .app / .dmg（Developer ID + 公证） | libmpv（media_kit），保留 AVFoundation 选项 |
| Windows 10/11 | MSIX + Inno Setup 安装包 | libmpv（media_kit） |
| Linux | AppImage / .deb / Flatpak | libmpv（media_kit） |
| iPadOS / iOS | IPA（iPad 优先） | libmpv / AVFoundation 可切换 |
| Android 平板 | APK / AAB | libmpv（media_kit） |

SwiftUI 版本保留为 `legacy/macos-swift`（视觉与交互参考实现），不再作为主线。

## 理由

1. **一套 UI 覆盖全部目标**：Flutter 自绘引擎在 Windows/Linux/Android/iPadOS 上像素一致，才能做「同一套 Cinema Editorial」和复杂转场；SwiftUI 只覆盖 Apple，Kotlin Multiplatform 的 Windows 端不成熟，Electron 体积与视频色彩管理不可控。
2. **播放统一**：media_kit 把 libmpv 封装为纹理，桌面与 Android 共用同一套解码/字幕/音轨能力，避免每个平台各写一套播放器。HDR/杜比视界在桌面由 libmpv 的 gpu-next 处理；iOS/iPadOS 可切 AVFoundation 以拿到系统级 HDR。
3. **交互上限高**：Flutter 的 CustomPainter / 隐式动画 / 手势系统足以实现 Hero 动态预览、帧预览、3D 倾斜、空间转场；表格与移动端共用一套响应式断点。
4. **工程可持续**：Dart 单语言、热重载、CI 矩阵（GitHub Actions）可同时出五端包。

## 模块划分

```
lib/
  app/            路由、主题、启动
  design/         设计令牌、字体、动效、组件（Cinema Editorial）
  domain/         MediaItem / Source / PlaybackTarget / EPG
  data/
    providers/    local / smb / webdav / emby / jellyfin / plex / dlna / iptv
    metadata/     TMDB + 本地 NFO/海报
    store/        SQLite（drift）+ 设置 + 安全凭据
  playback/       media_kit 封装、字幕、进度回写、画中画
  features/       home / library / detail / player / live / settings / search
```

## SMB 策略（分阶段）

- **阶段一**：WebDAV + Emby/Jellyfin/Plex + 本地目录，覆盖大多数 NAS 用户。
- **阶段二**：平台原生挂载（macOS NetFS、Windows WNetAddConnection2、Linux gvfs），通过 MethodChannel 暴露统一 `SmbMount` 接口。
- **阶段三**：libsmb2 FFI 直连（含 iOS/Android），避免依赖系统挂载。

## 后果

- 需要引入 Flutter/Dart 工具链与 media_kit 依赖；安装包体积增加（libmpv 约 30–60 MB）。
- 需要重写已有 SwiftUI 界面与数据层，但设计规范、Provider 协议、解析规则可逐条移植。
- 桌面端 HDR 色彩管理需逐平台验证；Windows 的 HDR 直通与 Linux/Wayland 是重点测试项。
