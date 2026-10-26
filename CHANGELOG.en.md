# Changelog

[简体中文](CHANGELOG.md) · **English**

## 13.1.0 (283368) — 2026-10-26

### Added

- Regram Pro settings, settings search, and English, Simplified Chinese, and Traditional Chinese interfaces.
- Settings backup and restore by category.
- Message bookmarks, tags, group aliases, recent chats, and message searches by author within a group or across shared groups.
- Customizable message menus, resending and forwarding without attribution, selecting messages by sender, and message screenshots.
- Keyword and regular expression filters, hidden users, and filter rule import previews and merging.
- Optional local records of deleted messages, edit history, and per-chat retention settings.
- Translation engine selection, quick translation, translation before sending, web page translation, custom LLMs, and message summaries.
- A speech transcription task list with cancel and retry actions.
- Custom fonts, nine Regram application icons, a compact chat list, and bottom bar width adjustments.
- Media information, link preview settings, DNS and proxy policies, and network diagnostics.
- Local Premium, phone number, rating, Stars, TON, and gift displays in “Show Off.”
- Invite link QR codes from upstream.

### Improved

- Preserve original image data when copying and send pasted images at the highest photo encoding quality.
- Show Regram icons in the native icon picker, with a direct link from appearance settings.
- Use the native standard and collectible gift interfaces for local gift details.
- Adjust the layout of settings groups, input rows, and selection controls.
- Reduce unnecessary refreshes and flickering in pinned message and translation bars.
- Simplify bottom bar settings to contact and call visibility and manual width adjustment.
- Standardize send-key labels as “Return” and support Command + Enter for line breaks.
- Store Regram data and Keychain items separately, and retain logins across updates signed with the same identity.

- Improve update signing by signing the app and embedded components individually with the same certificate, preserving each target's existing entitlements, signing flags, and runtime settings.

### Fixed

- Fix synchronous translation segments sometimes cancelling subsequent asynchronous requests.
- Fix a crash that could occur when opening some videos before the player had finished loading.
- Fix progressive JPEG previews showing a mix of sharp and blurred areas.
- Fix returning from Regram Pro jumping to the initial settings page and losing its selection highlight.
- Fix compact chat list settings not taking effect immediately and misplaced Premium badges.
- Fix unread badges in some folders and custom font settings not taking effect.
- Fix newly sent message bubbles being clipped during the send animation.
- Fix native locations such as “My Stars” not reflecting local display settings.
