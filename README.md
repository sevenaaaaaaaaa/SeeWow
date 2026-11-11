# SeeWow

**Cinema, made personal.** 一个以私人媒体库为中心的跨平台播放器，使用 Flutter + media_kit / libmpv。

当前工作区为 **1.6.0 体验预览版**。新增默认关闭的 [AI 字幕与小映陪看](docs/ai-watch.md)：自行配置 API，翻译已有字幕，按需解释台词、情节与场景。支持三套主题、皮肤工作室和 design.md 生成，详见 [皮肤说明](skins/README.md) 与 [design.md 模板](design.md)。

## 下载 1.6.0 体验预览版

完整更新记录见 [1.6.0 发布说明](docs/releases/1.6.0.md)，安装包与 SHA-256 校验文件见 [GitHub Release](https://github.com/sevenaaaaaaaaa/SeeWow/releases/tag/v1.6.0)。

| 平台 | 安装包 | 安装与签名状态 |
| --- | --- | --- |
| macOS Apple Silicon | [下载 ZIP](https://github.com/sevenaaaaaaaaa/SeeWow/releases/download/v1.6.0/SeeWow-macos-1.6.0-preview.zip) | 解压后将应用移到「应用程序」；临时签名、未公证 |
| Android | [下载 APK](https://github.com/sevenaaaaaaaaa/SeeWow/releases/download/v1.6.0/SeeWow-Android-1.6.0-preview.apk) | Android 7.0+；Release 编译、开发签名预览包 |
| iOS / iPadOS ARM64 | [下载 IPA](https://github.com/sevenaaaaaaaaa/SeeWow/releases/download/v1.6.0/SeeWow-iOS-1.6.0-arm64-unsigned.ipa) | iOS 15+；未签名，需使用自己的证书与描述文件重签 |

Windows / Linux 本轮未提供 1.6.0 安装包。AI 功能默认关闭，需要用户自行配置 API；使用前请阅读 [功能与数据说明](docs/ai-watch.md)。

片源能力包括服务选择器、Plex / File Station / Navidrome 适配、OpenList / Alist API 扫描与动态直链，以及本地 / SMB / WebDAV 的中文 NFO 读取。以下区分已经实现与尚未支持的能力。

## 从连接到观看

1. 在「片源与订阅」连接本地目录、SMB / NAS、WebDAV、Plex、Jellyfin / Emby、群晖 File Station、OpenList / Alist 或 M3U；Navidrome 曲目可在「音乐库」查看。
2. 「媒体库」统一查看影片，按来源、类型、电影/剧集、观看状态筛选，按片名、年份、评分或入库时间排序。
3. 首页「调整我的口味」选择偏好。影片菜单可以喜欢、不感兴趣、加入待看、标记已看。
4. 在 Agent 中描述需求，查看逐步执行结果，把挑选结果保存到「我的片单」。
5. 播放时每约 5 秒更新一次本机进度，退出时再保存一次。返回详情与首页可看到更新后的状态。

iOS / iPadOS 已提供真机 ARM64 可重签 IPA，最低 iOS 15。包含钥匙串、Files 文件夹授权和手机播放控制适配；构建方式、签名状态及验证范围见 [iOS 构建说明](docs/ios-build.md)。

## 已实现

| 能力 | 当前行为 |
| --- | --- |
| AI 字幕与陪看 | 默认关闭，用户自配 API；翻译内嵌文字字幕/外挂 SRT、VTT，原文译文同显；小映按当前台词与时间点解释，视觉分析需额外开启并按次附带单张缩小截图；上下文和请求有界，不保存会话到片库 |
| 主题与皮肤 | 曜黑、素白、流光玻璃全局切换；颜色、字体、圆角、布局密度与材质编辑；社区 JSON / Markdown 本地导入导出；design.md 参数本地生成或用户模型 AI 生成，校验预览后应用 |
| 导航与搜索 | 桌面侧栏 / 平板图标栏 / 手机底部导航；顶部搜索与 ⌘K / Ctrl+K 搜索真实片库并跳转功能 |
| 首页 | 片库内推荐、继续观看、Agent 任务入口、可编辑的类型偏好；取消自动轮播和持续入场动效 |
| 媒体库 | 多条件组合筛选、全文关键词匹配、排序、海报/列表视图、批量选择、已看/未看、结果保存为片单 |
| 收藏与反馈 | 待看、喜欢、不感兴趣、类型偏好、观看时间和播放进度持久化；不感兴趣可从卡片菜单恢复 |
| 推荐 | 本地可解释排序，使用明确偏好、喜欢、观看反馈；支持类型、部分心情词、分钟数上限；排除已看与不感兴趣，减少同剧及同片重复 |
| 片单 | 保存搜索/筛选结果或 Agent 结果；重启后可重新打开；删除片单保留媒体文件 |
| 影片信息匹配 | 详情页搜索 TMDB，选择同名/年份候选、预览并确认；中文简介、评分、类型、海报和剧照可补全；默认保留本地/服务器图片；剧集匹配应用到同源整部剧，新扫描的集数可继承 |
| 媒体服务器 | Jellyfin / Emby API Key 接入，支持反向代理子路径、分页入库、电影/剧集、服务器海报与原文件直接播放；用户 ID 可选；分页中断保留旧片库 |
| 片库体检 | 查找疑似同名同年份同集重复、缺少海报/简介的条目；只列出待检查结果，不自动删除或合并；信息补全从详情页主动匹配 |
| 本地/NAS | 本地递归扫描；SMB 在 macOS 用 NetFS、Windows 用 net use、Linux 用 gio 挂载后扫描 |
| WebDAV / 网盘 | PROPFIND 扫描，Basic 认证、HTTP Range 播放；网盘通过用户自己的 WebDAV 网关（如 Alist / OpenList）接入 |
| OpenList / Alist API | 按挂载根目录递归建库；播放前调用网关获取新直链；云盘账号授权由网关维护；网关 Token 不跟随直链发送到云盘域名 |
| Plex | Token 接入，电影及逐集目录、海报和原文件播放；不使用客户端转码 |
| 群晖 File Station | DSM 账号只读列目录、扫描文件，播放前建立新会话；也可使用 SMB / WebDAV |
| Navidrome | OpenSubsonic 账号认证、曲目扫描、独立音乐库与原音频播放；播放认证签名只在运行时生成 |
| NFO 中文资料 | 本地 / SMB / WebDAV 自动读取同名 `.nfo`、`movie.nfo`、`tvshow.nfo`，解析中文标题、简介、类型、评分和时长；无效旁车回退文件名，不阻塞媒体播放 |
| 编辑连接 | 更新名称、地址、挂载根目录、账号或凭据；保留来源 ID，按稳定条目 ID 合并仍在扫描范围内的进度、收藏和已确认元数据 |
| 直播订阅 | M3U / M3U8 频道列表、XMLTV、分组、收藏、最近观看、订阅刷新 |
| 链接收集 | 从用户粘贴的地址识别链接，读取最多 3 个页面并收集 M3U / DAV 候选；候选可编辑连接，测试后导入 |
| 来源状态 | 显示扫描进度、上次成功时间、持久化错误；断网/扫描失败保留旧片库；同源并发扫描合并为一次 |
| 播放 | 播放/暂停、音量、快进/快退、全屏、倍速、键盘控制、播放失败提示、断点续播、进度回写 |

## Agent：规划 → 工具 → 可操作结果

Agent 工作区提供两种明确标注的模式：

- **本地规则**：无需密钥或模型。识别内置任务与部分偏好表达，调用本地推荐、搜索、体检、来源刷新和链接收集。它不是语言模型，也不理解任意自然语言。
- **AI 模型**：在「影院 Agent → 接入 AI 模型」填写完整的 Chat Completions 兼容接口地址、模型名和可选密钥。远程服务需 HTTPS，本机服务支持 HTTP。模型规划最多 5 个步骤，应用验证后调用受限工具。

工具集合为 `recommend`、`search_library`、`audit_library`、`refresh_sources`、`build_collection`。链接任务在本地单独路由到 `discover_sources`。刷新来源需要用户请求中明确包含扫描/刷新/同步意图；模型返回未知工具或片库外 ID 会使任务失败。片单先生成预览，再由用户保存；Agent 不删除原文件。

每次任务显示步骤、成功/失败/取消、结果和重试入口；最近 30 次任务落盘。可以停止模型或页面请求；来源扫描开始后会完成当前扫描，再跳过后续步骤，已经导入的数据保留。已完成任务的片单被删除后，可再次保存结果。模型连接失败不会伪装成本地模式成功。目录最多提供前 250 个条目，结果仅能引用其中真实存在的 ID。

**数据去向：**使用模型模式执行任务，会把本次需求、类型偏好和影片摘要（名称、类型、年份、时长、观看/反馈状态、ID）发到配置的服务。摘要不包含文件路径、片源地址、HTTP 认证头或凭据。链接任务在本地处理。密钥按服务 origin 隔离保存；macOS 使用钥匙串，其他平台使用权限受限的本机文件。

协议参考：[Chat Completions API](https://developers.openai.com/api/reference/resources/chat)。未绑定特定模型厂商，也不要求 OpenAI 账号。

## 诚实的边界

- **没有全网影片/订阅源搜索。**链接收集读取用户提供的网页；外部搜索引擎、资源质量验证和自动订阅策略尚未接入。
- **网盘首轮使用网关。**夸克、百度、UC、OneDrive、Google Drive、MEGA、123、115 提供明确的服务入口，通过 OpenList / Alist API 或 WebDAV 接入；需要先在网关配置对应驱动并完成授权。尚未提供这些网盘的原生 OAuth，也不能把分享链接直接当媒体库。
- **媒体服务器只读接入。**Jellyfin / Emby 使用 API Key，Plex 使用 Token；读取目录、已有元数据和原文件流，不回写服务端观看状态，不支持 Quick Connect / Plex 账号授权、转码协商或 DLNA。飞牛通过共享协议接入，飞牛影视专有接口仍待实现。
- **群晖会话限制。**File Station 账号需具有读取权限；需要二步验证的账号可先走 SMB / WebDAV。扫描结束注销扫描会话，播放时重新登录的会话由 DSM 超时回收。
- **音乐支持范围。**Navidrome 当前提供曲目目录、播放和本机进度；不包含歌词、专辑封面授权加载、服务端播放记录回写、转码、离线下载或完整音乐管理。
- **刮削范围。**NFO 是已有资料的导入，不等同于直接抓取豆瓣 / 时光网；当前在线匹配仍为 TMDB，媒体服务器沿用它们已有的刮削结果。NFO 读取支持本地、SMB 和 WebDAV；OpenList API / File Station 本轮只扫描媒体文件。
- **TMDB 需用户配置 Token。**在「影院偏好 → 影片信息补全」保存自己的 API Read Access Token，然后从详情页匹配。只在主动搜索/预览时发送片名和 TMDB ID；没有后台批量刮削、离线图片缓存或自动猜测匹配。匹配保留本地文件、进度与片单关系，并随重扫保留。
- 推荐仍受片库元数据质量影响。本地模式仅支持部分心情/类型表达；模型模式的挑选质量依赖用户配置的模型，目前没有嵌入索引、长期语义记忆或外部影片目录。
- 片单是保存时的条目快照，不是自动更新的订阅。重复检测是启发式检测，不是内容哈希校验或无损版本合并。
- 移动端 SMB、云同步、原生网盘直连、完整字幕/音轨选择、PiP、HDR / Dolby Vision 原生旁路、直播回看与时移仍待实现。
- Windows / Linux 的挂载逻辑与移动端包未在本轮真机验证；本轮构建与人工交互验证在 macOS 上进行。

## 开发与验证

前置为 Flutter 3.47.9 / Dart 3.13.7 及平台工具链。macOS 桌面播放依赖 libmpv；已有环境可直接构建。

```bash
cd apps/seewow
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run -d macos
flutter build macos --release
```

现有代码仍有历史 info 级 lint；验证要求无 analyzer error / warning。测试覆盖文件名、M3U/XMLTV、WebDAV/SMB 解析，以及偏好/片单持久化、扫描失败恢复、并发扫描、模型规划校验、错误恢复、链接收集、搜索交互和响应式布局。兼容模型、TMDB 和媒体服务器协议通过本机模拟 HTTP 服务验证；元数据确认流程、窄屏服务选择器、服务器 / 网关表单有组件测试。当前共 94 项测试，新增换肤、皮肤导入、design.md 生成、草稿取消与恢复、AI 生成协议测试；其余测试覆盖目录递归、分页中断、动态直链、跨域跳转的 Token 隔离、群晖会话、Navidrome 盐值签名、NFO 与来源编辑。没有使用用户的真实模型、TMDB 或 NAS 凭据进行外部调用，真实服务器兼容性还需实际连接验证。

`SEEWOW_SHOTS=1 flutter test test/experience_test.dart` 可生成 `/tmp/seewow-experience-shots/` 布局截图。测试在 macOS 可加载系统字体；其他系统使用默认测试字体。普通 CI 不需要 `DemoMedia/`。

启动可使用 `SEEWOW_LAUNCH=home|library|collections|sources|agent|live|music|settings|detail|play`。兼容旧 `movies`、`tv`、`playweb`、`liveplay` 参数。

## 数据与代码

数据位置：平台 application-support 目录下的 `SeeWow/`，macOS 通常为 `~/Library/Application Support/com.seewow.seewow/SeeWow/`。

- `library.json`：来源、媒体、已确认的元数据匹配、偏好、待看、片单、播放记录、来源错误；写入串行化，临时文件完成后重命名。
- `agent.json`：模型接口配置与最近任务；不保存 API Key。
- 认证头（Authorization / Cookie / X-Emby-Token 等）不再写入新的片库快照；启动时从来源凭据恢复。媒体服务器凭据不会发送给 TMDB 图片站点或模型服务。
- `skin.json`：已有界面偏好。新安装默认石墨、无衬线、纯平；已有偏好保留。
- `iptv.json`：直播频道、订阅与节目单。订阅链接可能包含用户提供的访问令牌，应视为私人本机数据。

```text
apps/seewow/lib/
  app/          应用壳、启动、主题、命令搜索
  agent/        受限规划执行器、任务记录、链接收集
  domain/       媒体模型、偏好、推荐、查询、体检、IPTV/XMLTV
  data/         片库持久化、本地扫描、直播状态
  sources/      本地/SMB/WebDAV/Plex/Jellyfin/Emby/OpenList/FileStation/Navidrome 适配与播放解析
  metadata/     TMDB 搜索与详情、NFO 旁车读取
  features/     首页、媒体库、片单、来源、Agent、详情、直播、设置
  playback/     media_kit 播放器
  design/       共享令牌与界面组件
```

当前设计规则见 [设计系统](docs/seewow/design-system/seewow/MASTER.md)。`docs/screens/`、`docs/design-lab/` 与旧 HTML preview 保留 1.1 版历史参考，不代表当前主界面。根目录 `Sources/` 为保留的 SwiftUI 原型，主实现位于 `apps/seewow/`。

元数据接口参考：[TMDB 搜索](https://developer.themoviedb.org/reference/search-movie)、[详情](https://developer.themoviedb.org/reference/movie-details)。服务器接口参考：[Emby Items](https://dev.emby.media/reference/RestAPI/ItemsService/getItems.html)、[API Key 认证](https://dev.emby.media/doc/restapi/API-Key-Authentication.html)、[Jellyfin API](https://api.jellyfin.org/)。TMDB 标志来自官方品牌素材，应用在匹配界面与关于区域展示来源声明。

## 优先服务的接入方式

| 服务 | 1.4 接入方式 | 原生授权状态 |
| --- | --- | --- |
| 飞牛 NAS | SMB / WebDAV；也可使用 OpenList 挂载 | 飞牛影视专有协议待接 |
| 群晖 NAS | File Station API、SMB、WebDAV | 已有账号登录；二步验证账号优先使用共享协议 |
| Plex | 服务器 Token、电影和剧集目录 | Plex 账号授权待接 |
| WebDAV | 标准 Basic 认证 | 已接入 |
| Jellyfin | API Key、可选用户 ID | 已接入；Quick Connect 待接 |
| 夸克、百度、UC、OneDrive、Google Drive、MEGA、123、115 | 各自的服务入口 → OpenList / Alist API 或 WebDAV | 网盘登录和续期由网关维护，逐步做原生直连 |
| Navidrome | OpenSubsonic 用户名 / 密码、音乐库 | 已接入协议；认证参数不写进片库 |

网盘使用方式：先在网关添加对应驱动并授权 → 在 SeeWow 选择具体服务 → 填写网关地址、Token 与挂载目录（例如 `/夸克/电影`）→ 测试连接并扫描。网关 Token 为空时仅适用于网关允许匿名读取的目录，目录元数据密码本轮未单独提供输入。编辑入口位于来源卡片「… → 编辑连接与凭据」。

协议依据：[OpenList 文件 API](https://openlistteam.github.io/docs/guide/api/fs.html)、[官方驱动目录](https://github.com/OpenListTeam/OpenList/tree/main/drivers)、[Plex API](https://developer.plex.tv/pms/)、[Synology File Station API](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Package/FileStation/All/enu/Synology_File_Station_API_Guide.pdf)、[Navidrome 协议兼容性](https://www.navidrome.org/docs/developers/subsonic-api/)。上述服务的协议与错误路径经本地模拟服务验证，尚未使用用户的真实 NAS / 云盘账号逐一测试。
