# 功能与设置组合回归

从仓库根目录运行一次，不启用定时任务或性能采集。先完成 arm64 Release/STABLE 构建与安装；原生 UI 运行器会生成后续夹具使用的链接配置。

```sh
swift test --package-path packages/RegramCore -c release -Xswiftc -DSTABLE --jobs 2
swift test --package-path packages/RegramServices -c release -Xswiftc -DSTABLE --jobs 2
python3 tools/tests/regram-native-ui/run.py
python3 tools/tests/regram-combinations/run-outgoing.py
python3 tools/tests/regram-combinations/run-services.py
python3 tools/tests/regram-combinations/run-composer.py
python3 tools/tests/regram-combinations/run-toggles.py --native-output /tmp/regram-native-ui --output /tmp/regram-toggle-checks
python3 tools/tests/regram-combinations/run-clipboard.py --native-output /tmp/regram-native-ui --output /tmp/regram-clipboard-checks
python3 tools/tests/regram-chat-regressions/run.py --filter 'RegramComposerPreferenceTests|RegramInputReturnPolicyTests|RegramMentionEntityTests|RegramFilteredReadingTests'
```

运行器使用优化编译和 STABLE。`--output` 选择证据目录，`--products` 指向已有 Core/SwiftSignalKit Release 产物。输入、开关和粘贴运行器使用 `--native-output` 指向已有原生 UI 夹具的 `compile-command.txt`，其中包含完整 Release 依赖和原生链接参数。每个运行器保存生产输入哈希、生成源码、编译日志与执行结果。

## 设置组合的实际覆盖

Core 的 `RegramSettingCombinationTests` 对 165 个声明设置执行 13,530 对组合，每对检查默认／非默认四种值、两个写入顺序和 Codable 往返，共 54,120 个值组合。VoIP TCP 的两个兼容键按同一个设置处理。这检查存储互相覆盖与序列化，不等同于穷举全部界面和运行行为。

额外行为检查覆盖：13,530 对批量变更通知与七种订阅范围、4,096 个过滤／防撤回组合、960 个网络／媒体／导航组合、36,864 个菜单候选权限／双击／独立开关组合、五个备份分类的 32 种部分恢复选择和 32 种分类重置，以及多功能启用时的翻译和识别配置隔离。菜单测试使用受权限限制的给定候选列表，不执行其处理器或替代服务器权限判断。持久化使用独立 UUID 偏好域并清理该测试域。

## 输入转换

`run-outgoing.py` 提取当前生产 Pangu、发送前输入转换和编辑前输入转换。只将账号上下文／共享偏好读取改成显式参数；文字与属性变换主体保持原样。使用真实 InputView、Postbox、TelegramCore 和 RegramCore 数据类型。独立进程初始化自己的主题，不启动 Regram。

覆盖 12,096 个普通输入场景：六种默认格式、全局空格、逐聊天继承／关闭／覆盖、其他功能开关、账号与完整 PeerId 命名空间隔离，以及草稿序列化。另检查七类受保护内容在 12 种默认格式／空格组合下的完整性：提及、链接、行内代码、带语言的预格式代码、自定义表情、引用和格式日期。16 个编辑输入组合验证编辑空格只受编辑开关控制，不继承发送默认格式。

`--source` 可指向保存的修复前 `RegramOutgoingInput.swift`。同一组输入在旧实现中会因预格式代码丢失而失败：旧转换通过显示用的属性字符串重建输入，而显示转换有意略过 `.pre`。当前实现复用 Pangu 的 UTF16 范围映射，直接保留原始输入属性。这里不调用 Sender、编辑消息接口或发送回调。

## 服务同时运行

`run-services.py` 编译完整生产 LLM 及 OpenAI 兼容语音提供方、配置、分段和语言辅助代码。仅注入 URLSessionConfiguration，将所有请求交给进程内 URLProtocol，并将上传临时目录改到夹具拥有的位置。任何意外主机也被夹具拒绝，不能落到真实 HTTP。

同时保留三个翻译请求及第四个排队请求、两个语音请求，再执行模型列表和失败测试请求，共八个合成请求。检查 OpenAI／Anthropic／STT 的请求头、模型、提示词、上下文、队列槽位、取消和失败隔离、返回值归属及临时 multipart 文件清理。语音必须能在翻译队列占满时启动和结束。

`--shared-credential-control` 仅在生成源码中故意把 OpenAI 的请求头替换为同一个测试凭据；必须编译成功后由凭据隔离断言失败。使用显式测试配置，不访问 Keychain 或真实账号。这些检查不是远端提供方可用性、计费、系统语音下载或设备授权验收。

## 同文草稿与设置刷新

`run-composer.py` 提取 ChatController 的实际设置订阅、取消方法、查询触发条件及回调身份／检测令牌判断，配合生产 `RegramComposerRefreshState`、实际偏好信号和 SwiftSignalKit 执行。查询提供方、草稿及上下文是内存替身；共享偏好引用指向独立测试域，不构造真实账号或完整 ChatController。

检查同一份草稿修改预览设置后取消和刷新、内联查询不受预览修改影响、自动内联开关单独刷新、隐藏时取消但不启动新工作、返回后合并刷新、快速编辑只使用最新配置、旧回调拒绝、清理后不再更新和所有者释放。真实 ChatUI 单元测试另覆盖 2,048 个相关设置变换／可见性组合。

`--controller-source` 可指向修复前控制器。旧文件没有相关订阅，夹具保留这个缺失并使用它原有的输入变更条件；编译成功后，“相同草稿修改预览配置应取消和刷新”的断言失败。此负对照不是完整旧应用的端到端操作录像。

## 原生开关与恢复配置

`run-toggles.py` 编译完整链接预览、内联规则、菜单、外观、消息／媒体与展示空间控制器，以及组合设置页的实际控制器声明。使用真实原生表单、NSSwitch 和 SwiftSignalKit。账号上下文、导航、文件夹流和元数据刷新是无副作用替身；偏好、菜单记录和展示空间使用独立 UUID 测试域。展示空间使用实际本地存储与变更信号；非 888 区号查询不在该夹具覆盖内。

覆盖 104 个偏好开关绑定、5,356 对交替操作，以及四个展示空间开关的组合。检查快速连续操作、四组其他功能开关、实际备份恢复、九种分类重置后立即操作、账号隔离，以及资料号码、评级和余额保持不变。实际调用隐藏窗口中的原生控件，不只调用纯设置模型。修复前源码可通过 `--source-directory` 指向保存的七个生产文件；负对照必须编译成功后由开关状态断言失败。断言失败数量不是独立缺陷数量。

## 剪贴板图片分类

`run-clipboard.py` 编译完整 InputPasteboardParser、RegramClipboardImages、附件预览的实际缓存分类方法和 Sender 的 WebP 分支条件。真实 AppKit 剪贴板使用随机名称，临时路径重定向到证据目录；账号、交互、权限、大小限制、错误提示和媒体替换是受控边界，不运行完整 Sender 或真实账号。WebP 由仓库现有 libwebp 编码合成，不下载第三方图片。

检查 PNG、JPEG、TIFF、HEIC、AVIF、WebP，三种 DPI（WebP 单独使用 72）、正常与临时扩展名、图片数据／文件地址／两者并存，以及最高画质开关的两种状态。分别验证聊天输入和追加附件入口的照片分类、画质标记与静态 WebP 分支。另检查普通文档、混合附件和原生小图／超窄图片回退。图片准备保留原始字节；普通画质标记不触发最高画质策略。系统不支持的 ImageIO 编码器会跳过，报告计数以实际运行结果为准。

所有检查不发送聊天消息，不修改真实账号设置，不读取真实凭据。不能把有限两两覆盖或受控请求扩大为任意高阶组合、真实 Telegram 发送／编辑、全部服务端权限或所有硬件授权流程均已验证。
