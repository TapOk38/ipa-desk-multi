# Changelog

## 0.7.0-beta.4 — 2026-10-12

- Renamed the app to TapOk IPA Installer — Android; kept the existing package ID and signing identity.
- Allowed the heading to wrap on narrow screens.

## 0.7.0-beta.3 — 2026-10-12

- Added the approved launcher icon.
- Compile and package Android resources in manual builds; verify launcher resource references and APK alignment.

## 0.7.0-beta.2 — 2026-10-12

- Fixed the manual-build manifest order and enabled resizable windows to prevent legacy letterboxing.
- Handle system-bar insets explicitly and widen the language selector.
- Default to English while preserving saved Russian preferences.
- Verify SDK order and activity resizing in the packaged APK.

## 0.7.0-beta.1 — 2026-10-12

- Russian and English interfaces with an in-app language selector.
- Language preference persists between launches.
- Added Russian and English guides.
- Fixed APK packaging; builds now verify ZIP structure and entry checksums.

## 0.6.0-beta.1 — 2026-10-12

- First public beta based on prototype 0.6.
- Support for repeated empty directory entries in IPA files without repacking.
- Retained duplicate file, metadata CRC and path validation.
- Selecting an invalid IPA clears the previous selection.
- Added builds without signing keys in source, CI, licenses and documentation.
- Retained USB mux, plist and temporary file cleanup fixes from the prototypes.