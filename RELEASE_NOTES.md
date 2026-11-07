# scrcpy macOS launcher 1.0.3

非官方修改版。投屏、设备控制与设备端服务主要来自
[Genymobile/scrcpy](https://github.com/Genymobile/scrcpy)，版权归 Genymobile、
Romain Vimont 和贡献者所有，依 Apache License 2.0 分发；adb 来自 Android Open
Source Project。本仓库提供独立的 macOS 启动器与集成功能，并未收录或修改 scrcpy
上游源码。完整来源见 [NOTICE.md](https://github.com/xpump/scrcpy-mac-launcher/blob/v1.0.3/NOTICE.md)。

Fixes a crash when reopening "连接与设置…" after closing the control window while mirroring.
Adds a selectable UHID keyboard mode for typing with the Android device's IME.
Adds experimental Mac IME text transfer through scrcpy's paste command using a private clipboard. The bridge has passed automated tests, but text entry on a physical device has not yet been verified; fields that block pasting may reject it.

Unofficial launcher built from the official binaries in
[Genymobile/scrcpy 5.0.1](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1).
The upstream executable is re-signed ad hoc as part of the macOS bundle.
The upstream authors retain copyright; see [NOTICE.md](https://github.com/xpump/scrcpy-mac-launcher/blob/v1.0.3/NOTICE.md) and [LICENSE](https://github.com/xpump/scrcpy-mac-launcher/blob/v1.0.3/LICENSE).

- macOS Apple Silicon application with scrcpy 5.0.1 and adb from the official release.
- A single Dock icon while mirroring; reopen controls from the scrcpy application menu.
- Device wake and host-side numeric PIN entry for locked devices.
- Device-scoped Huawei secure keyboard toggle, audio and window settings.

Android secure lock screens cannot be displayed by scrcpy. PIN input is an attempt to unlock through an already authorized ADB connection; device-specific lock screens may reject it. The Huawei secure keyboard toggle does not bypass an app's `FLAG_SECURE` protection. The app is ad-hoc signed and not notarized.
