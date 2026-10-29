# Regram 共享语言包

`Regram/en.json`、`Regram/zh-Hans.json` 和 `Regram/zh-Hant.json` 是 iOS 与 macOS 的共同源文件。包含 1694 个共用键；`macos` 包含 27 个平台覆盖或 macOS 专用文案。`nativeMacos` 包含 37 个原生界面补充文案，例如聊天记录导出。

生成两端资源：

```sh
python3 scripts/generate-regram-language-pack.py
python3 scripts/generate-regram-language-pack.py --check
```

macOS 的输出直接写入 `packages/RegramCore/Sources/RegramCore/Resources/*/Regram.strings`，随应用内置，跟随应用语言加载，支持英文、简体中文、繁体中文及地区代码。原生界面补充文案只合并到对应语言，不覆盖其他语言。

iOS 的输出位于 `generated/ios/*/RGLocalizable.strings`，随共享源文件一并提供，兼容现有 `RGLocalizationManager` 的资源格式和键名。提供资源不代表已发布或验证 iOS 应用。需要同步到独立 iOS 工作副本时运行：

```sh
python3 scripts/generate-regram-language-pack.py --ios-root /path/to/Regram-ios
```

`ios-language-link.patch` 为 iOS 的语言管理器补上 `regram-zh-hans` 和 `zhcncc` 短名识别，并包含对应测试。它供独立 iOS 项目按需采用，不是生成 macOS 资源的依赖，也不表示完成了 iOS 整包或设备验证。

生成器检查键名一致性、非空值和格式参数，也会校验 `.strings` 语法。`--check` 只检查，不改写文件。修改文案后重新生成，提交源文件和两端输出；不直接编辑生成文件。向 iOS 项目同步后仍需在该项目独立验证。

输出默认按键名排序。`manifest.json` 中可选的 `macosInsertBefore` 指定 macOS 键的兼容位置，保留现有应用资源的字节顺序；它不影响 iOS 输出。约束的键和目标必须存在，不能自指或形成环。

标准分享链接为 `https://t.me/setlanguage/regram-zh-hans`，对应的翻译项目为 `https://translations.telegram.org/regram-zh-hans/`。在线语言包尚未完成，不属于本版交付。应用内置的三语资源可以独立生成和使用；更新这些资源不代表在线项目已更新，Release 也不附带在线语言包导入文件。

参考语言包为 [zhcncc](https://t.me/setlanguage/zhcncc)。可自行访问其 [iOS 翻译页面](https://translations.telegram.org/zhcncc/ios/) 或 [macOS 翻译页面](https://translations.telegram.org/zhcncc/macos/)，使用 Export File 获取对应平台文件。参考译文归原语言包的贡献者所有，导出文件不随本仓库发布，也不是生成内置资源的依赖。创建 Regram 翻译项目不表示已继承或发布其译文。

Telegram 翻译平台提供原生界面的语言包。Regram 自有功能的文案继续由两端共享资源提供，跟随已安装语言包的短名加载；不能假定平台接受 Regram 新增的字符串键。
