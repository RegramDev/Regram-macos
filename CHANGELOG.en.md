# Changelog

[简体中文](CHANGELOG.md) · **English**

## 13.1.0 (283377) — 2026-10-27

### Interface and navigation

- Keep the official native bottom bar and item order, with optional contact visibility. Regram Pro and General settings share the call panel switch.
- Adjust bottom bar width from 50% to 100% and optionally show labels. Labels increase the bar height; disabling them restores the original height.
- Apply bottom bar switches when released, without waiting for the animation to finish. Avoid repeated chat and settings refreshes for navigation changes.
- Correct list backgrounds in the Regram Paper and Graphite palettes to restore rounded settings groups and remove extra separators. Reimport the updated palette to apply the fix to an existing theme.
- Remove the separate swipe-to-delete setting; chat list swipes use the shared swipe mode.
- Remove the macOS media loading experiment, restore upstream media fetching and playback, and ignore its legacy backup setting.

### Upstream sync

- Merge nine upstream commits through `e1883098`.
- Improve chat search result corners, message menu performance, and message search by author.
- Include author, time, and reply context when copying messages; add password visibility to two-step verification login.
- Correct wallet gift drop positions and text layering, and unify gift tile corner radii.

## 13.1.0 (283374) — 2026-10-27

### Added and improved

- Separate Apple Silicon and Intel packages, with matching architecture throughout each app and its embedded components.
- Automatic update checks, downloads, and installation on quit, with download digest and signing identity validation.
- Message bookmarks on the main Settings page, with an enable switch that preserves saved bookmarks and tags when disabled.
- Native Regram Pro, bookmark, and author-message screens, with complete sidebar selection corners and corrected search state after returning.
- Faster filtered previews, unread synchronization, and folder switching through fewer repeated queries, text expansions, and rule matches.
- Avoid unnecessary interface-wide refreshes when returning to the app without a font configuration change.
- Image translation follows the selected service and Chinese language variant, with stable region mapping and clear size-limit feedback.
- Merge 15 upstream updates covering Liquid Glass controls, shared media, photo editing, batch photo saving, and message reactions.

### Fixed and changed

- Fix input crashes and profile navigation for mentions; pasted images default to photos.
- Fix network policy saving and reconnection, data center result display and copying, and configuration diagnostics.
- Accept complete request paths in model base URLs and fill in the provider path when omitted.
- Fix image translation loading states, misplaced regions, shrinking layers, and stale results after switching images.
- Adjust profile data center, Peer ID, registration estimate, and local gift display.
- Remove message summaries and message screenshot export.

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
