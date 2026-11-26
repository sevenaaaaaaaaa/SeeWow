# iOS / iPadOS 预览包

Bundle ID `com.seewow.seewow`，最低 iOS 15，真机 ARM64，支持 iPhone / iPad。
代码基线跟随主仓（当前为 1.22.0+35 加 1.22.1 未发版打磨；版本号以 `pubspec.yaml` 为准）。

## 平台适配现状

随同一套 Flutter 代码交付的能力（媒体库 / 播放 / 直播 / 离线缓存 / 在线源 / Agent / 皮肤）不再逐条罗列，见 [对齐说明](parity.md)。这里只记录 iOS 原生层：

- **凭据**：iOS 原生钥匙串读写与删除，失败时不回落到明文文件或尝试启动 chmod 子进程。
- **本地文件夹**：系统 Files 文件夹选择，保存访问书签并在应用启动时恢复授权。若用户移动或撤销原目录，请重新选择目录。
- **画中画**：AVKit 系统 PiP，带手机内回环代理（127.0.0.1）注入认证头；代理随 App 进程运行，强制退出后失效。PiP 内不做画面手势与控制台，退出回传时间点。
- **锁屏与后台**：playback 音频会话、MPRemoteCommandCenter 播放控制、NowPlaying 元数据；后台默认关闭，用户开启后启用。
- **音频路由保护**：CoreAudio 当前路由查询，敏感内容与外放保持静音的语义与桌面一致。
- **自动解说（1.22.1 补齐）**：桌面用 `say` / SAPI / espeak 子进程，iOS 沙箱不允许 spawn，因此走 `seewow/voice` 通道由 AVSpeechSynthesizer 离线渲染 16 位单声道 PCM WAV，与桌面产物等价；无系统语音时如实不可用，不回落在线服务。**真机行为未验证。**
- 移动端 NAS 默认选择 WebDAV / File Station / OpenList；SMB 系统挂载仍仅支持桌面端（系统无公开 SMB API）。
- Rust 内核（trickplay 加速等）不进 iOS（路线图 D-12）；章节走 mpv 内嵌信息路径，不受影响。

## 构建 IPA

在仓库根目录运行：

```sh
apps/seewow/tool/build_ios_ipa.sh --no-pub
```

脚本先生成 iPhoneOS Release，再验证目标平台，打包 `Payload/SeeWow.app`，输出可重签 IPA 与 SHA-256。它不会打包模拟器二进制。

输出：`dist/SeeWow-iOS-<版本号>-arm64-unsigned.ipa`。

当前机器中 Apple Development 证书有效且团队匹配，但 Xcode 没有配置开发者账号，也没有本 App 的 provisioning profile。标准开发签名导出因此失败。本包按用户提供的证书和安装工具重签使用；它不是 App Store / TestFlight 包，也不是已签名的直接安装包。

## 验证记录（1.22.1 打磨，2026-11-26）

- `flutter test` 613 项通过 / 2 项按需跳过（新增 5 项 iOS 语音后端通道协议测试）。
- `flutter analyze` 104 条 info、0 error / 0 warning；剩余全部是 SDK 对 `material.dart` 导入的弃用提示（迁移决策见 [1.22.1](releases/1.22.1.md)）。
- 真机 ARM64 Release 构建通过并打包 IPA；Mach-O 平台为 IOS，最低系统 15.0。
- AVSpeechSynthesizer 渲染路径只有模拟器/编译验证，未连接真实 iPhone / iPad：解说音色、文件时长校准与锁屏交互都待真机确认。
- IPA ZIP 完整性、包目录、设备架构和校验和经过检查。

重生成 iOS 图标：

```sh
swift apps/seewow/tool/generate_ios_icon.swift apps/seewow/ios/Runner/Assets.xcassets/AppIcon.appiconset
```
