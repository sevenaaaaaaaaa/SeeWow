# SeeWow 开放皮肤格式 · v1

在「设置 → 外观与皮肤」切换曜黑、素白、流光玻璃。打开皮肤工作室可自定义当前皮肤、导入社区作者的 JSON / Markdown，或从 design.md 生成。当前提供本地导入导出与两个格式示例，尚未提供在线社区商店、账号或发布服务。

## 分享与使用

1. 载入 `example.seewow-skin.json` 或根目录 `design.md`。
2. 通过工作室修改并预览。取消保留当前外观；「应用并保存」后全局切换并保存到本机。
3. 导出 JSON 或复制给其他用户。导入支持 JSON，或 Markdown 中的 `seewow-skin` / `json` 代码块。自由描述请走 design.md 的 AI 生成入口。

## 参数

- `schemaVersion`: `1`。
- `name` / `author`: 最长 60 字符；`description` 最长 500 字符。
- `mode`: `dark` 或 `light`。改变全局 Material 明暗模式。
- `material`: `flat` 或 `glass`。玻璃使用应用内部背景与局部模糊；不是 macOS 桌面穿透效果。
- `font`: `sans` / `editorial` / `humanist` / `geometric`，使用内置或系统回退字体。
- `density`: `comfortable` / `compact`，影响控件与片库网格。
- `radius`: 面板圆角 0–28；`posterRadius`: 海报圆角 0–24。
- `blur`: 0–40；`opacity`: 0.65–0.98，仅玻璃材质使用。系统减少动画时关闭表面模糊。
- `colors`: 必须完整包含 `background`、`shell`、`panel`、`text`、`muted`、`faint`、`accent`、`line`、`ambient`、`success`、`error`，均为 `#RRGGBB`。

`text` 和 `muted` 与三类底色的对比度至少 4.5:1；强调色与面板至少 3:1。不合法的皮肤不会替换当前主题。影片画面、海报角标和播放区域保留独立的深色遮罩，避免浅色模式破坏画面上的文字可读性。

## design.md 生成

本地生成接受 `key: value` 或 Markdown 参数表，默认补齐所选明暗基础主题中未指定的参数。完整 JSON 代码块也可直接使用。自由描述通过用户配置的 Chat Completions 兼容模型生成；界面会显示服务主机，仅发送当前设计文档，不发送片库。模型结果也必须通过同样的格式与对比度校验，失败时保留当前主题。

文件上限 64 KB，本机最多保存 40 个皮肤。皮肤声明不支持脚本、远程图片、字体下载、自定义代码或布局替换。
