# Origin and third-party notices

This repository is an unofficial macOS launcher built around
[Genymobile/scrcpy](https://github.com/Genymobile/scrcpy). It is not an official
scrcpy release or endorsed by its maintainers. Most mirroring and device-control
functionality in the packaged app is upstream scrcpy work, not original work of
this repository.

The application bundle contains scrcpy 5.0.1, scrcpy-server, adb, and icons from
the [official macOS arm64 release](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1).
The build script verifies the upstream archive SHA-256 before packaging. The
upstream scrcpy source code is neither vendored nor modified here; its
executable is re-signed ad hoc when the macOS application bundle is signed.
scrcpy is Copyright (C)
2018 Genymobile and Copyright (C) 2018-2026 Romain Vimont and contributors,
licensed under Apache License 2.0. adb is part of the
[Android Open Source Project](https://android.googlesource.com/platform/packages/modules/adb/),
also distributed under Apache License 2.0. The upstream license and manual are
included in `Scrcpy.app/Contents/Resources/docs/`.

`ScrcpyLauncher.swift`, `Info.plist`, and an initial `build-app.sh` were present
in the local macOS launcher directory supplied for this project. They are not
part of the official scrcpy release archive. No separate author notice or
public repository was identified for those launcher files. The changes in this
repository add device wake and host-side numeric PIN input, application-menu
controls, Dock behavior, Mac IME integration, packaging, and release automation. The launcher code
is distributed under the repository's Apache License 2.0; upstream copyright
notices are retained. No ownership of the upstream scrcpy project is claimed.

`MirrorMenuBridge.m` is a separate integration component built into this
launcher. It enables a Settings command in scrcpy's macOS app menu, sends a
local notification to show the launcher controls, and relays committed Mac IME
text through scrcpy's paste shortcut. It does not alter the upstream scrcpy
binary on disk.
