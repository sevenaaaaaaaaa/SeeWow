这个目录放「随包内置的播放源」清单（`builtin_sources.json`）。

- 本地预览包、iOS IPA、iCloud 分发的包：带这个文件，首次启动铺满内置站点。
- 上 GitHub 的公开包：**不带**。构建脚本 `tool/build_macos_public.sh` 会把 JSON 暂时挪走，
  再用 `--dart-define=SEEWOW_NO_BUILTIN_SOURCES=true` 构建，产物里连代码种子也不生效，
  用户要么自己填采集站接口，要么粘一条 TVBox 配置导入。

这个说明文件留在两种包里都不是问题：它只是一个占位，保证目录非空（Flutter 对
已声明但为空的资源目录会报错），里面不含任何站点地址。
