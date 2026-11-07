# scrcpy macOS 启动器

非官方 Apple Silicon 版 [scrcpy 5.0.1](https://github.com/Genymobile/scrcpy) 启动器。本程序的投屏和设备控制核心来自他人的开源项目 scrcpy，并非本仓库原创；本仓库主要提供 macOS 启动器与集成功能。可发现已授权的 Android USB 调试设备，并在 macOS 窗口中管理镜像、声音、唤醒、数字 PIN 解锁和华为安全键盘设置。

## 来源与版权

屏幕镜像、键鼠控制和设备端服务来自 [Genymobile/scrcpy](https://github.com/Genymobile/scrcpy)，版权归 Genymobile、Romain Vimont 及相应贡献者所有，按 Apache License 2.0 发布。本仓库的构建脚本从该项目的 v5.0.1 Release 下载并校验 macOS arm64 发行包；仓库没有收录或修改 scrcpy、scrcpy-server 的上游源码。Release 安装包会包含这些上游二进制、图标和许可证。随包提供的 adb 属于 Android Open Source Project。

本仓库发布的是**非官方 macOS 启动器**，并非 scrcpy 官方项目。`ScrcpyLauncher.swift` 和初版打包脚本来自用户提供的本地启动器目录，不在上述 scrcpy 官方发行包中；本次修改增加了唤醒与数字 PIN 输入、应用菜单中的设置入口、单一 Dock 图标及发布流程。原始启动器文件未标明独立作者或仓库，不能据此把其作者归为 scrcpy 维护者。完整的组件归属和许可证见 [NOTICE.md](NOTICE.md) 与 [LICENSE](LICENSE)。

## 使用

1. 在设备上开启 USB 调试并授权这台 Mac，然后打开 `Scrcpy.app`。
2. 选择设备并开始镜像。启动器控制窗口会收起；镜像进程是唯一占用 Dock 的 scrcpy 应用。
3. 在屏幕左上角的 scrcpy 菜单中选择“连接与设置…”，重新打开控制窗口。设备行的锁图标可唤醒设备并输入数字 PIN。

系统锁屏窗口在 Android 12 及更新版本中可能带有安全标记，因此真实锁屏画面无法被 scrcpy 捕获。电脑端的 PIN 输入框可以尝试完成解锁，但不会显示受保护的锁屏画面；若设备拒绝 ADB 键盘事件或要求额外验证，请在设备上完成解锁。PIN 按单个按键事件发送，不写入应用设置或运行日志。

“密码输入时尝试保持画面”会关闭当前设备的华为安全键盘，直到再次关闭该选项；这会降低设备的密码输入保护，也无法解除应用自身的 `FLAG_SECURE` 限制。参见 [scrcpy 锁屏限制讨论](https://github.com/Genymobile/scrcpy/issues/3413)。

“Mac 输入法”模式尝试将输入法已选定的中文文字经 scrcpy 的粘贴通道发送到手机，使用进程内专用剪贴板，不修改 Mac 系统剪贴板；文字仍会进入 Android 剪贴板。该模式已通过桥接测试，真实设备输入尚待验证，拒绝粘贴的输入框可能无法使用。“手机输入法”模式将 Mac 键盘作为实体键盘连接到 Android，使用手机端输入法处理中文；“兼容”模式保留 scrcpy 的 SDK 键盘行为。

## 构建

需要 macOS 13 或更新版本、Apple Silicon 和 Xcode Command Line Tools：

```sh
zsh build-app.sh
```

脚本会下载 scrcpy 官方 macOS arm64 发行包，校验 SHA-256 后构建。若已有该发行包，可设置 `SCRCPY_ARCHIVE=/absolute/path/to/scrcpy-macos-aarch64-v5.0.1.tar.gz`。输出为 `dist/Scrcpy.app` 和 `dist/ScrcpyLauncher-macos-arm64-v1.0.3.zip`；ZIP 是 GitHub Release 安装包，本项目不生成 Android APK。

应用采用本地 ad-hoc 签名，尚未经过 Apple 公证。首次运行可能需要在 Finder 中右键选择“打开”。上游组件及许可证见 [NOTICE.md](NOTICE.md)。

## English

Unofficial Apple Silicon launcher built around Genymobile/scrcpy 5.0.1. Mirroring, device control, and server functionality come from the upstream project and remain its authors' work. This repository contains a separate Swift launcher derived from the supplied local launcher files; it does not include or modify scrcpy's upstream source. See [NOTICE.md](NOTICE.md) for attribution and [RELEASE_NOTES.md](RELEASE_NOTES.md) for limitations.
