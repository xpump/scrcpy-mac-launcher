# scrcpy macOS 启动器

非官方 Apple Silicon 版 [scrcpy 5.0.1](https://github.com/Genymobile/scrcpy) 启动器。可发现已授权的 Android USB 调试设备，并在 macOS 窗口中管理镜像、声音、唤醒、数字 PIN 解锁和华为安全键盘设置。

## 使用

1. 在设备上开启 USB 调试并授权这台 Mac，然后打开 `Scrcpy.app`。
2. 选择设备并开始镜像。启动器控制窗口会收起；Dock 中只保留 scrcpy 镜像图标。
3. 点击镜像窗口右上角的齿轮，重新打开连接与设置窗口。设备行的锁图标可唤醒设备并输入数字 PIN。

系统锁屏窗口在 Android 12 及更新版本中可能带有安全标记，因此真实锁屏画面无法被 scrcpy 捕获。电脑端的 PIN 输入框可以尝试完成解锁，但不会显示受保护的锁屏画面；若设备拒绝 ADB 键盘事件或要求额外验证，请在设备上完成解锁。PIN 按单个按键事件发送，不写入应用设置或运行日志。

“密码输入时尝试保持画面”会关闭当前设备的华为安全键盘，直到再次关闭该选项；这会降低设备的密码输入保护，也无法解除应用自身的 `FLAG_SECURE` 限制。参见 [scrcpy 锁屏限制讨论](https://github.com/Genymobile/scrcpy/issues/3413)。

## 构建

需要 macOS 13 或更新版本、Apple Silicon 和 Xcode Command Line Tools：

```sh
zsh build-app.sh
```

脚本会下载 scrcpy 官方 macOS arm64 发行包，校验 SHA-256 后构建。若已有该发行包，可设置 `SCRCPY_ARCHIVE=/absolute/path/to/scrcpy-macos-aarch64-v5.0.1.tar.gz`。输出为 `dist/Scrcpy.app` 和 `dist/ScrcpyLauncher-macos-arm64-v1.0.0.zip`；ZIP 是 GitHub Release 安装包，本项目不生成 Android APK。

应用采用本地 ad-hoc 签名，尚未经过 Apple 公证。首次运行可能需要在 Finder 中右键选择“打开”。上游组件及许可证见 [NOTICE.md](NOTICE.md)。

## English

Unofficial Apple Silicon launcher for scrcpy 5.0.1. It provides one Dock icon while mirroring, a corner control button, device wake, and a host-side numeric PIN entry. Android secure lock screens remain uncapturable. Run `zsh build-app.sh` to produce the macOS app and release ZIP; see [RELEASE_NOTES.md](RELEASE_NOTES.md) for limitations.
