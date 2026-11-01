# 2026-11-01 富文本旧测试修正与完整回归

以 `8eb9fb33` 为基线，修正此前完整富文本测试暴露的两类旧夹具问题。完整 macOS 编辑器和共享核心套件，以及聊天端富文本集成回归，共 1,230 项通过，零失败。

## 修正内容

普通文字的颜色由当前主题提供，读取格式时不应把显示颜色固化进文档模型。原有两条测试仍期待读回前景色。本轮改为检查前景色保持空值，保留下划线、粗斜体、删除线、底色及基线偏移的验证，并检查红／黑／白来源文字在黑白两种主题中重新渲染时采用当前主题颜色，下划线仍保留。

图片已经通过 `MediaBlockBox` 和宿主视图渲染。旧图片、表格导航、Tab、间隙光标和全宽布局测试仍查找或强转为 `ImageBlockBox`，导致进程中断。本轮接入受控宿主视图，并改用实际的媒体选区、上下文与布局接口；保留选中／取消／删除、跨图片标题选区、标题编辑、Shift+Return、间隙光标、表格前后导航和全宽图片布局的断言。类型检查使用 `XCTUnwrap`，失败时报告测试错误。

`ImageBlockBox` 自身的显式宽度测试直接构造该类，与同文件中的独立几何测试一致；画布集成测试验证当前宿主图片视图的实际布局。

共修改十个测试文件，涉及的测试方法数量在修正前后均为 83，没有删除或跳过用例。编辑器 61 个生产源码文件的摘要全部一致，本轮未修改生产实现。

## 完整回归结果

运行平台为 arm64 macOS，全部使用 Release 配置，并向 Swift 传入 `STABLE`。

| 套件 | 结果 | 证据目录内日志 |
| --- | --- | --- |
| RichTextEditorUI 完整 macOS 套件 | 689 项通过，零失败 | `editor-full-2.log` |
| RichTextEditor 共享核心完整套件 | 538 项通过，零失败 | `core-full.log` |
| ChatUI 聊天选词与 Article 草稿编解码 | 3 项通过，零失败 | `chat-rich-text.log` |
| 合计 | 1,230 项通过，零失败 | `regression-summary.json` |

前两个套件执行完整 `swift test`，没有筛选或跳过测试。聊天集成回归验证真实 InstantPage 布局下中文、复杂 emoji、旗帜、肤色、组合音标及标点的双击选区，并通过实际 Postbox 编解码器检查富文本草稿往返及缺失页面错误。

主要命令：

```sh
swift test --package-path packages/RichTextEditorUI --configuration release -Xswiftc -DSTABLE --jobs 2
swift test --package-path submodules/telegram-ios/submodules/TelegramUI/Components/RichTextEditor --configuration release -Xswiftc -DSTABLE --jobs 2
PYTHONDONTWRITEBYTECODE=1 python3 tools/tests/regram-chat-regressions/run.py --package ChatUI --filter 'ChatRichTextWordSelectionTests|ChatRichTextDraftPersistenceTests'
```

证据目录为 `/tmp/regram-rich-text-regressions-20261101`。解除首处图片崩溃后，首次完整运行暴露了表格插入测试中相同的旧类型查找；补齐同类夹具后，第二次完整运行通过。方法数量与重命名见 `test-inventory.json`，原始状态和生产文件摘要见 `baseline.json`。

## 本地改动保留

原有父仓库 31 个本地文件和核心子模块 77 个本地文件，共 108 个文件，内容摘要全部保留。核心子模块版本与原有工作区状态保持一致，见 `preservation.json`。

本轮仅提交测试及回归记录，没有安装应用或推送远端。
