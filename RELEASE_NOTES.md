# scrcpy macOS launcher 1.0.0

Unofficial launcher built from the official binaries in
[Genymobile/scrcpy 5.0.1](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1).
The upstream executable is re-signed ad hoc as part of the macOS bundle.
The upstream authors retain copyright; see [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).

- macOS Apple Silicon application with scrcpy 5.0.1 and adb from the official release.
- A single Dock icon while mirroring; reopen controls from the scrcpy application menu.
- Device wake and host-side numeric PIN entry for locked devices.
- Device-scoped Huawei secure keyboard toggle, audio and window settings.

Android secure lock screens cannot be displayed by scrcpy. PIN input is an attempt to unlock through an already authorized ADB connection; device-specific lock screens may reject it. The Huawei secure keyboard toggle does not bypass an app's `FLAG_SECURE` protection. The app is ad-hoc signed and not notarized.
