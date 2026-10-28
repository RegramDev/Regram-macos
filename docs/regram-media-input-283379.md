# Regram 283379：图片预览与中文候选框定位

用户报告聊天图片出现局部清晰、局部模糊，以及 Intel/macOS 12 上中文候选框落在屏幕左下角。第二项已确认是候选框定位问题。

## 修复

聊天输入框原本直接继承 NSTextView 的字符范围查询。在真实 InputTextView 上，`NSNotFound` 范围得到 `(0, 0, 0, 0)`，而相同组合输入的明确选区可以得到正常屏幕坐标。现在查询前同步文本布局，按 UTF-16 长度将未指定范围解析为当前光标、限制越界请求，再交给原生方法计算屏幕坐标。窗口、祖先视图或滚动位置变化会合并刷新输入法坐标；失去焦点或移出视图后撤销观察，不改变组合输入或重新获取焦点。

渐进式 JPEG 的不完整数据原本会作为清晰图直接绘制。使用重复棋盘图和真实 ImageIO 解码可以复现上下细节明显不同，1x 对比度约为 224/161。现在不完整数据只生成模糊预览，完整文件到达后使用既有缩放解码显示清晰图片。完整渐进数据按最终字节数识别；完整资源使用 MediaBox 的整文件接口读取，支持没有声明资源大小的旧图片。`autoFetchFullSize` 下载所选完整资源，避免仅请求早期扫描段而一直停留在预览。

## 验证

`tools/tests/photo-preview-input/run.py` 直接编译全部 InputView 源码、MediaUtils 的原始绘制闭包与渐进数据分支，使用 Release 缓存依赖、优化、STABLE 和 macOS 12 部署目标。数据分支仅用持有真实隔离 MediaBox 的容器替代 Postbox 参数，下载由本地合成数据提供，不访问账号或网络。真实 NSTextView 和 ImageIO 的几何与像素检查使用不显示、不激活的独立窗口。

- arm64：617 项通过。覆盖未指定和越界字符范围、Unicode、连续组合输入、长文滚动、祖先与窗口移动、负屏幕坐标、焦点转移，以及 1x/2x 图片、圆角透明度和下载完成后的清晰图。
- HEAD 负对照：相同 617 项出现 297 项失败，包含零坐标、图片上下清晰度差异、自动下载未完成以及未知大小的缓存读取。
- x86_64：同组 617 项通过，使用 Intel Release 依赖编译并在 Rosetta 中运行。
- 隔离 MediaBox 覆盖五段/六段渐进数据、有/无声明资源大小、被动预览不启动下载、完整下载与完整缓存。新建 MediaBox 时上游 StorageBox 会输出不存在 `t19` 的初始化诊断；检查通过，不涉及用户数据库。

arm64 Release/STABLE 整包构建成功，已使用 `scripts/install-regram-release.py` 安装至 `/Applications/Regram.app` 并启动。全部 5 个二进制均为纯 arm64，固定签名与本地配置一致，deep/strict 校验通过。构建前后的根仓库与子模块源码指纹一致。启动后的真实聊天窗口及一张完整聊天图片已检查，保留现有草稿、账号和聊天数据，未输入或发送测试消息。

两个架构的 Release/STABLE 整包构建、签名和 DMG 打包均成功。两个 DMG 均已只读挂载，实际包内版本、STABLE、macOS 12 最低系统版本、各 5 个代码组件的纯架构与固定签名、下载文件 SHA-256 均通过验证。全部临时测试应用和构建应用已删除，保留回归报告、渲染图片和构建缓存。

| 架构 | 安装包 | 字节数 | SHA-256 |
| --- | --- | --- | --- |
| Apple Silicon | `~/Downloads/Regram/Regram-13.1.0-283379-arm64.dmg` | 93,147,953 | `6ac77d6721f1ab728e47f4322bb2fc000245f78e89524a44ce4d7fc6528b8a04` |
| Intel | `~/Downloads/Regram/Regram-13.1.0-283379-x86_64.dmg` | 101,161,365 | `3e191985f9cf47bac4d156b3f0bab3faa95d1bb1a10eb5e4fe528f073d0a60bb` |

原生检查运行于 Apple Silicon/macOS 27.0.1。Rosetta 检查不能代替 Intel/macOS 12 真机候选框验收，该项仍需在用户报告问题的机器上复测。

原生检查产物：`/tmp/regram-photo-input-final-arm64/`、`/tmp/regram-photo-input-final-x86_64/`、`/tmp/regram-photo-input-final-before/`。构建与签名证据：`~/Library/Logs/RegramRelease/283379-20261028/`。

## 系统输入法补充验证

用户明确主要使用系统输入法。此前回归覆盖简体中文、Unicode 和连续组合输入，没有逐一运行繁体等实际输入法引擎。本次补充原生 NSTextInputClient 组合输入契约验证，覆盖简/繁体拼音、繁体注音、仓颉、日文假名与汉字转换、韩文拼合、拉丁重音、越南文组合音标及阿拉伯文/希伯来文。

在 140/380 宽度的真实 ChatInputTextView 上检查标记文字、候选条款选区、UTF-16 与字素范围、显式替换、确认、取消和前后文本保留。arm64 与 x86_64/Rosetta 各 4,122 项全部通过；同组 HEAD 负对照出现 640 项零坐标/不可见锚点失败。生产代码与已安装、已打包的 283379 一致，本次只增加回归和记录。

这些检查直接调用真实 NSTextView 的输入客户端接口，没有启用或运行各语言的输入法引擎。本机仅启用 ABC 和简体拼音，未修改输入源设置。报告中明确记录 `realInputMethodEngineExercised: false`。Intel/macOS 12 上各系统输入法的实际候选窗位置仍需真机验证。

补充产物：`/tmp/regram-system-input-arm64-283379/`、`/tmp/regram-system-input-x86_64-283379/`、`/tmp/regram-system-input-before-283379/`；对应报告和生产源码一致性记录已保存到上述构建证据目录。
