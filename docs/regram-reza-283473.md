# Reza 13.2.0 (283473)

本版跟进 iOS `6600bde38a`（改名 Reza、四款猫图标、会话 ReSieve 记录）与 `34161c93b1`（功能审计）中适用于 macOS 的部分，并修复翻译、聊天列表闪烁与富文本覆盖问题。

## 名称与图标

- 用户可见名称改为 Reza：`CFBundleName`、`CFBundleDisplayName`（主程序与分享扩展）、关于页、设置入口「Reza Pro」、三语语言包。
- 以下保持不变，避免影响自动更新和本机数据：bundle id `app.regram.macos`、`PRODUCT_NAME`／可执行文件 `Regram`、安装位置 `/Applications/Regram.app`、GitHub Release 资产名 `Regram-<版本>-<构建>-<架构>.dmg`、钥匙串作用域、App Group、`regram://` 链接。新增 `reza://` 作为别名。
- 新增 `RGCatOrange`（橘猫，默认）、`RGCatCalico`、`RGCatSiamese`、`RGCatTuxedo`，取自 iOS `Reza/RGBranding/AppIcons.xcassets` 的 1024px 原图。应用包图标 `Regram.icon` 改为橘猫。已主动选择过旧图标的用户继续沿用；从未选择的用户显示橘猫。
- 设置入口图标跟随所选应用图标。

## ReSieve 会话过滤记录

- `RGAdSampleStore.load(reviewedOnly:peerId:)` 按账号盐值计算的 `sourceGroup` 只返回当前会话的待处理与已审阅记录。
- 频道和群组资料页在 ReSieve 开关下方新增「ReSieve 过滤记录」（路由 `reSieveRecords/<peerId>`）。该入口不受会话或全局开关影响，暂停过滤后仍可查看、纠正或删除已有记录。

## 翻译

- 慢的原因：一批消息、每条消息的各段文本（按链接与格式实体切分）都是串行请求；iOS 用 `combineLatest` 并行。现改为有界并行 `regramTranslateConcurrently`（默认 6，LLM 3，系统翻译 1），并在 HTTP 层加 10 个并发请求的全局限流，单请求超时 20 秒。
- 首次失败：默认 Telegram 翻译对非 Premium 账号或配额用尽时直接报错。现与 iOS 一致，Telegram 翻译失败后回退 Google（仍经过受保护内容的网络许可检查）；快速翻译与翻译窗口同样回退。
- 移除已失效的 Google CN 与 Microsoft 后端；读取、写入、备份导入时把 `gtranslate`／`googleCN`／`microsoft` 迁移为 `google`。

## 富文本

- 快速翻译按钮支持富文本消息：默认后端先用 `translateRichMessage`，失败或为空时按块用所选服务翻译 InstantPage，结果以 `TranslationMessageAttribute.instantPage` 保存并渲染。
- 翻译窗口中的富文本消息在选择第三方服务时改用该服务，默认后端失败时回退 Google。
- ReSieve 不再排除富文本：页面按顶层块展平为文本（保留链接、提及、自定义表情、代码与引用实体）交给分类器；整条判定为广告时隐藏，被移除范围完整覆盖的顶层块从富文本中删除。

## 聊天列表闪烁

- 新消息或重新分类期间，行预览保留上一条已确认的可见预览，而不是先显示原文、再清空、再显示回退消息。规则或模型状态变化时不再整体清空回退预览。
- 放开 macOS 上不必要的节流：调度器前台一律以交互优先级运行，取消工作后的恢复等待（仅过热时保留），规则匹配预算 0.05 秒放宽到 0.25 秒，未完成重试从 60 秒改为 2 秒起指数退避，刷新合并间隔缩短到约 16 毫秒，回退扫描批量从 16 增至 64。

## 其他排查与修复

- 幽灵模式「不发送在线状态」：在线状态管理器只接受 `object` 为账号 ID 的通知，而设置变更发送的是偏好对象本身，切换后不会立即生效。现按变更键判断并立即重新上报。
- 防自毁：云端会话中的阅后即焚媒体（autoclear）同时受「防自毁」和「防自动删除」保护，与 iOS 一致。
- 链接预览修复：Instagram 默认改为 `instagramfix.com` 并迁移旧值 `ddinstagram.com`；内置规则新增 `instagram.com`、`www.tiktok.com`、`reddit.com`；远程规则只覆盖其列出的域名，未列出的保留内置规则，仍指向失效主机的远程规则被丢弃。
- 设置项排查：Regram 设置页上的 73 个开关和选项均有实际读取方，未发现只显示不生效的项。

核心子模块改动（`ManagedAccountPresence.swift`、`ManagedAutoremoveMessageOperations.swift`）已同步到 `patches/regram-telegram-core.patch`，并用临时索引从固定版本重放核对。
