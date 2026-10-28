<div align="center">
  <img src="Telegram-Mac/Regram.icon/Assets/Regram.png" alt="Regram" width="120" height="120">
  <h1>Regram for macOS</h1>
  <p>Based on Telegram's native macOS client, with more flexible messaging, translation, and appearance settings.</p>
  <p>
    <a href="README.md">简体中文</a> · <strong>English</strong>
  </p>
  <p>
    <a href="https://github.com/RegramDev/Regram-macos/releases/tag/v13.1.0-283382">Download</a> ·
    <a href="CHANGELOG.en.md">Changelog</a> ·
    <a href="INSTALL.md">Build instructions</a> ·
    <a href="https://github.com/RegramDev/Regram-macos/issues">Report an issue</a>
  </p>
</div>

Regram is an unofficial client based on [Telegram for macOS](https://github.com/TelegramMessenger/telegram-macos). It uses the native Swift and AppKit interface and is maintained independently by Regram.

## Features

- **Messages and history**: Customizable message menus and double-click actions, immediate resending and forwarding without attribution, bookmarks, tags, group aliases, and message searches by author or across shared groups.
- **Translation and speech**: Choose a translation engine for individual messages, entire chats, outgoing messages, web pages, and images; use custom LLM translation and speech transcription.
- **Privacy and filtering**: Keyword and regular expression filters, hidden users, filter rule imports, and local records of deleted and edited messages.
- **Images and media**: Copy original images, paste high-quality images, inspect media information, and configure link previews.
- **Appearance and navigation**: Nine Regram icons, a compact chat list, and adjustable bottom bar items and width.
- **Settings and networking**: Settings search, backup and restore by category, DNS and proxy policies, and connection diagnostics.
- **Show Off**: Local Premium appearance, phone number, rating, Stars, TON, and gift displays.

“Show Off” only affects on-device display and local simulation records. It does not change Telegram's server-side Premium benefits, real balances, or gift ownership. External translation, LLM, and speech services use the configuration for your selected provider.

## Downloads and updates

Regram 13.1.0 (283382) requires macOS 12.0 or later and provides separate packages:

| Mac | Package |
| --- | --- |
| Apple Silicon (M series) | [arm64 DMG](https://github.com/RegramDev/Regram-macos/releases/download/v13.1.0-283382/Regram-13.1.0-283382-arm64.dmg) |
| Intel | [x86_64 DMG](https://github.com/RegramDev/Regram-macos/releases/download/v13.1.0-283382/Regram-13.1.0-283382-x86_64.dmg) |

Verify downloads with [SHA256SUMS.txt](https://github.com/RegramDev/Regram-macos/releases/download/v13.1.0-283382/SHA256SUMS.txt). See the [changelog](CHANGELOG.en.md) for additions and fixes.

This release is signed with an Apple/Mac Development certificate and has not been notarized by Apple. Open the downloaded DMG, drag Regram to Applications, and launch it from that folder.

If Gatekeeper blocks the first launch, first confirm that the download came from this repository's GitHub Releases and that you trust its source. On macOS 13 or later, use System Settings → Privacy & Security → Open Anyway. On macOS 12, use System Preferences → Security & Privacy → General → Open Anyway. Confirm opening the app when prompted. See [Apple's official instructions](https://support.apple.com/en-us/102445) and the [macOS Monterey guide](https://support.apple.com/en-gb/guide/mac-help/mh40616/12.0/mac/12.0).

Regram uses its own application identifier and local data directory, so it can be installed alongside Telegram. This build supports automatic checks, downloads, and installation on quit, configurable in Regram Pro; manual replacement remains available. Updates choose the matching architecture and verify the download digest and app signature. Normal updates retain your existing accounts and local data.

## Build from source

See [INSTALL.md](INSTALL.md) for the complete toolchain, submodule, and native dependency setup.

```sh
git clone https://github.com/RegramDev/Regram-macos.git
cd Regram-macos
cp Telegram-Mac/ApiCredentials.example.xcconfig Telegram-Mac/ApiCredentials.local.xcconfig
```

Enter your own `REGRAM_API_ID` and `REGRAM_API_HASH` in the local configuration file. After preparing the dependencies, use a fixed code-signing certificate to build and install the Release version:

```sh
python3 scripts/install-regram-release.py --identity YOUR_CERTIFICATE_SHA1
```

By default, the installer builds only for the current Mac’s architecture. It passes `STABLE` to Swift packages, validates the build, and installs it to `/Applications/Regram.app`. Future releases use separate Apple Silicon and Intel packages; see [packaging](INSTALL.md#separate-apple-silicon-and-intel-packages). For subsequent updates, omit `--identity` to keep using the same certificate. API credentials and local signing configuration are ignored by Git.

## Report an issue

Please report problems through this repository's [Issues](https://github.com/RegramDev/Regram-macos/issues), including your Regram version, macOS version, and steps to reproduce.

## Credits and license

Thanks to the contributors to [Telegram for macOS](https://github.com/TelegramMessenger/telegram-macos) and Regram for iOS. Attribution for Regram code and resources is documented in [Core](packages/RegramCore/ATTRIBUTION.md), [Services](packages/RegramServices/ATTRIBUTION.md), and [UI](packages/RegramUI/ATTRIBUTION.md).

This project uses the [GNU GPL v2](LICENSE) license. Derived builds should use their own API credentials, application name, icons, and signing configuration, and retain attribution and license notices for the original authors and third-party resources.
