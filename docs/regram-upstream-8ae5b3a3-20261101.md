# 2026-11-01 上游富文本预览、提示气泡与群管理更新

以 `1fb64f5b` 为基线，合入 `f6d77621..8ae5b3a3` 三项上游更新。保留前轮富文本选词、旧测试修正和音乐加载修复。

| 提交 | 更新 |
| --- | --- |
| `f72be930` | 富文本预览提取支持表格内容、无标题折叠块、封面、嵌入文章、媒体标题及按钮，保持自定义 emoji 的 UTF-16 范围；预览提取与原有富文本投影分开。 |
| `de781bbf` | 提示气泡圆角随高度变化，窄气泡限制圆角以容纳箭头，尺寸变化时同步更新圆角动画。 |
| `8ae5b3a3` | 群最近操作日志增加限制／封禁菜单，先核对最新成员及管理权限；头像菜单按操作相关上下文绑定，复用行或移除头像后旧操作失效。 |

## 合并处理

唯一文本冲突位于 `ChatMessageMenuItems.swift`。合并后的信号链使用上游的主线程 `combineLatest`，继续执行 Regram 的异步 `regramFilterImportData`，并在最终创建菜单前回到主线程。过滤规则导入数据仍随同消息及多选数据进入菜单构建。

头像的 Regram 隐藏 Stories 偏好保留；上游新增的菜单绑定和失效检查完整接入。消息菜单现有的原图复制、受保护内容设置、过滤规则导入和其他 Regram 扩展继续保留。

## 回归与构建

全部使用 Release/STABLE。新增回归编译实际模块和原样的上游测试，使用真实 TelegramCore、Postbox、TGUIKit、SwiftSignalKit 类型；账号网络返回由测试中的受控信号提供。

| 检查 | 结果 | 证据目录内日志 |
| --- | --- | --- |
| 头像菜单上下文绑定 | 9 项通过 | `chat-ui.log` |
| 聊天富文本选词、Article 草稿、Regram 提及和过滤已读 | 7 项通过 | `chat-ui.log` |
| 群管理菜单权限、超时、取消、过期结果和调用时检查 | 11 项通过 | `participant-moderation.log` |
| 完整 MessageTextUtils 套件，包含 7 项富文本预览用例 | 18 项通过 | `message-text-utils-final.log` |
| 原生提示气泡窄栏／窗口边缘／按钮布局及圆角动画 | 3 项通过 | `tooltip-final.log` |
| Regram 过滤规则导入 | 8 项通过 | `filter-import.log` |
| Regram 过滤聊天列表 | 176 项检查通过 | `filtered-chat-parity.log` |
| 合并后的 arm64 Release/STABLE 完整构建 | 通过；构建输入 14 个生产文件摘要一致 | `release-build.log`、`merge-build-verification.json` |

合并验证构建的构建号仍为 283392，后续双架构发布使用独立的版本递增和构建记录。

原生回归运行器增加 PeerModerationUI、MessageTextUtils、TGUIKit 的选择及独立缓存路径。前两者补充已有 RNNoise 对象的链接，避免原生 Telegram 调用依赖缺少 `_rnnoise_*` 符号。提示气泡测试复用仓库已有的 TGUIKit 资源初始化，检查实际窗口内提示视图、箭头边界和 Core Animation 参数，不改动生产视图的可见性。

没有向真实聊天发送消息或调用真实成员限制／封禁接口。此次合并及回归阶段未替换本机安装包。

## 保留检查

原有父仓库 31 个本地文件和核心子模块 77 个本地文件，共 108 个文件，摘要均一致。核心仍固定为 `fb0e62ba8a147f0821da6aa63c09da7d79a10111`，没有暂存既有子模块改动。

在临时 Git 索引中从固定版本重放 `patches/regram-telegram-core.patch`，77 个文件全部与实际构建工作区逐字节相同，确认发布源码可复现当前核心实现。

合并与回归证据目录为 `/tmp/regram-upstream-8ae5b3a3-20261101`；发布核验目录为 `/Users/yuki/Downloads/Regram/v13.1.0-283393/verification`。
