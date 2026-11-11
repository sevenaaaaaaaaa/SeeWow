# iOS / iPadOS 预览包

当前版本：1.6.0 (7)，Bundle ID `com.seewow.seewow`，最低 iOS 15，真机 ARM64，支持 iPhone / iPad。

## 本轮适配

- iOS 原生钥匙串读写与删除，失败时不回落到明文文件或尝试启动 chmod 子进程。
- 系统 Files 文件夹选择，保存访问书签并在应用启动时恢复授权。若用户移动或撤销原目录，请重新选择目录。
- 局域网访问说明，以及用户自建 HTTP NAS / WebDAV / 网关的连接配置。
- 手机播放按钮、安全区、竖屏控制栏与横屏全屏切换。全屏保持原播放控制层，退出时恢复系统方向策略。
- 三套主题、皮肤工作室、媒体库和现有服务器适配随 iOS 构建交付。
- 移动端 NAS 默认选择 WebDAV / File Station / OpenList；SMB 系统挂载仍仅支持桌面端。

## 构建 IPA

在仓库根目录运行：

```sh
apps/seewow/tool/build_ios_ipa.sh --no-pub
```

脚本先生成 iPhoneOS Release，再验证目标平台，打包 `Payload/SeeWow.app`，输出可重签 IPA 与 SHA-256。它不会打包模拟器二进制。

输出：`dist/SeeWow-iOS-1.6.0-arm64-unsigned.ipa`。

当前机器中 Apple Development 证书有效且团队匹配，但 Xcode 没有配置开发者账号，也没有本 App 的 provisioning profile。标准开发签名导出因此失败。本包按用户提供的证书和安装工具重签使用；它不是 App Store / TestFlight 包，也不是已签名的直接安装包。

## 验证记录

- 94 项 Flutter 自动化测试通过；静态分析无 error / warning，仍有 info 级 lint。
- iOS 真机 ARM64 Release 构建通过；Mach-O 平台为 IOS，最低系统为 15.0。
- 上一版 1.5.0 的 iOS Simulator Debug 构建通过；1.6.0 完成真机 ARM64 Release 编译和共用界面的组件测试。当前 Xcode 环境缺少 Simulator 图形应用，未完成 1.6.0 的模拟器界面与实际播放验收；未连接真实 iPhone / iPad 进行安装测试。
- IPA ZIP 完整性、包目录、设备架构和校验和经过检查。

重生成 iOS 图标：

```sh
swift apps/seewow/tool/generate_ios_icon.swift apps/seewow/ios/Runner/Assets.xcassets/AppIcon.appiconset
```
