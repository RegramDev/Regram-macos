<div align="center">
  <p><strong>简体中文</strong> · <a href="README.en.md">English</a></p>
  <img src="Telegram-Mac/Regram.icon/Assets/Regram.png" alt="Regram" width="120" height="120">
  <h1>Regram for macOS</h1>
  <p>基于 Telegram 原生 macOS 客户端，提供更灵活的消息、翻译与外观设置。</p>
  <p>
    <a href="https://github.com/RegramDev/Regram-macos/releases/tag/v13.1.0-283382">下载</a> ·
    <a href="CHANGELOG.md">更新日志</a> ·
    <a href="INSTALL.zh-CN.md">构建说明</a> ·
    <a href="https://github.com/RegramDev/Regram-macos/issues">问题反馈</a>
  </p>
</div>

Regram 是基于 [Telegram for macOS](https://github.com/TelegramMessenger/telegram-macos) 的非官方客户端，沿用 Swift 与 AppKit 原生界面，由 Regram 独立维护。

## 功能

- **消息与记录**：消息菜单与双击动作自定义、直接复读与无引用转发、书签、标签、群备注，以及按作者或共同群组查找消息。
- **翻译与语音**：选择翻译引擎，提供单条、整聊、发送前、网页及图片翻译；支持自定义 LLM 翻译和语音转写。
- **隐私与过滤**：关键词和正则表达式过滤、隐藏用户、过滤规则导入、本地撤回与编辑记录。
- **图片与媒体**：原图复制、高画质图片粘贴、媒体信息查看及链接预览设置。
- **外观与导航**：九款 Regram 图标、紧凑聊天列表，以及底栏项目与宽度调整。
- **设置与网络**：设置搜索、分类备份与恢复、DNS 和代理策略、连接诊断。
- **显摆一下**：本地会员外观、手机号、评级、Stars、TON 和礼物展示。

“显摆一下”只影响本机展示与本地模拟记录，不改变 Telegram 服务端会员权益、真实余额或礼物所有权。外部翻译、LLM 和语音服务按所选提供方配置使用。

## 下载与更新

Regram 13.1.0 (283382) 要求 macOS 12.0 或更高版本，按处理器提供独立安装包：

| Mac | 安装包 |
| --- | --- |
| Apple Silicon（M 系列） | [arm64 DMG](https://github.com/RegramDev/Regram-macos/releases/download/v13.1.0-283382/Regram-13.1.0-283382-arm64.dmg) |
| Intel | [x86_64 DMG](https://github.com/RegramDev/Regram-macos/releases/download/v13.1.0-283382/Regram-13.1.0-283382-x86_64.dmg) |

校验值见 [SHA256SUMS.txt](https://github.com/RegramDev/Regram-macos/releases/download/v13.1.0-283382/SHA256SUMS.txt)，新增功能与修复内容见[更新日志](CHANGELOG.md)。

此版本使用 Apple/Mac Development 开发证书签名，尚未经 Apple 公证。打开下载的 DMG，将 Regram 拖到 Applications（应用程序）文件夹，再从该文件夹启动。

首次打开若被 Gatekeeper 阻止，请先确认下载来自本仓库的 GitHub Releases 且来源可信，再按系统版本操作：macOS 13 或更高版本进入“系统设置 → 隐私与安全性 → 仍要打开”；macOS 12 进入“系统偏好设置 → 安全性与隐私 → 通用 → 仍要打开”，按提示确认打开。详见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)及 [macOS Monterey 官方指南](https://support.apple.com/en-gb/guide/mac-help/mh40616/12.0/mac/12.0)。

Regram 使用独立的应用标识和本地数据目录，可以与 Telegram 同时安装。本版提供自动检查、下载和退出时安装更新，可在 Regram Pro 中调整；也可手动下载并替换应用。更新按当前架构选择安装包，检查下载摘要和应用签名，正常更新保留现有账号与本地数据。

## 从源码构建

完整的工具链、子模块和原生依赖准备步骤见[中文构建指南](INSTALL.zh-CN.md)或 [English build guide](INSTALL.md)。

```sh
git clone https://github.com/RegramDev/Regram-macos.git
cd Regram-macos
cp Telegram-Mac/ApiCredentials.example.xcconfig Telegram-Mac/ApiCredentials.local.xcconfig
```

在本地配置文件中填写自己的 `REGRAM_API_ID` 和 `REGRAM_API_HASH`，完成依赖准备后，使用固定的代码签名证书构建并安装 Release 版本：

```sh
python3 scripts/install-regram-release.py --identity YOUR_CERTIFICATE_SHA1
```

安装脚本默认只构建当前 Mac 的架构，向 Swift 包传入 `STABLE`，校验并安装到 `/Applications/Regram.app`。后续发布按 Apple Silicon 与 Intel 分别打包，见[构建指南](INSTALL.zh-CN.md#separate-architecture-packages)。后续更新省略 `--identity`，继续使用同一证书。API 凭据和本地签名配置由 Git 忽略。

## 问题反馈

请通过本仓库的 [Issues](https://github.com/RegramDev/Regram-macos/issues) 反馈问题，并提供 Regram 版本、macOS 版本和复现步骤。

## 来源与许可

感谢 [Telegram for macOS](https://github.com/TelegramMessenger/telegram-macos) 及 Regram iOS 的贡献者。Regram 相关代码与资源的来源说明见 [Core](packages/RegramCore/ATTRIBUTION.md)、[Services](packages/RegramServices/ATTRIBUTION.md) 和 [UI](packages/RegramUI/ATTRIBUTION.md)。

本项目沿用 [GNU GPL v2](LICENSE) 许可。派生版本应使用自己的 API 凭据、应用名称、图标与签名配置，并保留原作者及第三方资源的署名和许可。
