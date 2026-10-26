# 构建 Regram macOS 版

[English](INSTALL.md) · [中文项目介绍](README.md)

应用通过 Xcode 工作区（`Telegram-Mac.xcworkspace`）构建，链接 `core-xprojects/`
中预先构建的原生库，以及 `packages/` 和 `submodules/telegram-ios/submodules/`
中的本地 Swift 包。项目没有远程 Swift 包依赖，因此检出全部子模块后即可离线构建。

## 安装发布包

下载 [Regram 13.1.0 (283368) Universal DMG](https://github.com/RegramDev/Regram-macos/releases/download/v13.1.0-283368/Regram-13.1.0-283368-universal.dmg)。此版本支持 Intel 与 Apple Silicon Mac，要求 macOS 12.0 或更高版本。

此版本使用 Apple/Mac Development 开发证书签名，尚未经 Apple 公证。打开下载的 DMG，将 Regram 拖到 Applications（应用程序）文件夹，再从该文件夹启动。

首次打开若被 Gatekeeper 阻止，请先确认下载来自本仓库的 GitHub Releases 且来源可信，再按系统版本操作：macOS 13 或更高版本进入“系统设置 → 隐私与安全性 → 仍要打开”；macOS 12 进入“系统偏好设置 → 安全性与隐私 → 通用 → 仍要打开”，按提示确认打开。详见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)及 [macOS Monterey 官方指南](https://support.apple.com/en-gb/guide/mac-help/mh40616/12.0/mac/12.0)。

## 环境要求

- 运行 macOS 的 Apple Silicon 或 Intel Mac。Apple Silicon 需要安装 Rosetta 2：
  `tde2e` 构建过程会编译并运行一个 x86_64 代码生成工具。
- 完整的 Xcode 16 或更新版本，仅安装 Command Line Tools 不够。
  Xcode 27 仅支持 macOS 12.0 及更新的部署目标，因此构建前需要应用
  [XCODE27.md](XCODE27.md) 中的本地调整。将 Xcode 设为当前开发工具目录：
  ```
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```
- Homebrew 及以下软件包：
  ```
  brew install cmake ninja meson nasm yasm openssl@1.1 zlib autoconf libtool automake pkg-config
  ```
- 通过 rustup 安装的 Rust 工具链。TON 钱包引擎（`wallet-engine`）和 tlottie
  贴纸渲染器均为 Rust 库；其构建脚本会从 `PATH` 或 `~/.cargo/bin` 查找 `cargo`，
  rustup 会自动安装引擎 `rust-toolchain.toml` 指定的工具链。tlottie 使用
  `mtproto-engine` 的工具链构建，使应用中的 Rust 库使用同一套标准库。
  ```
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
  ```
- 能够访问 `github.com` 和 `gitlab.com` 的 Git 环境，用于获取子模块。
  `.gitmodules` 中的地址使用 SSH。如果只能通过 HTTPS 访问，请在克隆前添加地址重写：
  ```
  git config --global url."https://github.com/".insteadOf "git@github.com:"
  git config --global url."https://gitlab.com/".insteadOf "git@gitlab.com:"
  ```

## 1. 克隆仓库及子模块

```
git clone --recurse-submodules https://github.com/RegramDev/Regram-macos.git
cd Regram-macos
```

已有工作副本可执行：

```
git submodule update --init --recursive
```

`--recursive` 不可省略：`submodules/telegram-ios` 中还包含构建原生库所需的嵌套子模块，
例如 `third-party/td`、`third-party/dav1d`、`third-party/libvpx`、
`third-party/webrtc` 和 `third-party/wallet-engine`。

如果此 Regram 工作副本中的可选仓库 `third-party/twidget` 或
`third-party/widget-sandbox` 无法访问，可以显式初始化应用所需的依赖：

```
git submodule update --init --recursive -- submodules/libtgvoip submodules/Sparkle submodules/telegram-ios submodules/rlottie submodules/tgcalls submodules/tg_owt submodules/libprisma submodules/regex submodules/tlottie
bash scripts/prepare-regram-core.sh
```

上述两个 widget 仓库不是原生应用的依赖。打开工作区前先应用[仓库维护的核心补丁](patches/README.md)；
原生库准备流程也会应用该补丁。Regram 使用独立的应用标识和数据路径，自动更新已停用，
后续版本需手动安装。

构建 Regram 前，先配置 Telegram API 凭据：

```
cp Telegram-Mac/ApiCredentials.example.xcconfig Telegram-Mac/ApiCredentials.local.xcconfig
```

在本地文件中填写 `REGRAM_API_ID` 和 `REGRAM_API_HASH`。该文件已被 Git 忽略，
Debug 和 Release 配置都会包含它。主应用与分享扩展分别从各自处理后的 Info.plist
读取这些值，不会回退到官方客户端的 API 凭据。

## 2. 准备构建环境

```
sh scripts/setup_build_env.sh
```

该脚本可以重复运行，会自动完成环境要求中能够自动化的步骤：安装 Homebrew 和软件包，
在 Apple Silicon 上安装 Rosetta 2，检查是否选中完整的 Xcode，递归初始化子模块，
并修补 `tg_owt` 内 abseil 副本中的 `ABSL_ATTRIBUTE_LIFETIME_BOUND`，避免新版 clang
拒绝编译。脚本不安装 Rust，请按前述说明自行安装。

加上 `--build` 参数，可在完成准备后直接进入第 3 步。

## 3. 构建原生库（首次执行）

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CMAKE_POLICY_VERSION_MINIMUM=3.5 \
sh scripts/configure_frameworks.sh
```

这一步耗时较长，主要时间花在 WebRTC 上。脚本会：

1. 使用 SwiftTL 生成 TelegramApi 的 SwiftPM 源码，再通过仓库自带的 `scripts/flatc`
   生成 TelegramCore 的 FlatSerialization 源码。
2. 依次通过 `core-xprojects/<lib>/` 中的工程构建 `OpenH264`、`OpenSSLEncryption`、
   `libopus`、`libvpx`、`Mozjpeg`、`libwebp`、`dav1d`、`ffmpeg`、`webrtc`（tg_owt）、
   `tde2e` 和 `WalletEngine`。产物位于被 Git 忽略的 `core-xprojects/<lib>/build`。
   `WalletEngine` 还会重新生成已纳入版本管理的
   `packages/WalletEngine/Sources/WalletEngineFFI/WalletEngineFFI.swift`，以及被忽略的
   `packages/WalletEngine/wallet_engineFFI.xcframework`。
3. 将公开头文件复制到 `tgcalls`、OpusBinding、FFMpegBinding、OpenSSLEncryptionProvider、
   libwebp 和 Mozjpeg 包所需的 `SharedHeaders` 目录。
4. 为 `TdBinding` 执行 `td` 的 macOS 清理步骤。

准备流程会比较源码、工具链及依赖指纹，并检查必需的库、头文件与 Rust 绑定产物，
再决定是否复用已有构建。有效的缓存会跳过对应原生库的 Xcode 构建调用。
缺失或不一致的产物会被修复，只有产物检查通过后才写入成功标记。
没有成功标记的构建目录会重新构建，不会直接视为完整产物。
如需全部重新构建，将 `scripts/rebuild` 的内容改为 `yes`（默认为 `no`），
运行脚本后再改回 `no`。

CMake 4 已不再支持 mozjpeg 和 td 仍在声明的旧版 `cmake_minimum_required`，
因此使用 CMake 4 时需要设置 `CMAKE_POLICY_VERSION_MINIMUM=3.5`。

使用 Xcode 27 时，请在此步骤前运行 `scripts/xcode27.sh apply`：
这些原生库工程的部署目标为 macOS 10.11–10.13，Xcode 27 会拒绝构建。
详见 [XCODE27.md](XCODE27.md)。

### 仅重建钱包引擎

更新 `telegram-ios` 子模块后，或缺少 `wallet_engineFFI.xcframework` 时，执行：

```
sh core-xprojects/wallet-engine/wallet-engine/build.sh \
  submodules/telegram-ios/third-party/wallet-engine/wallet-engine \
  core-xprojects/wallet-engine/build \
  packages/WalletEngine
```

如果重新生成的 `WalletEngineFFI.swift` 发生变化，应将其提交。
xcframework 不纳入版本管理，每台机器自行构建。

## 4. 构建应用

在 Xcode 中打开 `Telegram-Mac.xcworkspace`，而非 `Telegram.xcodeproj`。
工作区还包含应用需要链接的 `RLottie_Xcode`、`CodeSyntax` 和 `Sparkle` 工程，
单独构建 `Telegram.xcodeproj` 无法找到它们。

可用方案：

| Scheme | 用途 |
| --- | --- |
| `Telegram` | 开发工具，使用 Debug 配置（`Telegram-Mac/Debug.xcconfig`） |
| `TelegramShare` | 单独构建分享扩展 |
| `Release` | Regram 测试与分发（`Telegram-Mac/Release.xcconfig`） |

命令行构建：

```
xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Release -configuration Release \
  MACOSX_DEPLOYMENT_TARGET=12.0 \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) STABLE' build
```

v13.1.0-283368 发布版的部署目标为 macOS 12.0 或更高版本。
Swift 包从工作区中的本地路径解析，不需要访问网络。

<a id="universal-build"></a>

### 通用架构构建

如需同时构建两种架构，请使用与发布版相同的部署目标：

```
xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Release -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/RegramUniversal \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=12.0 \
  CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) STABLE' build

python3 scripts/install-regram-release.py --skip-build \
  --derived-data build/RegramUniversal --identity YOUR_CERTIFICATE_SHA1
```

`ARCHS='arm64 x86_64'` 与 `ONLY_ACTIVE_ARCH=NO` 保留两种架构。
安装程序默认会按当前机器的架构重新构建；使用 `--skip-build`，并指定同一个
`--derived-data` 目录，才能直接为已有 Universal 应用签名和安装，避免重建为单一架构。
保存过签名身份后，可以省略 `--identity`，继续使用该证书。

### 生成 TelegramApi 源码

`scripts/configure_frameworks.sh` 会在 Xcode 解析包之前准备生成的 Swift 和 Objective-C
API 源码。两条 CI 构建路径都会在构建或归档前执行此准备。
共享的 `Telegram`、`Release` 和 `TelegramShare` 方案也会在常规构建前刷新生成结果。
两个应用目标都会检查生成文件，避免生成器失败后仍静默使用过期产物。

生成过程支持增量处理：会检查 schema、SwiftTL 源码、生成脚本、选定的 Swift 工具链
及生成文件的内容。未变化文件的时间戳保持不变。生成过程在临时目录中运行，
只将完整结果写入目标位置；并发准备调用会串行执行。生成产物和准备标记均被 Git 忽略。

如果工作副本已有原生库，但尚未生成 API 源码，请在**打开 Xcode 或调用 `xcodebuild` 前**先执行一次：

```
python3 scripts/prepare-telegram-api.py
```

常规原生库准备与 CI 流程已包含此步骤。Xcode 在方案预操作执行前就会发现包内源码文件，
因此首次构建缺少文件时，仅靠预操作无法完成初始化。
如果子模块更新改变了生成文件名集合，先执行准备，再重新打开工作区，刷新包源码发现结果。
直接使用 `swift build`／`swift test` 构建或测试包时，也应先执行准备。

不构建主应用即可运行以下专项检查：

```
python3 tools/tests/telegram-api-generation/test_generation.py
python3 tools/tests/telegram-api-generation/xcode.py
python3 tools/tests/no-paid-messages-token/run.py
```

Xcode 检查会使用一份干净的 TelegramApi 副本构建临时命令行应用，
然后检查增量生成、schema 变化及生成器失败处理，并输出保存构建日志的临时目录。

<a id="local-regram-testing-and-updates"></a>

### 本地 Regram 测试与更新

本地 Regram 测试使用 Release 配置，并安装、启动固定路径 `/Applications/Regram.app`。
安装程序默认只为当前 Mac 的架构构建，向 Swift 包传入 `STABLE`，检查调试功能已排除，
并使用固定证书签名。替换验证通过后才删除旧应用及临时构建的应用包，
编译缓存与应用数据会保留。

首次使用时，通过 `security find-identity -v -p codesigning` 获取证书的 SHA-1 指纹，
并配置签名证书：

```
python3 scripts/install-regram-release.py --identity YOUR_CERTIFICATE_SHA1
```

指纹保存在被 Git 忽略的 `Telegram-Mac/Signing.local.json`。
后续更新执行相同命令，但省略 `--identity`，继续使用同一证书。不接受临时签名（ad-hoc signing）。
保持签名要求稳定，可使钥匙串识别更新后的应用；详见 Apple 的
[代码签名要求说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。
Regram 为每个渠道使用独立的密码锁与钱包钥匙串作用域，不导入 Telegram 凭据。
更新应用会保留已有 Regram 登录与本地数据。

安装程序会在验证成功前保留旧应用，以便回退。安装后启动已安装的应用。
安装程序的检查可通过以下命令运行：

```
python3 -m unittest discover -s tools/tests/regram-release-install -p 'test_*.py' -v
```

### 签名

主应用使用 `app.regram.macos`，分享扩展使用 `app.regram.macos.share`。
源码工程中的开发团队字段留空。如需自行分发，应配置与证书匹配的团队及签名权限。
本地安装程序使用同一已保存的身份为更新签名，不要复用 Telegram 的应用标识或凭据。

## 上游构建配置与 CI 参考

本节说明从 Telegram 继承的渠道与 CI 脚本，供理解上游构建方式使用。
部分脚本仍依赖 `Telegram.app` 名称和 Telegram 发布运行器的配置。
本地 Regram Release 构建与更新请使用[本地安装程序](#local-regram-testing-and-updates)。
Regram 安装包通过本仓库的
[GitHub Releases](https://github.com/RegramDev/Regram-macos/releases) 分发，自动更新继续停用。

`Telegram-Mac/common.xcconfig` 保存共享设置。渠道通过 xcconfig 选择，
该文件定义 `TYPE`（Swift 编译标志）以及 Sparkle 更新源地址：

| xcconfig | `TYPE` | 更新源 |
| --- | --- | --- |
| `Telegram-Mac/Debug.xcconfig` | 无 | beta 更新源 |
| `Telegram-Mac/Release.xcconfig` | `STABLE` | `mac-updates.telegram.org/updates` |
| `configurations/Stable.xcconfig` | `STABLE` | stable 更新源 |
| `configurations/Beta.xcconfig` | `BETA` | `mac-updates.telegram.org/beta` |
| `configurations/Alpha.xcconfig` | `ALPHA` | AppCenter 更新源 |
| `configurations/AppStore.xcconfig` | `APP_STORE` | 无（Mac App Store 构建） |

`buildbox/build-mac.sh <Alpha|Beta|Stable|AppStore>` 是上游的发布构建脚本：
将源码树复制到 `~/build-<channel>`，运行 `scripts/configure_frameworks.sh`，
以选定的 `configurations/<channel>.xcconfig` 覆盖 `Telegram-Mac/Release.xcconfig`，
然后运行：

```
xcodebuild archive -workspace Telegram-Mac.xcworkspace -scheme Release -configuration Release \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) <CHANNEL>'
```

其中 `<CHANNEL>` 为 `ALPHA`、`BETA`、`STABLE` 或 `APP_STORE`。
xcconfig 中的 `TYPE` 只会传入应用目标；`packages/` 下的 Swift 包不会读取它，
因此渠道条件由命令行显式传入，才能作用于包括包在内的所有目标。
从 Xcode 界面启动的构建不会取得这一条件，所以包内的
`#if BETA`／`STABLE`／`ALPHA`／`APP_STORE` 在该场景下均为 false。

随后脚本会提取 `Telegram.app` 及其 dSYM。GitLab 通过 `buildbox/internal.sh`
运行这条直接在 Mac 上构建的路径；该脚本持有现有的整机级锁，验证并部署产物。
`buildbox/build.sh` 则是另一条旧版 Parallels 虚拟机构建路径。

### CI 构建复用与耗时

源码同步会保留原生库产物、生成的 TelegramApi 与 FlatSerialization 源码、SwiftTL
构建缓存以及生成的共享头文件。生成器仍会执行检查；未变化的 Swift 文件与头文件
保持原时间戳，已移除的生成文件会被删除。tlottie 仍由 Cargo 检查输入，
但不会替换内容相同的通用二进制库。

GitLab 将 `.ci-build-logs/<job-id>/` 保留七天，失败任务的日志也会保留，其中包括：

- `frameworks.log`：准备流程输出及原生库缓存决策。
- `xcodebuild.log`：完整归档输出和 Xcode 构建耗时汇总。
- `timings.tsv`：各阶段的实际耗时与退出码；汇总 `build` 行包含其内部的准备、归档和压缩阶段。

归档构建会关闭编译器索引。优化、两种 CPU 架构、渠道条件、签名、dSYM 和部署串行机制均保持。
没有额外加入清理 DerivedData 的步骤，Xcode 继续使用其常规目录。

如果运行器支持编译缓存，可以设置 CI 变量 `TELEGRAM_COMPILATION_CACHE=YES`，
试用带诊断信息的 Xcode 编译缓存。`NO` 会显式关闭缓存；不设置时保留工具链默认行为。
永久启用前，应比较基线构建、重复构建和少量源码变更后的构建。
常规流水线不会主动启用该设置。

`TELEGRAM_BUILD_ROOT` 可选地指定 `build-<channel>` 目录的位置，默认为用户主目录。
隔离的脚本测试也会使用此变量。它不会放宽整机级构建锁的限制。

以下专项检查不会执行部署：

```
python3 tools/tests/ci-build/test_incremental.py
python3 tools/tests/telegram-api-generation/test_generation.py
python3 tools/tests/ci-build/xcode.py
```

第一组测试使用临时样本覆盖缓存命中、依赖失效、产物缺失、生成失败、源码与头文件同步、
全部发布渠道参数及打包失败。Xcode 冒烟测试会针对一个小型、未签名的通用应用运行真实归档脚本，
分别在默认设置和开启编译缓存时检查渠道条件及 dSYM。
它不能替代在发布运行器上验证已签名的 Telegram 归档。

版本号在发布时手动递增，不是每次构建都递增：运行
`tools/bump_build_number.sh Telegram-Mac/Info.plist` 增加 `CFBundleVersion`，再运行
`tools/sync_share_version.sh Telegram-Mac/Info.plist TelegramShare/Info.plist`，
使分享扩展版本保持一致（App Store 验证要求二者一致）。这些操作过去在 `Telegram`
目标的构建阶段运行，每次构建都会改写 `Info.plist`，导致每次增量构建都重新打包和链接应用。

## 本地化字符串

`Telegram-Mac/en.lproj/Localizable.strings` 使用 UTF-16，编辑时请保留该编码。
添加字符串后，重新生成 Swift 访问接口：

```
brew install swiftgen
sh tools/swiftgen.sh
```

输出文件为 `packages/Localization/Sources/Localization/Localizable.swift`。

## 运行包测试

无需构建整个应用，也可以单独构建或测试 Swift 包，例如：

```
cd packages/WalletEngine && swift test
cd packages/TGUIKit && swift build
```

## 故障排查

- **Apple Silicon 构建 tde2e 时出现 “Bad CPU type in executable”**：
  安装 Rosetta 2（`softwareupdate --install-rosetta --agree-to-license`）。
- **CMake 报错涉及 `cmake_minimum_required`**：运行 `configure_frameworks.sh` 前设置
  环境变量 `CMAKE_POLICY_VERSION_MINIMUM=3.5`。
- **构建 webrtc 时，clang 报错涉及 abseil 的 `lifetimebound`**：
  再次运行 `scripts/setup_build_env.sh`，由脚本应用补丁。
- **Xcode 报告缺少库或 `SharedHeaders` 目录**：过期的 `core-xprojects/<lib>/build`
  目录导致该库被跳过。删除该目录后，重新运行 `configure_frameworks.sh`。
- **找不到 `wallet_engineFFI.xcframework`**：构建原生库时 Rust 不可用。
  安装 rustup 后，重新运行 `configure_frameworks.sh` 或前述钱包引擎构建脚本。
- **已安装 Rust，但找不到 `cargo`**：引擎构建脚本会查找 `PATH` 和 `~/.cargo/bin`；
  如果安装在其他位置，请设置 `CARGO=/path/to/cargo`。
- **出现 `library 'tlottie' not found`**：缺少 `core-xprojects/tlottie/build/libtlottie.a`。
  运行 `sh core-xprojects/tlottie/build.sh`，或重新运行 `configure_frameworks.sh`。
- **出现 `duplicate symbol '_rust_eh_personality'`**：tlottie 与引擎使用了不同的 Rust 工具链。
  删除 `core-xprojects/tlottie/build`，重新运行 `sh core-xprojects/tlottie/build.sh`。
- **找不到 RLottie 或 CodeSyntax**：打开的是 `Telegram.xcodeproj`，请改为打开工作区。
- **出现 “The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 10.13, but the range
  of supported deployment target versions is 12.0 to 27.0.x”**：当前使用的是 Xcode 27。
  运行 `scripts/xcode27.sh apply`（详见 [XCODE27.md](XCODE27.md)），并在提交前运行
  `scripts/xcode27.sh revert`。
- **更新 `telegram-ios` 子模块后 TelegramCore 立即构建失败**：新导入的模块必须在
  `submodules/telegram-ios/submodules/TelegramCore/Package.swift` 中声明，
  请在那里补充缺少的依赖。

## 开发自己的派生版本

1. 先按上述说明构建应用。
2. 申请自己的 [API ID](https://core.telegram.org/api/obtaining_api_id)。
3. 在 `Telegram-Mac/ApiCredentials.local.xcconfig` 中设置 `REGRAM_API_ID`
   和 `REGRAM_API_HASH`。在 Xcode 目标设置与 Regram Info.plist 键中配置应用标识和开发团队。
4. 在工程设置、entitlements、应用组和 `Regram*` Info.plist 键中保持应用标识与团队一致。
   Regram 当前的应用标识为 `app.regram.macos`。
5. 替换或移除 xcconfig 文件中的 `SFEED_URL`、`DSA_PEM_FILE` 和 `APPCENTER_SECRET`。
   它们指向 Telegram 的 Sparkle 更新源和 AppCenter 崩溃收集服务。
6. 遵循 [README.md](README.md) 中的署名和许可要求：使用自己的品牌，
   并保留源码与资源的许可。
7. 如有问题，请在 https://github.com/RegramDev/Regram-macos/issues/new 创建 issue。

## 性能实验与上游 CI 发布检查

性能实验工具仍可在 Debug 构建中使用。PerfLab 实现、NetworkLab 和功能实验入口仅在
`DEBUG` 条件下编译；CI 在所有分发渠道均使用 Release 归档。

部署前，`buildbox/verify-build.sh` 会针对已构建应用运行 `buildbox/verify-no-labs.py`。
该检查会扫描所有 Mach-O 二进制文件，包括内嵌框架和扩展，拒绝包含实验工具命名产物、
实验符号或启动标记的应用。调试元数据仅从临时检查副本中移除，避免已排除源码的文件引用
造成误报；已签名应用不会被修改。检查失败会阻止部署。调整实验工具代码或构建标志时，
请保留此项检查。

运行 `python3 -m unittest discover -s buildbox -p 'test_verify_no_labs.py' -v`
执行原生测试样本检查。这些检查覆盖干净、受污染、已剥离及嵌套的二进制文件，
不能替代对实际 CI 归档的验证。
