<div align="center">
  <img src="Telegram-Mac/Regram.icon/Assets/Regram.png" alt="Regram" width="120" height="120">
  <h1>Regram for macOS</h1>
  <p>Based on Telegram's native macOS client, with more flexible messaging, translation, and appearance settings.</p>
  <p>
    <a href="README.md">简体中文</a> · <strong>English</strong>
  </p>
  <p>
    <a href="https://github.com/RegramDev/Regram-macos/releases">Download</a> ·
    <a href="CHANGELOG.en.md">Changelog</a> ·
    <a href="INSTALL.md">Build instructions</a> ·
    <a href="https://github.com/RegramDev/Regram-macos/issues">Report an issue</a>
  </p>
</div>

Regram is an unofficial client based on [Telegram for macOS](https://github.com/TelegramMessenger/telegram-macos). It uses the native Swift and AppKit interface and is maintained independently by Regram.

## Features

- **Messages and history**: Customizable message menus, resending and forwarding without attribution, bookmarks, tags, group aliases, and message searches by author or across shared groups.
- **Translation and summaries**: Choose a translation engine for individual messages, entire chats, outgoing messages, and web pages; use custom LLM translation, summaries, and speech transcription.
- **Privacy and filtering**: Keyword and regular expression filters, hidden users, filter rule imports, and local records of deleted and edited messages.
- **Images and media**: Copy original images, paste high-quality images, inspect media information, and configure link previews.
- **Appearance and navigation**: Custom fonts, nine Regram icons, a compact chat list, and adjustable bottom bar items and width.
- **Settings and networking**: Settings search, backup and restore by category, DNS and proxy policies, and connection diagnostics.
- **Show Off**: Local Premium appearance, phone number, rating, Stars, TON, and gift displays.

“Show Off” only affects on-device display and local simulation records. It does not change Telegram's server-side Premium benefits, real balances, or gift ownership. External translation, LLM, and speech services use the configuration for your selected provider.

## Downloads and updates

Release builds will be published through this repository's [GitHub Releases](https://github.com/RegramDev/Regram-macos/releases). The first public Regram release has not been published yet. See the [changelog](CHANGELOG.en.md) for upcoming additions and fixes.

Regram uses its own application identifier and local data directory, so it can be installed alongside Telegram. To update, download a new build and replace the application manually. Normal updates retain your existing accounts and local data.

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

The installer passes `STABLE` to Swift packages, validates the build, and installs it to `/Applications/Regram.app`. For subsequent updates, omit `--identity` to keep using the same certificate. API credentials and local signing configuration are ignored by Git.

## Report an issue

Please report problems through this repository's [Issues](https://github.com/RegramDev/Regram-macos/issues), including your Regram version, macOS version, and steps to reproduce.

## Credits and license

Thanks to the contributors to [Telegram for macOS](https://github.com/TelegramMessenger/telegram-macos) and Regram for iOS. Attribution for Regram code and resources is documented in [Core](packages/RegramCore/ATTRIBUTION.md), [Services](packages/RegramServices/ATTRIBUTION.md), and [UI](packages/RegramUI/ATTRIBUTION.md).

This project uses the [GNU GPL v2](LICENSE) license. Derived builds should use their own API credentials, application name, icons, and signing configuration, and retain attribution and license notices for the original authors and third-party resources.
