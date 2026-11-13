# SeeWow

**Cinema, made personal.** 一个以私人媒体库为中心的跨平台播放器，使用 Flutter + media_kit / libmpv。

当前工作区为 **1.14.0 体验预览版**。手机端（iPhone / iPad / Android）补齐 Plex 账号登录、本地目录权限与扫描；桌面安装包同步更新。新增地区与多语言资料、本机批量补译、自定义资料服务、AI 封面、字幕检索、更多直播订阅格式，以及手势、音量隐私、AB 循环、精彩帧、小窗与语音译配等放映能力。默认关闭的 [AI 字幕与小映陪看](docs/ai-watch.md) 保持可用；支持三套主题、皮肤工作室和 design.md 生成，详见 [皮肤说明](skins/README.md) 与 [design.md 模板](design.md)。

## 下载 1.14.0 体验预览版

完整更新记录见 [1.14.0 发布说明](docs/releases/1.14.0.md)，安装包与 SHA-256 校验文件见 [GitHub Release](https://github.com/sevenaaaaaaaaa/SeeWow/releases/tag/v1.14.0)。

| 平台 | 安装包 | 安装与签名状态 |
| --- | --- | --- |
| macOS Universal | [下载 ZIP](https://github.com/sevenaaaaaaaaa/SeeWow/releases/download/v1.14.0/SeeWow-macos-1.14.0-preview.zip) | 解压后将应用移到「应用程序」；临时签名、未公证 |
| Android | [下载 APK](https://github.com/sevenaaaaaaaaa/SeeWow/releases/download/v1.14.0/SeeWow-Android-1.14.0-preview.apk) | Android 7.0+；Release 编译、开发签名预览包 |
| iOS / iPadOS ARM64 | [下载 IPA](https://github.com/sevenaaaaaaaaa/SeeWow/releases/download/v1.14.0/SeeWow-iOS-1.14.0-arm64-unsigned.ipa) | iOS 15+；未签名，需使用自己的证书与描述文件重签 |

Windows / Linux 本轮未提供 1.14.0 安装包。AI 功能默认关闭，需要用户自行配置 API；使用前请阅读 [功能与数据说明](docs/ai-watch.md)。

片源能力包括服务选择器、Plex / File Station / Navidrome 适配、OpenList / Alist API 扫描与动态直链，以及本地 / SMB / WebDAV 的多语言 NFO 读取。以下区分已经实现与尚未支持的能力。

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
| 影片信息匹配 | TMDB 多语言、电影发行地区、年份与分页搜索；原始标题、人员、评分票数和图片候选；缺失文字可配置回退；整剧或具体季集（含第 0 季）预览后确认；默认保留已有图片 |
| 地区与多语言资料 | 日本、韩国、香港、台湾、俄罗斯、西班牙、阿拉伯语与藏文优先；多地区目录搜索去重；保留并同时展示真实译名、简介与地区别名，纳入片库搜索；港版与台版独立保存，缺失语言明确留空 |
| 本机批量补译 | 最多 20 个条目生成缺失标题、简介与角色／职务称谓的翻译预览；连接用户自备的本机 Chat Completions 模型，确认后保存；逐字段区分资料源与机译、保留原名和人员姓名，原资料变化后提示译文可能过期 |
| 自定义刮削 API | 最多 20 个用户配置的 GET JSON 适配；按电影、分集、其他视频和自定义分类选择，配置搜索参数、详情路径与字段映射；只读取元数据，预览确认后应用到当前条目 |
| AI 生成封面 | 用户自行配置本机／远程 Images API 图像模型，为缺少封面的条目生成原创配图；编辑描述、主动生成、预览后保存本机，已有封面需明确选择替换；保留模型与时间并显示 AI 配图标记 |
| 任意类型资料编辑 | 电影、剧集、音乐、课程和家庭影像均可编辑标题、人员、分来源评分与封面；可读取已有 NFO，只修改本机资料 |
| 字幕管理与检索 | 独立于 AI 的轨道选择、本地字幕导入和同名本机旁车发现；OpenSubtitles 用户自配 Key、可选账号，多语言与发行版本检索、下载加载、本机缓存与清理 |
| 媒体服务器 | Jellyfin / Emby API Key 接入，支持反向代理子路径、分页入库、电影/剧集、服务器海报与原文件直接播放；用户 ID 可选；分页中断保留旧片库 |
| 片库体检 | 查找疑似同名同年份同集重复、缺少海报/简介的条目；只列出待检查结果，不自动删除或合并；信息补全从详情页主动匹配 |
| 本地/NAS | 本地递归扫描；SMB 在 macOS 用 NetFS、Windows 用 net use、Linux 用 gio 挂载后扫描 |
| WebDAV / 网盘 | PROPFIND 扫描，Basic 认证、HTTP Range 播放；网盘通过用户自己的 WebDAV 网关（如 Alist / OpenList）接入 |
| OpenList / Alist API | 按挂载根目录递归建库；播放前调用网关获取新直链；云盘账号授权由网关维护；网关 Token 不跟随直链发送到云盘域名 |
| Plex | Token 接入，电影及逐集目录、海报和原文件播放；不使用客户端转码 |
| 群晖 File Station | DSM 账号只读列目录、扫描文件，播放前建立新会话；也可使用 SMB / WebDAV |
| Navidrome | OpenSubsonic 账号认证、曲目扫描、独立音乐库与原音频播放；播放认证签名只在运行时生成 |
| NFO 多语言资料 | 本地 / SMB / WebDAV 读取已有 NFO，保留原名、语言、地区、人员、不同尺度的评分与图片引用；本机支持 UTF-8 和带 BOM 的 UTF-16；未确认资料随扫描更新，人工确认资料保留 |
| 编辑连接 | 更新名称、地址、挂载根目录、账号或凭据；保留来源 ID，按稳定条目 ID 合并仍在扫描范围内的进度、收藏和已确认元数据 |
| 直播订阅 | M3U、常见 TXT、纯数据 JSON；多仓与 TVBox `lives` 配置逐层预览；确认后导入频道；XMLTV、分组、收藏、最近观看和订阅刷新 |
| Telegram 本地媒体 | 选择用户已下载到设备的媒体目录，复用本地扫描与播放；该来源不进入 AI 模型目录，不开启 AI 字幕与陪看。原生账号、频道与聊天文件夹直连尚未实现 |
| 链接收集 | 从用户粘贴的地址识别链接，读取最多 3 个页面并收集 M3U / DAV 候选；候选可编辑连接，测试后导入 |
| 来源状态 | 显示扫描进度、上次成功时间、持久化错误；断网/扫描失败保留旧片库；同源并发扫描合并为一次 |
| 播放 | 播放/暂停、音量、快进/快退、全屏、倍速、键盘控制、播放失败提示、断点续播、进度回写 |
| 放映入场 | 光盘旋入／SeeWow 聚光片头／直接放映；约 2.1 秒，可跳过，尊重系统减少动态效果；先准备影片，片头结束再播放，不截掉正片开头 |
| 精彩帧与学习 | 收藏当前原始画面、播放时间点与备注，仅保存本机；图库查看、缩放、移除及从本片回到该时间点；AB 两点循环，B 点需晚于 A 点至少 0.5 秒，直播不启用 |
| 音频电平 | 根据实际 PCM 样本计算 RMS，原片按需独立采样，译音复用返回的 PCM；不读取麦克风或显示随机波形，不支持采样时显示不可用 |
| 离线缓存 | 详情页选择画质（Plex / Emby 支持 1080p / 720p / 480p 转码）与存放位置；下载队列支持限速、暂停 / 续传 / 重试 / 删除，显示实时速度与剩余时间；完成后优先本地播放 |
| 解耦空间 | 首页超长下拉进入第二个独立片库；桌面点顶栏「主空间 / 解耦空间」切换；空间有自己的文件夹、片库、观看记录与 Agent，主空间不受影响 |
| 刷新与发现 | 首页 / 媒体库下拉刷新全部片源（桌面顶栏也有刷新按钮）；首页新增最近加入、纪录片、短剧三条推荐维度 |
| 纪录片与短剧 | 本地按类型与单集时长归类；媒体库新增纪录片 / 短剧筛选，短剧模式显示单集 20 分钟内优先 |
| 播放控制 | 控制栏直接提供 AB 循环与画中画按钮，AB 已设置时高亮 |
| 手机遥控 | 同一 Wi-Fi 下用手机控制电脑播放：搜索或手填地址，6 位配对码，播放/暂停、进度、±10 秒与音量；还能浏览电脑片库并选片在电脑上打开；仅局域网、令牌鉴权 |
| 小窗与后台 | 桌面置顶迷你窗口与完整控制栏全屏；Android 8+ 系统 PiP、用户开启的媒体前台服务；iOS 后台原声音频与 AVKit PiP（受媒体格式和认证方式限制） |
| 语音译配 API | 用户自配专用语音适配服务，目标语言、服务声明保留音色；约 6 秒分段、最多两段缓冲、1× 译音播放；前台点播实验功能，需逐次确认音频发送与费用 |

## Agent：规划 → 工具 → 可操作结果

Agent 工作区提供两种明确标注的模式：

- **本地规则**：无需密钥或模型。识别内置任务与部分偏好表达，调用本地推荐、搜索、体检、来源刷新和链接收集。它不是语言模型，也不理解任意自然语言。
- **AI 模型**：在「影院 Agent → 接入 AI 模型」填写完整的 Chat Completions 兼容接口地址、模型名和可选密钥。远程服务需 HTTPS，本机服务支持 HTTP。模型规划最多 5 个步骤，应用验证后调用受限工具。

工具集合为 `recommend`、`search_library`、`audit_library`、`refresh_sources`、`build_collection`。链接任务在本地单独路由到 `discover_sources`。刷新来源需要用户请求中明确包含扫描/刷新/同步意图；模型返回未知工具或片库外 ID 会使任务失败。片单先生成预览，再由用户保存；Agent 不删除原文件。

每次任务显示步骤、成功/失败/取消、结果和重试入口；最近 30 次任务落盘。可以停止模型或页面请求；来源扫描开始后会完成当前扫描，再跳过后续步骤，已经导入的数据保留。已完成任务的片单被删除后，可再次保存结果。模型连接失败不会伪装成本地模式成功。目录最多提供前 250 个条目，结果仅能引用其中真实存在的 ID。

**数据去向：**使用模型模式执行任务，会把本次需求、类型偏好和影片摘要（名称、类型、年份、时长、观看/反馈状态、ID）发到配置的服务。摘要不包含文件路径、片源地址、HTTP 认证头或凭据。链接任务在本地处理。密钥按服务 origin 隔离保存；macOS 使用钥匙串，其他平台使用权限受限的本机文件。

协议参考：[Chat Completions API](https://developers.openai.com/api/reference/resources/chat)。未绑定特定模型厂商，也不要求 OpenAI 账号。

## 自定义资料 API 与 AI 封面

在「设置 → 自定义刮削 API」新建或编辑适配；详情页「自定义 API 匹配」选择适用服务，搜索、选择结果、预览后确认。密钥单独填写，保存在本机凭据存储，不写入 `library.json`。更改服务地址或认证头后不会沿用旧服务密钥；配置不包含媒体路径或片源凭据。

以下为用户自有资料服务的示例配置，`metadata.example.com` 是占位域名，不是可用影视服务：

```json
{
  "id": "my-course-api",
  "name": "我的课程资料",
  "baseUrl": "https://metadata.example.com/api",
  "kinds": ["other"],
  "category": "课程",
  "searchPath": "search",
  "searchQuery": {
    "q": "{query}",
    "category": "{category}",
    "language": "{language}"
  },
  "resultsPath": "data.items",
  "detailsPath": "items/{id}",
  "detailsRoot": "data",
  "fields": {
    "id": "id",
    "title": "name",
    "overview": "description",
    "year": "year",
    "posterUrl": "images.poster",
    "people": "people",
    "ratings": "ratings",
    "localized": "translations"
  },
  "authHeader": "Authorization",
  "authPrefix": "Bearer ",
  "allowLan": false
}
```

- `kinds` 为 `movie`、`episode`、`other` 的非空列表；`category` 是用户定义的动画、纪录片、课程等分类文字。请求参数可使用 `{query}`、`{kind}`、`{category}`、`{language}`、`{year}`、`{season}`、`{episode}`。搜索词通过 URI 参数编码，不拼入可执行表达式。
- 搜索返回数组的位置由 `resultsPath` 指定；留空可读取顶层数组。每次最多显示前 80 项。没有详情接口时将 `detailsPath` 留空，直接预览搜索结果；配置详情时需映射稳定 ID，详情必须返回相同 ID。详情 ID 支持字母、数字、下划线、短横线，不接受路径片段。
- `fields` 使用点分隔的 JSON 路径（含数组索引），只映射资料字段。除示例外可映射 `adult`（布尔值）、`originalTitle`、`originalLanguage`、`language`、`countries`、`genres`、`backdropUrl`、`alternativeTitles`。类型与地区为文字数组；人员格式为 `[{"name":"姓名","role":"角色","department":"部门"}]`，评分为 `[{"source":"来源","value":4.5,"scale":5,"votes":10}]`，地区译文为 `{"zh-HK":{"title":"港版名称","overview":"简介"}}`。复杂数据转换、POST／GraphQL、网页 HTML 或脚本接口需用户自己的适配服务；应用不执行远程插件代码。
- 资料接口单次响应最多 4 MiB，整次请求 30 秒，拒绝重定向，不向图片站点发送刮削 API 密钥。公网服务需 HTTPS；回环地址允许 HTTP，信任的 NAS／局域网需明确配置 `allowLan: true`。服务返回的播放链接、爬虫和解析规则不会成为播放功能或可执行内容。保存只确认当前条目，不批量改名整部剧。

在「设置 → AI 封面服务」填写完整 `/images/generations` 地址、图像模型与可选密钥；在详情页「AI 生成封面」编辑并确认发送的描述。接口采用 [Images API](https://developers.openai.com/api/reference/resources/images/methods/generate?site_locale=en) 的非流式请求，接收 `data[0].b64_json`；模型默认输出 Base64 时不发送 `response_format`，其他兼容服务可开启该选项。只返回 URL 的服务需要对应的 Base64 适配，不会自动下载返回的任意 URL。

生成描述默认从标题、类型和最多 1200 字简介构建，用户可以完全重写；只发送编辑后的描述，不上传视频、截图、路径、人员列表或片源凭据。用户主动点击才调用，可能产生第三方费用；停止连接不保证撤销服务端生成或计费。单次最长 180 秒、JSON 响应最多 28 MiB、图片最多 20 MiB，仅接受可解码的 PNG／JPEG／WebP，限制边长 8192 和总像素 2000 万。SVG、损坏图片和任意链接不保存。

封面先驻留预览，确认后写入 SeeWow 的 `covers/`，保留模型、生成时间和 AI 配图标记，不写回媒体目录或冒充官方海报。已有封面需明确勾选替换；确认时若资料或封面已被改动，拒绝覆盖。取消不保存；Telegram 等禁止 AI 的来源同时在生成和保存阶段检查。应用不附带图像模型或预置密钥，真实服务的生成质量与兼容性尚需用户实际连接验证。

自定义资料与生成服务均需用户确认拥有适用的访问、内容及商用授权。软件的数据适配、用户自填密钥、AI 标记或捐赠 Pro 本身不替代这些授权，也不能自动判断每个用户 API 的授权状态。

## 放映、精彩帧与语音译配

「设置 → 放映与播放」选择光盘旋入、SeeWow 聚光片头或直接放映，设置进入全屏、后台播放和音频电平。片头为原创 SeeWow 动效，不包含第三方电影公司的标志、片头素材或配乐。直播和音频直接播放；系统减少动态效果时跳过动画。桌面使用同一个原生窗口进入全屏，保留字幕、学习和播放工具，不另开一个丢失控制栏的视频路由。

播放器右上角「播放工具」提供当前画面收藏、本片图库、AB 循环、小窗和译配。`S` 收藏当前帧，`B` 依次标记 A／B 点；循环已开启时再按 B 重新标记 A。可在菜单清除循环；手动跳播、选择图库时间点或开启译配时清除循环。收藏会暂停并预览当前原始画面，确认后保存，取消不落盘；不包含 Flutter 绘制的控制栏和字幕叠层，可用备注记录台词。截图最多 8 MiB、边长 8192、总像素 2000 万；原生截图仍可能先分配原分辨率缓冲。图库也可从「设置 → 精彩帧收藏」打开；移除只处理 SeeWow 的截图，不删除影片。

画面手势支持横向滑动、左侧长按快退、右侧长按快进；长按逐步加速，显示时间预览，松手才提交一次跳播。直播不接受跳播。两个或更多手指在画面上保持约 650 ms 可锁定／解锁触控，单指操作和返回键在锁定时不改变播放。移动或取消多指手势不触发锁定，抬起后的余留手指不会误触跳播或解除静音。锁定期间临时启用后台原声播放；解锁后恢复原来的后台偏好。长按锁按钮也可解锁；桌面 `L` 切换锁定，`Esc` 可解锁。这是播放器内的触控锁，系统 Home／锁屏和媒体通知仍由系统管理。

每个新文件（含直播、音频）默认静音，快速双击画面解除静音；控制栏静音按钮和 `M` 也可操作。默认恢复的播放器音量为外放最多 30%、已确认耳机最多 50%，同一天同类输出上次主动选得更低则取较低值。手动调高音量只改变当前播放，下一文件／再次解除静音仍按上述默认上限。静音本身不把记忆值改为零。只保留本地日历当天的两个音量值，不保存收听历史；跨日读取时忽略并覆盖旧记录。这里控制播放器增益，不修改全局系统音量，也不代表物理响度上限。

切换输出设备后先静音，等待用户重新双击。Android 13+ 查询系统为媒体选择的输出，iOS 查询音频会话当前输出，macOS 使用 CoreAudio 当前默认设备、内建输出端口和明确的耳机终端类型。传统蓝牙 A2DP 可能是耳机也可能是音箱；投屏、共享输出、旧 Android 以及当前尚未接入原生路由识别的 Windows／Linux，不能确认时均按外放保护，不根据设备名称猜测耳机。路由事件处理存在系统与应用调度延迟，不能承诺设备切换时绝对零瞬间漏声，移动端拔插、蓝牙切换及后台行为仍需真机验证。

敏感内容保护识别明确的 `adult: true`、NSFW／色情等显式类型标签，TMDB、NFO 的 `<adult>` 与自定义资料映射可保留此标记；不会凭标题中的单词或普通 18+ 年龄分级推断色情。播放工具允许将当前播放标记为敏感内容。一旦阳性，保护持续至本次播放结束，后续阴性结果不会自动解除；外放或未知输出保持静音，双击、音量滑块、译声音轨和 iOS 系统小窗均遵守同一策略，已确认耳机可继续播放。

可选视觉检测位于「设置 → 放映与播放 → 用户自备的本机敏感画面检测」。本轮不捆绑模型，用户需运行自己的本机分类服务并主动开启此选项；未配置时仅检查内容标记，界面明确显示状态。仅允许字面量 HTTP 回环地址 `127.0.0.1`／`[::1]`，拒绝域名、局域网、公网和重定向。开启后前台每约 3 秒提交一张压缩至最长 640 像素、最多 512 KiB 的当前画面，不发送片名、路径、来源 URL 或认证信息。协议为：

```http
POST http://127.0.0.1:端口/classify
Content-Type: application/json

{"image_base64":"当前画面的 PNG Base64"}
```

```json
{"nsfw": true, "confidence": 0.95}
```

只有 `nsfw: true` 且 `confidence >= 0.8` 触发阳性；响应最多 8 KiB，整次请求最多 8 秒，一次只运行一个检测。失败显示不可用并停止本轮抽帧，在播放设置保存后可重试。后台、系统小窗、音频和禁止 AI 的来源不提交画面。抽帧、资料标记与用户模型都可能漏检；未检测、检测失败与阴性不构成内容安全认证。检测服务本身的数据处理由用户管理，本机地址限制不代表能约束用户服务的后续行为。

原片电平通过独立的音频解码器按需采样最多 4 秒 PCM，按当前时间计算 RMS；译配时直接读取已有译音样本。可见控制栏每约 100 ms 更新，不修改主播放器滤镜或音频输出，隐藏控件及进入后台会取消待采样任务。NAS／HTTP 来源可能产生额外的来源读取；采样失败、直播或不可定位音频显示电平不可用，不用音量滑块数值伪造声音起伏。此电平反映音频样本与播放器增益，不是设备扬声器的物理响度测量。

小窗／后台支持范围：

| 平台 | 当前实现与条件 |
| --- | --- |
| macOS／Windows／Linux | 置顶迷你窗口，保留播放／暂停、恢复与关闭；退出播放恢复原窗口位置、大小、全屏与置顶状态。macOS 已进行全屏播放与返回交互验证；Windows／Linux 本轮未构建验证 |
| Android | Android 8+ 且系统允许时使用原活动 PiP，保留原播放器；后台播放默认关闭，开启后使用媒体类型前台服务、MediaSession 与通知播放／暂停／停止控制。退出播放器或进程结束时停止服务；不承诺被系统终止后继续播放 |
| iOS／iPadOS | 开启后使用 playback 音频会话与后台 audio 模式，后台关闭视频轨道、前台恢复。系统 PiP 使用 AVKit 暂时接管播放，停止 PiP 时回传时间点；只支持 AVFoundation 可播放的本机文件或无需自定义认证头的 HTTP(S) 媒体，不承诺 MKV／任意 NAS 认证格式。失败会恢复应用内播放器，不绕过认证 |

移动端后台和 PiP 已接入并完成原生构建，尚需真机验证；操作系统权限、格式、音频路由和系统资源回收会影响实际行为。关闭播放器会结束播放，应用导航内持久悬浮播放器不包含在本轮。

「设置 → 语音译配 API · 实验性」配置完整接口、模型、目标语言代码及可选密钥；播放工具中选择开启，并确认向指定服务发送音频及音色使用权限。普通 Chat Completions／单一 TTS API 不能直接充当此服务，需能处理输入音频并返回对齐译音的模型或用户自己的适配层。保留原声、只翻译字幕的模式仍在独立的 AI 字幕设置中，不经过语音译配 API。

语音适配协议（POST JSON）：

```json
{
  "model": "用户的语音翻译模型",
  "target_language": "ja-JP",
  "preserve_voice": true,
  "source_at_ms": 42000,
  "source_duration_ms": 6000,
  "source_audio": {"format": "wav", "base64": "当前片段的音频 Base64"}
}
```

响应为 `{"target_language":"ja-JP","voice_preserved":true,"audio_base64":"对齐译音的 WAV Base64","text":"可选译文"}`。WAV 为 8–48 kHz、16 位、单／双声道 PCM，最多 2 MiB、8.5 秒；输出时长与原段差异不得超过约 15% 加 50 ms，再以保留音高的速率校准至源段时长。每次 JSON 响应最多 4 MiB、45 秒，公网须 HTTPS，局域网需明确允许。密钥与接口地址绑定，不写入片库；返回链接、其他目标语言、缺失音色声明或过大时长差异会被拒绝。

每次发送当前最多约 6 秒音频、时间点和所选语言，不发送影片文件、播放 URL、文件路径或片源认证头。持续开启并观看完整影片时，服务会依次收到所播放范围的全部音频。一次只有一个语音 API 请求，预取最多下一段，音频暂存在私有临时目录并在停止后清理。停止连接不能撤回已送达的音频或保证取消服务端计费。用户暂停会暂停原片和译音；跳播、切片、倍速更改、后台、进入小窗或打开陪看会停止译配并恢复原声，AI 限制来源和直播不可开启。后台继续播放仅使用原片声音，不继续发送语音请求。

这是有缓冲与等待的分段译配，准备不及时会暂停影片，不承诺无延迟同声传译。多说话人音色、翻译质量、跨段连续性与背景音乐保留取决于服务；`voice_preserved` 是服务声明，客户端无法验证声音身份或保证音色完全不变。原文件不被覆盖，也不默认上传第三方声音用于训练。实际服务的数据处理与使用条款需用户确认。本轮以合成音频和本机模拟语音 API 验证通路，没有使用真实商业语音模型验证译文或音色质量。

## 诚实的边界

- **用户自带媒体。**SeeWow 面向 NAS、家庭媒体库和个人学习场景。不内置、推荐或维护第三方影视源，不提供针对视频网站的地址提取或访问控制绕过服务；用户应确认内容与服务的使用授权。
- **列表兼容有明确范围。**直播入口支持 M3U、`名称,HTTP(S)地址` TXT（`分组,#genre#`）、JSON 的 `channels`、内嵌 `lives[].channels` 与 `lives[].url`。`urls:[{name,url}]` 多仓先展示目录，用户逐项选择，最多深入 5 层；只保存最终确认的频道列表订阅，不批量拉取其他配置。JSON 不等于完整 TVBox 点播兼容：`sites`、`spider`、`parses`、脚本、代理和 DNS 规则不执行；播放器扩展请求头目前忽略并提示。加密/伪装配置、单视频 HLS 清单、非 HTTP(S) 频道和任意网页不作为频道列表导入。
- **读取限制。**列表与 XMLTV 每次读取上限 8 MiB，HTTP 解压后的响应同样受限，整次网络读取限时 25 秒，最多跟随 4 次重定向；禁止远程配置转向本地文件或 HTTPS 降级。默认阻止订阅/节目单读取访问非公网地址，需要用户为该订阅读取明确开启局域网访问。此开关不构成播放器或操作系统的网络沙箱；频道播放仍由用户主动发起。刷新失败或无频道时保留旧列表，频道重排保留收藏与最近观看。订阅地址和流地址可能含访问令牌，仍属于私人本机数据。
- **Telegram 仅接本机目录。**「片源与订阅 → Telegram 本地媒体」或服务选择器中选择已下载文件夹；仅扫描可访问的视频文件，不登录账号、不读取频道和消息、不自动下载 Telegram 文件。此入口标记的媒体及其标题不发送给 AI 模型，AI 字幕/陪看不启用。原生 TDLib 接入仍需单独验证授权、播放和平台条款。

- **没有全网影片/订阅源搜索。**链接收集读取用户提供的网页；外部搜索引擎、资源质量验证和自动订阅策略尚未接入。
- **网盘首轮使用网关。**夸克、百度、UC、OneDrive、Google Drive、MEGA、123、115 提供明确的服务入口，通过 OpenList / Alist API 或 WebDAV 接入；需要先在网关配置对应驱动并完成授权。尚未提供这些网盘的原生 OAuth，也不能把分享链接直接当媒体库。
- **媒体服务器只读接入。**Jellyfin / Emby 使用 API Key，Plex 使用 Token；读取目录、已有元数据和原文件流，不回写服务端观看状态，不支持 Quick Connect / Plex 账号授权、转码协商或 DLNA。飞牛通过共享协议接入，飞牛影视专有接口仍待实现。
- **群晖会话限制。**File Station 账号需具有读取权限；需要二步验证的账号可先走 SMB / WebDAV。扫描结束注销扫描会话，播放时重新登录的会话由 DSM 超时回收。
- **音乐支持范围。**Navidrome 当前提供曲目目录、播放和本机进度；不包含歌词、专辑封面授权加载、服务端播放记录回写、转码、离线下载或完整音乐管理。
- **刮削覆盖。**电影、剧集，以及被 TMDB 收录的动画、纪录片、综艺、演唱会等可在线匹配；课程、家庭影像、音乐与未收录内容通过本地编辑、NFO 或服务器资料补全。不能保证所有语言、地区与版本都有完整资料。尚未直接接入豆瓣、IMDb、烂番茄、时光网的在线刮削；已有 NFO 可携带这些来源的评分，保留来源、尺度和票数，不混合计算。Jellyfin / Emby / Plex 读取服务器已有人员与评分。OpenList API / File Station 本轮仍只扫描媒体文件。
- **TMDB 配置与授权。**在「影院偏好 → 影片信息补全」配置 Token、资料语言（如 zh-CN、zh-TW、ja-JP、en-US）、电影发行地区、文字回退语言和优先采集的地区语言。匹配界面可按这些语言搜索同一目录并去重；详情预览读取资料源实际提供的翻译与地区别名，不把回退文字冒充其他地区译文。详情页「多语言资料与本机补译」及媒体库批量入口可主动采集已确认 TMDB ID 的现有文字译文；支持具体集的译文。人员姓名沿用资料源，不自动翻译。请求发送查询、语言、地区、年份及所选 ID；没有后台自动批量刮削或自动猜测。确认保存保留文件、进度与片单。
- **本机翻译的配置与范围。**在上述多语言入口展开本机模型设置，填写已安装的离线模型名与本机 Chat Completions 地址，例如 `http://127.0.0.1:11434/v1/chat/completions`；保存设置后生成预览，勾选条目再保存。应用不附带模型、不下载权重、不启动模型服务，也不回退到云端。连接仅允许回环地址，仍需用户确认本地服务使用离线模型且不会转发请求；显式 cloud 模型名会被拒绝。仅发送需要补译的标题、简介和角色／职务文字，不发送文件路径、播放链接、账号、人员姓名或评分。Telegram 等限制 AI 的来源跳过补译。此入口不翻译封面、分数或整份字幕；字幕翻译由独立的播放功能提供，使用其自己的模型配置。
- **语言覆盖与翻译质量。**默认地区标签为 `ja-JP`、`ko-KR`、`zh-HK`、`zh-TW`、`ru-RU`、`es-ES`、`ar-SA`、`bo-CN`；阿拉伯语文本从右向左排版，藏文与阿拉伯文字体随应用打包。缺失的当地译名与简介可本机补译，逐字段标注机译并保留原资料；不生成官方译名、评分、人物或播放源。藏文／阿拉伯语输出有文字脚本检查，但这不能验证翻译准确性，仍须人工审阅；未实测真实模型的藏文质量。地区搜索仍限 TMDB 已收录作品，尚未接入当地门户或新增片源目录。
- **第三方服务的商业授权。**商用项目需按 TMDB 与字幕等服务的条款取得适用授权，自填 Token 或用户捐赠开启 Pro 不代替相关授权。
- 推荐仍受片库元数据质量影响。本地模式仅支持部分心情/类型表达；模型模式的挑选质量依赖用户配置的模型，目前没有嵌入索引、长期语义记忆或外部影片目录。
- 片单是保存时的条目快照，不是自动更新的订阅。重复检测是启发式检测，不是内容哈希校验或无损版本合并。
- **字幕覆盖。**播放器字幕菜单提供内嵌轨道、本地 SRT / VTT / ASS / SSA / SUB / IDX / SUP / SMI / SAMI / TTML / DFXP / SBV 文件入口；实际渲染、旧编码及成对图形字幕依赖 libmpv 与文件完整性。同目录发现限同名本机或已挂载目录，以及其 Subs / subtitles 子目录，尚未枚举 WebDAV / 网关远程旁车。OpenSubtitles 可留空语言搜索全部，以标题或 IMDb ID、季集检索，显示发行版本、听障和机器翻译标记；确认后下载，不保证时间轴与视频版本一致。在线文字字幕缓存于应用目录，可从设置清理，不写回 NAS。图形字幕不自动 OCR，未新增 ASR。
- 移动端 SMB、云同步、原生网盘直连、完整音轨选择、HDR / Dolby Vision 原生旁路、直播回看与时移仍待实现。系统 PiP 的平台与格式限制见上方说明。
- Windows / Linux 的挂载逻辑与移动端包未在本轮真机验证；本轮 macOS 进行人工交互，iOS／Android 完成原生构建，真机后台与 PiP 行为仍需验证。

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

现有代码仍有历史 info 级 lint；验证要求无 analyzer error / warning。测试覆盖文件名、M3U/XMLTV、WebDAV/SMB 解析，以及偏好/片单持久化、扫描失败恢复、并发扫描、模型规划校验、错误恢复、链接收集、搜索交互和响应式布局。兼容模型、TMDB 和媒体服务器协议通过本机模拟 HTTP 服务验证；元数据确认流程、窄屏服务选择器、服务器 / 网关表单有组件测试。1.6.0 发布基线共 94 项测试，1.14.0 基线为 231 项通过、2 项原生解码器测试按需跳过；1.6.0 新增换肤、皮肤导入、design.md 生成、草稿取消与恢复、AI 生成协议测试；其余测试覆盖目录递归、分页中断、动态直链、跨域跳转的 Token 隔离、群晖会话、Navidrome 盐值签名、NFO 与来源编辑。后续列表兼容测试覆盖多仓预览、确认后导入、格式错误、重定向/大小/超时/局域网限制、刷新与收藏迁移、节目单隔离，以及 Telegram 本地扫描、AI 数据隔离与窄屏交互。没有使用用户的真实模型、TMDB 或 NAS 凭据进行外部调用，真实服务器兼容性还需实际连接验证。

区域资料测试覆盖港／台版本独立保存、多语言与 Unicode 搜索、TMDB 部分地区失败和身份校验、本机请求字段与脚本校验、AI 来源限制、取消、并发编辑保护、重扫保留与过期提示，以及 375 / 768 / 1440px 的批量预览与确认。真实 TMDB 目录完整度和本地模型翻译质量尚未通过外部服务实测。

`SEEWOW_SHOTS=1 flutter test test/experience_test.dart` 可生成 `/tmp/seewow-experience-shots/` 布局截图；`SEEWOW_SHOTS=1 flutter test test/regional_metadata_flow_test.dart` 生成 `/tmp/seewow-regional-languages.png`，加载内置藏文与阿拉伯文字体。测试在 macOS 可加载系统字体；其他系统使用默认测试字体。普通 CI 不需要 `DemoMedia/`。

启动可使用 `SEEWOW_LAUNCH=home|library|collections|sources|agent|live|music|settings|detail|play`。兼容旧 `movies`、`tv`、`playweb`、`liveplay` 参数。

## 数据与代码

数据位置：平台 application-support 目录下的 `SeeWow/`，macOS 通常为 `~/Library/Application Support/com.seewow.seewow/SeeWow/`。

- `library.json`：来源、媒体、已确认的元数据匹配、偏好、待看、片单、播放记录、来源错误；写入串行化，临时文件完成后重命名。
- `agent.json`：模型接口配置与最近任务；不保存 API Key。
- 认证头（Authorization / Cookie / X-Emby-Token 等）不再写入新的片库快照；启动时从来源凭据恢复。媒体服务器凭据不会发送给 TMDB 图片站点或模型服务。
- `skin.json`：已有界面偏好。新安装默认石墨、无衬线、纯平；已有偏好保留。
- `subtitles/`：主动下载的字幕缓存，按来源和条目隔离，语言保留地区变体，可在设置清理。字幕密码仅用于登录请求，会话和 API Key 使用独立凭据存储，不写入片库。
- `covers/`：用户确认保存的 AI 配图；片库仅记录本机路径、模型与生成时间，取消预览不产生封面文件。刮削 API 配置与图像服务密钥使用独立的本机凭据条目，密钥不写入媒体元数据。
- `frames/`：精彩帧截图及 `index.json`，保存本机条目 ID、片名、时间点、备注和收藏时间，不保存播放地址或认证头。语音采样／译音使用系统临时目录，正常停止和退出时清理，不写入片库；进程异常终止时操作系统可能暂留临时文件。
- `iptv.json`：直播频道、订阅与节目单。订阅链接可能包含用户提供的访问令牌，应视为私人本机数据。

```text
apps/seewow/lib/
  app/          应用壳、启动、主题、命令搜索
  agent/        受限规划执行器、任务记录、链接收集
  domain/       媒体模型、偏好、推荐、查询、体检、IPTV/XMLTV
  data/         片库持久化、本地扫描、直播状态
  sources/      本地/SMB/WebDAV/Plex/Jellyfin/Emby/OpenList/FileStation/Navidrome 适配与播放解析
  metadata/     TMDB 多地区搜索与译文、NFO、本机缺失资料翻译、字幕检索缓存
  features/     首页、媒体库、片单、来源、Agent、详情、直播、设置
  playback/     media_kit 播放器
  design/       共享令牌与界面组件
```

当前设计规则见 [设计系统](docs/seewow/design-system/seewow/MASTER.md)。`docs/screens/`、`docs/design-lab/` 与旧 HTML preview 保留 1.1 版历史参考，不代表当前主界面。根目录 `Sources/` 为保留的 SwiftUI 原型，主实现位于 `apps/seewow/`。

区域字体使用 Google Fonts 的 [Noto Serif Tibetan](https://github.com/google/fonts/tree/main/ofl/notoseriftibetan) 和 [Noto Sans Arabic](https://github.com/google/fonts/tree/main/ofl/notosansarabic)，随包保留 SIL Open Font License，应用许可页展示声明。多语言接口参考：[电影译文](https://developer.themoviedb.org/reference/movie-translations)、[剧集译文](https://developer.themoviedb.org/reference/tv-series-translations)、[分集译文](https://developer.themoviedb.org/reference/tv-episode-translations)、[Ollama 本机兼容接口](https://docs.ollama.com/api/openai-compatibility)。

元数据接口参考：[TMDB 搜索](https://developer.themoviedb.org/reference/search-movie)、[详情](https://developer.themoviedb.org/reference/movie-details)。服务器接口参考：[Emby Items](https://dev.emby.media/reference/RestAPI/ItemsService/getItems.html)、[API Key 认证](https://dev.emby.media/doc/restapi/API-Key-Authentication.html)、[Jellyfin API](https://api.jellyfin.org/)。TMDB 标志来自官方品牌素材，应用在匹配界面与关于区域展示来源声明。

补充协议与许可：[TMDB 语言](https://developer.themoviedb.org/docs/languages)、[TMDB 商用与署名](https://developer.themoviedb.org/docs/faq)、[OpenSubtitles API](https://opensubtitles.tawk.help/article/about-the-api)、[专业方案](https://opensubtitles.tawk.help/article/pro-packages)、[Kodi NFO](https://kodi.wiki/view/NFO_files/Movies)。

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
