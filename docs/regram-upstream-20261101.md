# 2026-11-01 上游合并与回归

本记录中的音乐加载既有失败随后已修复，后续验证见 [音乐加载修复记录](regram-music-loading-20261101.md)。下文保留本次上游合并当时的检查结果。

本轮合入指定的 `de608bb0..b18dcd80` 五项 Telegram macOS 上游提交，没有额外合入其他功能分支或升级子模块。

| 提交 | 内容 |
| --- | --- |
| `8b707261` | 再次点击个人资料音乐条时复用当前账号、当前资料的播放器，打开歌曲列表并定位当前歌曲。 |
| `7b3a0836` | 搜索结果和最近联系人菜单增加已读／未读操作，保留秘密聊天、话题群和收藏夹子聊天的限制。 |
| `ac870abe` | 活跃设备详情展示客户端版本、系统、官方客户端标识、首次登录与最后活跃时间，并提供位置预览。 |
| `7cc8cc30` | 最近普通／动态 emoji 支持逐个移除，正确处理肤色、原始条目身份和空分组。 |
| `b18dcd80` | 调整聊天列表小程序按钮的垂直位置及文字避让宽度。 |

## Regram 保留检查

自动合并没有文本冲突。应用源码及上游测试共涉及 34 个文件；只额外清理了一行上游新增的行尾空白，并增加本记录。

Regram 的 emoji 排序及设置订阅、搜索消息过滤与备注、资料页钱包入口、聊天列表布局与过滤实现保留。emoji 排序方法和资料页钱包入口与合并前的源码逐字一致；合并产生的源码和测试文件范围与上游一致。

合并前保存了父仓库及 `telegram-ios` 的补丁、状态和文件指纹。原有 31 个父仓库本地文件与 76 个核心子模块本地文件，共 107 个文件，均未被合并或测试修改。没有暂存这些既有本地改动。

证据目录：`/tmp/regram-upstream-b18dcd80-20261101`。保留检查见 `baseline.json` 和 `merge-preservation.json`。

## 回归结果

本轮使用 Release/STABLE。对于默认没有指定 Release 的既有测试运行器，证据目录内的 `release-runner.py` 在调用时为 `swift test` 增加 `--configuration release -Xswiftc -DSTABLE`，为直接 `swiftc` 调用增加 `-O -D STABLE`，没有修改仓库中的运行器。实际命令保存在对应日志中。

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| 最近 emoji 移除 | 当前代码 34 项通过；另以 `592446a5` 模型临时组合的 34 项通过，没有把该提交合入应用 | `remove-recent-emoji.log` |
| 搜索已读／未读菜单 | 46 项通过 | `search-unread.log` |
| 个人资料音乐条重复点击 | 31 项通过；合并前实现负对照有 7 项失败 | `profile-music.log`、`profile-music-before.log` |
| 活跃会话状态 | 5 项通过 | `active-sessions.log` |
| emoji 状态菜单 | 22 项通过 | `emoji-status-menu.log` |
| emoji 建议算法 | 30,083 项结果与访问次数比较通过 | `emoji-suggestions.log` |
| Regram Core | 120 项通过 | `regram-core.log` |
| Regram 搜索菜单／分组模型 | 14 项通过 | `regram-search-menu.log` |
| Regram 过滤聊天列表 | 176 项通过 | `filtered-chat-list-parity.log` |
| 列表滚动辅助刷新 | 8 项通过 | `list-scroll.log` |
| 原生聊天搜索控件 | 220 项通过 | `chat-search.log` |

音乐条专项提取当前生产 `openProfileMusic` 和 `activeProfileMusic` 实现，检查当前歌曲、状态和上下文复用，以及跨账号、跨资料、缺失播放器状态和缺失内联播放器时的回退。账号、播放器和列表展示是受控替身；脚本、生成源码及哈希均保留在证据目录。

这些是生产源码抽取、受控模型或原生组件回归，没有操作真实账号、发送消息、调用地理编码服务或启动实际音乐播放，也不代表已完成安装版人工验收。

## 已有音乐加载套件失败

`saved-music-loading` 执行 47 个用例，其中 38 个用例失败，共 76 条断言失败。以合并前源码重新运行，失败用例集合及每个用例的断言失败数量相同。

该套件读取的核心 `SavedMusic.swift` 和界面 `SendAudioModalController.swift` 在合并前后字节完全相同。失败涉及已有的加载、分页和变更状态行为，没有在本轮改动核心实现或放宽断言。不能将本轮结果描述为全部回归通过。

对照日志为 `saved-music.log`、`saved-music-before.log`，汇总为 `saved-music-baseline-comparison.json`。两个源码的 SHA-256 分别为 `578a2a38885d9bb2082b3d2cca64e9aff88f4dba163a8f16e3c13e95a3f22c03`、`0aa4b323276df2d2b84e5420e5016d802c39c2f7f29687995c0a5d043802b0fd`。

## 完整构建

通过 `scripts/install-regram-release.py` 的 `build_release` 执行完整 arm64 Release/STABLE 构建，结果为 `BUILD SUCCEEDED`。复用 `/Users/yuki/Library/Caches/RegramReleaseDerivedData-arm64`，包含受影响模块和应用层 hook 的编译及最终链接。

构建包通过同一脚本的 `validate_release_bundle`：应用标识为 `app.regram.macos`，`SOURCE` 为 `STABLE`，主程序为纯 arm64，没有 Debug dylib。构建日志为 `release-build.log`，验证结果为 `release-build-verification.json`。

本轮没有安装、启动构建出的应用或推送远端。安装版及真实账号数据保持原状，构建缓存保留。构建完成后再次核对，原有 107 个本地文件指纹均一致，结果见 `final-preservation.json`。
