// SPDX-License-Identifier: Apache-2.0
// Upstream scrcpy attribution and launcher provenance: NOTICE.md.
import AppKit
import Foundation

private struct AndroidDevice {
    let serial: String
    let state: String
    let model: String?

    var isReady: Bool { state == "device" }

    var label: String {
        let name = model?.replacingOccurrences(of: "_", with: " ") ?? serial
        return isReady ? "\(name) (\(serial))" : "\(name) (\(serial) · \(state))"
    }
}

private struct LaunchOptions {
    let audioLocation: String
    let stayAwake: Bool
    let screenOff: Bool
    let alwaysOnTop: Bool

    static func load() -> LaunchOptions {
        let defaults = UserDefaults.standard
        return LaunchOptions(audioLocation: defaults.string(forKey: "audioLocation") ?? "computer",
                             stayAwake: defaults.bool(forKey: "stayAwake"),
                             screenOff: defaults.bool(forKey: "screenOff"),
                             alwaysOnTop: defaults.bool(forKey: "alwaysOnTop"))
    }

    var arguments: [String] {
        var args = audioLocation == "phone" ? ["--no-audio"] : ["--audio-source=output"]
        if stayAwake { args.append("--stay-awake") }
        if screenOff { args.append("--turn-screen-off") }
        if alwaysOnTop { args.append("--always-on-top") }
        return args
    }
}

private enum UnlockOutcome {
    case unlocked
    case stillLocked
    case alreadyUnlocked
}

private final class ScrcpyModel {
    var onChange: (() -> Void)?
    private(set) var devices: [AndroidDevice] = []
    private(set) var selectedSerial = ""
    private(set) var isScanning = false
    private(set) var isMirroring = false
    private(set) var status = "正在查找设备…"
    private(set) var logText = ""

    private var mirrorProcess: Process?
    private var activeSerial = ""
    private var pendingRestart: (serial: String, options: LaunchOptions)?
    private var stopRequested = false

    var selectedDevice: AndroidDevice? {
        devices.first { $0.serial == selectedSerial }
    }

    var currentSerial: String? {
        if isMirroring { return activeSerial }
        return selectedDevice?.isReady == true ? selectedSerial : nil
    }

    func selectDevice(_ serial: String) {
        selectedSerial = serial
        if !isMirroring { updateReadyStatus() }
        onChange?()
    }

    func refreshDevices() {
        guard !isScanning else { return }
        isScanning = true
        onChange?()

        let adb = bundledURL("adb")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = adb
            process.arguments = ["devices", "-l"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let result = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async { [weak self] in
                    self?.finishDeviceScan(result, exitCode: process.terminationStatus)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isScanning = false
                    self.devices = []
                    self.selectedSerial = ""
                    self.status = "无法启动 adb：\(error.localizedDescription)"
                    self.onChange?()
                }
            }
        }
    }

    private func finishDeviceScan(_ output: String, exitCode: Int32) {
        isScanning = false
        guard exitCode == 0 else {
            devices = []
            selectedSerial = ""
            status = "adb 无法获取设备，请查看运行日志"
            appendLog(output)
            onChange?()
            return
        }

        var found: [AndroidDevice] = []
        var inDeviceList = false
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("List of devices attached") {
                inDeviceList = true
                continue
            }
            guard inDeviceList else { continue }
            let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard fields.count >= 2 else { continue }
            let model = fields.first(where: { $0.hasPrefix("model:") })?.dropFirst("model:".count)
            found.append(AndroidDevice(serial: fields[0], state: fields[1], model: model.map(String.init)))
        }

        devices = found
        if !found.contains(where: { $0.serial == selectedSerial }) {
            selectedSerial = found.first(where: \.isReady)?.serial ?? found.first?.serial ?? ""
        }
        if !isMirroring { updateReadyStatus() }
        onChange?()
    }

    private func updateReadyStatus() {
        if devices.isEmpty {
            status = "未发现设备，请连接手机并允许 USB 调试"
        } else if selectedDevice?.state == "unauthorized" {
            status = "请在手机上允许 USB 调试"
        } else if selectedDevice?.state == "offline" {
            status = "设备离线，请重新连接手机"
        } else {
            status = "设备已就绪"
        }
    }

    func start() {
        guard !isMirroring, let device = selectedDevice, device.isReady else { return }
        launch(serial: device.serial, options: LaunchOptions.load())
    }

    private func launch(serial: String, options: LaunchOptions) {
        let process = Process()
        process.executableURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ScrcpyMirror.app/Contents/MacOS/scrcpy")
        process.arguments = ["--serial=\(serial)"] + options.arguments
        process.currentDirectoryURL = Bundle.main.resourceURL
        var environment = ProcessInfo.processInfo.environment
        environment["ADB"] = bundledURL("adb").path
        environment["SCRCPY_SERVER_PATH"] = bundledURL("scrcpy-server").path
        environment["SCRCPY_ICON_DIR"] = Bundle.main.resourceURL!.appendingPathComponent("icons").path
        environment["DYLD_INSERT_LIBRARIES"] = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ScrcpyMirror.app/Contents/Frameworks/MirrorMenuBridge.dylib").path
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { [weak self] in self?.appendLog(text) }
        }
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async { [weak self] in self?.processExited(finished) }
        }

        logText = ""
        stopRequested = false
        status = "正在连接 \(serial)…"
        do {
            try process.run()
            mirrorProcess = process
            activeSerial = serial
            isMirroring = true
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            status = "无法启动 scrcpy：\(error.localizedDescription)"
        }
        onChange?()
    }

    func settingsChanged() {
        guard let process = mirrorProcess else { return }
        pendingRestart = (activeSerial, LaunchOptions.load())
        status = "正在应用设置…"
        if process.isRunning { process.terminate() }
        onChange?()
    }

    func stop() {
        guard let process = mirrorProcess else { return }
        pendingRestart = nil
        stopRequested = true
        status = "正在停止镜像…"
        if process.isRunning { process.terminate() }
        onChange?()
    }

    func wakeDevice(serial: String, completion: @escaping (Result<Void, Error>) -> Void) {
        runADB(serial: serial, arguments: ["shell", "input", "keyevent", "KEYCODE_WAKEUP"]) { result in
            completion(result.map { _ in () })
        }
    }

    func unlockWithPIN(serial: String, pin: String,
                       completion: @escaping (Result<UnlockOutcome, Error>) -> Void) {
        guard !pin.isEmpty, pin.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            completion(.failure(settingError("请输入数字 PIN")))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result: Result<UnlockOutcome, Error>
            do {
                let trust = try self.executeADB(serial: serial, arguments: ["shell", "dumpsys", "trust"]).get()
                guard let locked = Self.isDeviceLocked(trust) else {
                    throw self.settingError("无法确认手机是否锁定，未发送 PIN")
                }
                if !locked {
                    result = .success(.alreadyUnlocked)
                } else {
                    _ = try self.executeADB(serial: serial,
                                            arguments: ["shell", "input", "keyevent", "KEYCODE_WAKEUP"]).get()
                    _ = try self.executeADB(serial: serial,
                                            arguments: ["shell", "input", "keyevent", "KEYCODE_MENU"]).get()
                    for digit in pin {
                        _ = try self.executeADB(serial: serial,
                                                arguments: ["shell", "input", "keyevent", "KEYCODE_\(digit)"]).get()
                    }
                    _ = try self.executeADB(serial: serial,
                                            arguments: ["shell", "input", "keyevent", "KEYCODE_ENTER"]).get()
                    Thread.sleep(forTimeInterval: 1.0)
                    let updated = try self.executeADB(serial: serial,
                                                      arguments: ["shell", "dumpsys", "trust"]).get()
                    guard let stillLocked = Self.isDeviceLocked(updated) else {
                        throw self.settingError("已发送 PIN，但无法确认解锁结果")
                    }
                    result = .success(stillLocked ? .stillLocked : .unlocked)
                }
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func isDeviceLocked(_ trust: String) -> Bool? {
        let lines = trust.components(separatedBy: .newlines)
        guard let line = lines.first(where: { $0.contains("(current):") && $0.contains("deviceLocked=") }) else {
            return nil
        }
        if line.contains("deviceLocked=1") || line.contains("deviceLocked=true") { return true }
        if line.contains("deviceLocked=0") || line.contains("deviceLocked=false") { return false }
        return nil
    }

    func readSecureKeyboard(serial: String, completion: @escaping (Result<Bool?, Error>) -> Void) {
        runADB(serial: serial, arguments: ["shell", "settings", "get", "secure", "secure_keyboard"]) { result in
            switch result {
            case .success(let output):
                switch output.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "0": completion(.success(true))
                case "1": completion(.success(false))
                case "null": completion(.success(nil))
                default:
                    completion(.failure(NSError(domain: "ScrcpyLauncher", code: 1,
                                                userInfo: [NSLocalizedDescriptionKey: "无法识别手机的安全键盘状态"])))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func setSecureKeyboard(serial: String, showPasswordScreen: Bool,
                           completion: @escaping (Result<Void, Error>) -> Void) {
        let value = showPasswordScreen ? "0" : "1"
        runADB(serial: serial, arguments: ["shell", "settings", "put", "secure", "secure_keyboard", value]) {
            [weak self] result in
            switch result {
            case .success:
                self?.readSecureKeyboard(serial: serial) { state in
                    switch state {
                    case .success(let actual) where actual == showPasswordScreen:
                        completion(.success(()))
                    case .success:
                        completion(.failure(NSError(domain: "ScrcpyLauncher", code: 2,
                                                    userInfo: [NSLocalizedDescriptionKey: "手机未保存该设置"])))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func runADB(serial: String, arguments: [String],
                        completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.executeADB(serial: serial, arguments: arguments)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func executeADB(serial: String, arguments: [String]) -> Result<String, Error> {
        let process = Process()
        process.executableURL = bundledURL("adb")
        process.arguments = ["-s", serial] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus == 0 { return .success(message) }
            return .failure(settingError(message.isEmpty ? "adb 无法连接设备" : message))
        } catch {
            return .failure(error)
        }
    }

    private func settingError(_ message: String) -> NSError {
        NSError(domain: "ScrcpyLauncher", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func processExited(_ process: Process) {
        guard mirrorProcess === process else { return }
        mirrorProcess = nil
        isMirroring = false
        if let restart = pendingRestart {
            pendingRestart = nil
            launch(serial: restart.serial, options: restart.options)
        } else if stopRequested || process.terminationStatus == 0 {
            status = "镜像已结束"
        } else {
            status = "连接中断或启动失败，请查看运行日志"
        }
        stopRequested = false
        onChange?()
    }

    private func appendLog(_ text: String) {
        logText = String((logText + text).suffix(16_000))
        if isMirroring && status.hasPrefix("正在连接") &&
            logText.contains("[server] INFO: Device:") {
            status = "正在投屏 \(activeSerial)"
        }
        onChange?()
    }

    private func bundledURL(_ name: String) -> URL {
        Bundle.main.resourceURL!.appendingPathComponent("bin").appendingPathComponent(name)
    }
}

private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.maximumNumberOfLines = 0
    return field
}

private func iconButton(_ symbol: String, tooltip: String, target: AnyObject,
                        action: Selector) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)!,
                          target: target, action: action)
    button.isBordered = false
    button.toolTip = tooltip
    button.imageScaling = .scaleProportionallyDown
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 30),
        button.heightAnchor.constraint(equalToConstant: 30)
    ])
    return button
}

private final class SettingsController: NSViewController {
    private let model: ScrcpyModel
    private let serial: String?
    private let onChange: () -> Void
    private let audioControl = NSSegmentedControl(labels: ["电脑", "手机"],
                                                  trackingMode: .selectOne, target: nil, action: nil)
    private let audioDescription = label("", size: 11, color: .secondaryLabelColor)
    private let stayAwake = NSButton(checkboxWithTitle: "连接时保持唤醒", target: nil, action: nil)
    private let screenOff = NSButton(checkboxWithTitle: "镜像时关闭手机屏幕", target: nil, action: nil)
    private let alwaysOnTop = NSButton(checkboxWithTitle: "镜像窗口置顶", target: nil, action: nil)
    private let showPasswordScreen = NSButton(checkboxWithTitle: "密码输入时尝试保持画面", target: nil, action: nil)
    private let secureKeyboardDescription = label(
        "会持续关闭当前设备的华为安全键盘，降低密码输入保护；受保护的应用仍可能黑屏。",
        size: 11, color: .secondaryLabelColor)
    private let secureKeyboardStatus = label("", size: 11, color: .secondaryLabelColor)
    private var savedPasswordScreenState = false

    init(model: ScrcpyModel, serial: String?, onChange: @escaping () -> Void) {
        self.model = model
        self.serial = serial
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let defaults = UserDefaults.standard
        let audioLocation = defaults.string(forKey: "audioLocation") ?? "computer"
        audioControl.selectedSegment = audioLocation == "phone" ? 1 : 0
        audioControl.target = self
        audioControl.action = #selector(settingChanged)
        stayAwake.state = defaults.bool(forKey: "stayAwake") ? .on : .off
        screenOff.state = defaults.bool(forKey: "screenOff") ? .on : .off
        alwaysOnTop.state = defaults.bool(forKey: "alwaysOnTop") ? .on : .off
        for checkbox in [stayAwake, screenOff, alwaysOnTop] {
            checkbox.target = self
            checkbox.action = #selector(settingChanged)
        }
        showPasswordScreen.isEnabled = false
        showPasswordScreen.target = self
        showPasswordScreen.action = #selector(secureKeyboardChanged)
        updateAudioDescription()

        let separator = NSBox()
        separator.boxType = .separator
        let secureSeparator = NSBox()
        secureSeparator.boxType = .separator
        let stack = NSStackView(views: [
            label("设置", size: 15, weight: .semibold),
            label("声音播放位置", size: 13, weight: .medium),
            audioControl,
            audioDescription,
            separator,
            stayAwake,
            screenOff,
            alwaysOnTop,
            secureSeparator,
            showPasswordScreen,
            secureKeyboardDescription,
            secureKeyboardStatus,
            label("更改声音或镜像选项后会重新连接当前镜像。", size: 11, color: .secondaryLabelColor)
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            audioControl.widthAnchor.constraint(equalTo: stack.widthAnchor),
            audioDescription.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            secureSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secureSeparator.heightAnchor.constraint(equalToConstant: 1),
            secureKeyboardDescription.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secureKeyboardStatus.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        view = root
        preferredContentSize = NSSize(width: 330, height: 400)
        loadSecureKeyboard()
    }

    @objc private func settingChanged() {
        let defaults = UserDefaults.standard
        defaults.set(audioControl.selectedSegment == 1 ? "phone" : "computer", forKey: "audioLocation")
        defaults.set(stayAwake.state == .on, forKey: "stayAwake")
        defaults.set(screenOff.state == .on, forKey: "screenOff")
        defaults.set(alwaysOnTop.state == .on, forKey: "alwaysOnTop")
        updateAudioDescription()
        onChange()
    }

    private func loadSecureKeyboard() {
        guard let serial else {
            secureKeyboardStatus.stringValue = "连接设备后可用。"
            return
        }
        secureKeyboardStatus.stringValue = "正在读取手机设置…"
        model.readSecureKeyboard(serial: serial) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let state?):
                self.savedPasswordScreenState = state
                self.showPasswordScreen.state = state ? .on : .off
                self.showPasswordScreen.isEnabled = true
                self.secureKeyboardStatus.stringValue = state
                    ? "当前设备的安全键盘已关闭。" : "当前设备的安全键盘已开启。"
            case .success(nil):
                self.secureKeyboardStatus.stringValue = "当前设备没有可用的安全键盘开关。"
            case .failure(let error):
                self.secureKeyboardStatus.stringValue = "读取失败：\(error.localizedDescription)"
            }
        }
    }

    @objc private func secureKeyboardChanged() {
        guard let serial else { return }
        let requestedState = showPasswordScreen.state == .on
        showPasswordScreen.isEnabled = false
        secureKeyboardStatus.stringValue = "正在更新手机设置…"
        model.setSecureKeyboard(serial: serial, showPasswordScreen: requestedState) { [weak self] result in
            guard let self else { return }
            self.showPasswordScreen.isEnabled = true
            switch result {
            case .success:
                self.savedPasswordScreenState = requestedState
                self.secureKeyboardStatus.stringValue = requestedState
                    ? "当前设备的安全键盘已关闭。" : "当前设备的安全键盘已开启。"
            case .failure(let error):
                self.showPasswordScreen.state = self.savedPasswordScreenState ? .on : .off
                self.secureKeyboardStatus.stringValue = "设置失败：\(error.localizedDescription)"
            }
        }
    }

    private func updateAudioDescription() {
        audioDescription.stringValue = audioControl.selectedSegment == 1
            ? "声音留在手机，不转发到电脑。" : "手机音频转发到电脑播放。"
    }
}

private final class UnlockController: NSViewController {
    private let model: ScrcpyModel
    private let serial: String?
    private let pinField = NSSecureTextField()
    private let statusLabel = label("", size: 11, color: .secondaryLabelColor)
    private let wakeButton = NSButton(title: "唤醒设备", target: nil, action: nil)
    private let unlockButton = NSButton(title: "输入 PIN 并解锁", target: nil, action: nil)

    init(model: ScrcpyModel, serial: String?) {
        self.model = model
        self.serial = serial
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() {
        let root = NSView()
        pinField.placeholderString = "设备锁屏 PIN"
        pinField.target = self
        pinField.action = #selector(unlock)
        wakeButton.target = self
        wakeButton.action = #selector(wake)
        unlockButton.target = self
        unlockButton.action = #selector(unlock)
        wakeButton.isEnabled = serial != nil
        unlockButton.isEnabled = serial != nil
        statusLabel.stringValue = serial == nil ? "连接设备后可用。" : ""

        let actions = NSStackView(views: [wakeButton, unlockButton])
        actions.orientation = .horizontal
        actions.spacing = 8
        let stack = NSStackView(views: [
            label("唤醒与解锁", size: 15, weight: .semibold),
            pinField,
            actions,
            statusLabel,
            label("系统锁屏画面受 Android 保护，无法显示在镜像中。PIN 不会保存到应用设置或日志。",
                  size: 11, color: .secondaryLabelColor)
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            pinField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            unlockButton.widthAnchor.constraint(greaterThanOrEqualTo: wakeButton.widthAnchor)
        ])
        view = root
        preferredContentSize = NSSize(width: 330, height: 205)
    }

    @objc private func wake() {
        guard let serial else { return }
        wakeButton.isEnabled = false
        statusLabel.stringValue = "正在唤醒设备…"
        model.wakeDevice(serial: serial) { [weak self] result in
            guard let self else { return }
            self.wakeButton.isEnabled = true
            switch result {
            case .success: self.statusLabel.stringValue = "已发送唤醒指令。"
            case .failure(let error): self.statusLabel.stringValue = "唤醒失败：\(error.localizedDescription)"
            }
        }
    }

    @objc private func unlock() {
        guard let serial else { return }
        let pin = pinField.stringValue
        pinField.stringValue = ""
        guard !pin.isEmpty, pin.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            statusLabel.stringValue = "请输入数字 PIN。"
            return
        }
        unlockButton.isEnabled = false
        statusLabel.stringValue = "正在尝试解锁…"
        model.unlockWithPIN(serial: serial, pin: pin) { [weak self] result in
            guard let self else { return }
            self.unlockButton.isEnabled = true
            switch result {
            case .success(.unlocked): self.statusLabel.stringValue = "设备已解锁。"
            case .success(.stillLocked): self.statusLabel.stringValue = "设备仍处于锁定状态，请核对 PIN。"
            case .success(.alreadyUnlocked): self.statusLabel.stringValue = "设备已解锁，未发送 PIN。"
            case .failure(let error): self.statusLabel.stringValue = "解锁失败：\(error.localizedDescription)"
            }
        }
    }
}

private final class HelpController: NSViewController {
    override func loadView() {
        let root = NSView()
        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: [
            label("连接说明", size: 15, weight: .semibold),
            label("1. 在手机的开发者选项中开启 USB 调试。"),
            label("2. 连接 USB 线，并在手机上允许这台电脑进行调试。"),
            label("3. 选择设备，点击“开始镜像”。"),
            separator,
            label("电脑播放手机声音需要 Android 11 或更新版本；部分应用可能禁止音频采集。",
                  size: 12, color: .secondaryLabelColor)
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
        view = root
        preferredContentSize = NSSize(width: 330, height: 230)
    }
}

private final class LauncherApp: NSObject, NSApplicationDelegate {
    private let model = ScrcpyModel()
    private var window: NSWindow!
    private var devicePicker: NSPopUpButton!
    private var refreshButton: NSButton!
    private var unlockButton: NSButton!
    private var statusLabel: NSTextField!
    private var statusDot: NSView!
    private var mirrorButton: NSButton!
    private var logButton: NSButton!
    private var logWindow: NSWindow?
    private var logView: NSTextView?
    private var settingsPopover: NSPopover?
    private var unlockPopover: NSPopover?
    private var helpPopover: NSPopover?
    private var renderedDeviceList = ""
    private var deviceTimer: Timer?
    private var wasMirroring = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeMenu()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showControlsFromMirror(_:)),
            name: Notification.Name("org.scrcpy.desktop-launcher.showControls"), object: nil)
        makeWindow()
        model.onChange = { [weak self] in self?.render() }
        render()
        model.refreshDevices()
        deviceTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self, !self.model.isMirroring else { return }
            self.model.refreshDevices()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !model.isMirroring
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showControls()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        deviceTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
        model.stop()
    }

    private func makeMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let controlsItem = appMenu.addItem(withTitle: "连接与设置…",
                                           action: #selector(showControlsFromMenu(_:)),
                                           keyEquivalent: ",")
        controlsItem.target = self
        let quitItem = appMenu.addItem(withTitle: "退出 scrcpy",
                                       action: #selector(NSApplication.terminate(_:)),
                                       keyEquivalent: "q")
        quitItem.target = NSApp
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 350),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "scrcpy"
        window.center()
        let content = window.contentView!

        let icon = NSImageView()
        icon.image = NSImage(contentsOf: Bundle.main.resourceURL!
            .appendingPathComponent("icons/scrcpy.png"))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let titles = NSStackView(views: [label("scrcpy", size: 20, weight: .semibold),
                                         label("Android 屏幕镜像", size: 11, color: .secondaryLabelColor)])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let settingsButton = iconButton("gearshape", tooltip: "设置", target: self,
                                        action: #selector(showSettings(_:)))
        let helpButton = iconButton("questionmark.circle", tooltip: "连接说明", target: self,
                                    action: #selector(showHelp(_:)))
        let header = NSStackView(views: [icon, titles, headerSpacer, settingsButton, helpButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        let divider = NSBox()
        divider.boxType = .separator
        let deviceSpacer = NSView()
        deviceSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        refreshButton = iconButton("arrow.clockwise", tooltip: "刷新设备", target: self,
                                   action: #selector(refresh(_:)))
        unlockButton = iconButton("lock.open", tooltip: "唤醒与解锁", target: self,
                                  action: #selector(showUnlock(_:)))
        let deviceRow = NSStackView(views: [label("设备", size: 14, weight: .semibold),
                                            deviceSpacer, unlockButton, refreshButton])
        deviceRow.orientation = .horizontal
        deviceRow.alignment = .centerY

        devicePicker = NSPopUpButton(frame: .zero, pullsDown: false)
        devicePicker.target = self
        devicePicker.action = #selector(deviceChanged(_:))
        statusDot = NSView()
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusLabel = label("", size: 12, color: .secondaryLabelColor)
        statusLabel.maximumNumberOfLines = 2
        let statusRow = NSStackView(views: [statusDot, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        mirrorButton = NSButton(title: "开始镜像", target: self, action: #selector(toggleMirror(_:)))
        mirrorButton.bezelStyle = .rounded
        mirrorButton.controlSize = .large
        mirrorButton.font = .systemFont(ofSize: 14, weight: .medium)
        mirrorButton.keyEquivalent = "\r"
        logButton = NSButton(title: "运行日志", target: self, action: #selector(showLog(_:)))
        logButton.isBordered = false
        logButton.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "运行日志")
        logButton.imagePosition = .imageLeading
        logButton.font = .systemFont(ofSize: 11)
        logButton.contentTintColor = .secondaryLabelColor

        for view in [header, divider, deviceRow, devicePicker!, statusRow, mirrorButton!, logButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            header.heightAnchor.constraint(equalToConstant: 40),
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            divider.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            divider.heightAnchor.constraint(equalToConstant: 1),
            deviceRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            deviceRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            deviceRow.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 24),
            deviceRow.heightAnchor.constraint(equalToConstant: 30),
            devicePicker.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            devicePicker.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            devicePicker.topAnchor.constraint(equalTo: deviceRow.bottomAnchor, constant: 9),
            devicePicker.heightAnchor.constraint(equalToConstant: 30),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            statusRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            statusRow.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            statusRow.topAnchor.constraint(equalTo: devicePicker.bottomAnchor, constant: 13),
            mirrorButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            mirrorButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            mirrorButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            mirrorButton.heightAnchor.constraint(equalToConstant: 38),
            logButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            logButton.bottomAnchor.constraint(equalTo: mirrorButton.topAnchor, constant: -12)
        ])
    }

    private func render() {
        let deviceList = model.devices.map { "\($0.serial):\($0.state):\($0.label)" }.joined(separator: "|")
        if deviceList != renderedDeviceList {
            renderedDeviceList = deviceList
            devicePicker.removeAllItems()
            if model.devices.isEmpty {
                devicePicker.addItem(withTitle: "暂无设备")
            } else {
                for device in model.devices {
                    devicePicker.addItem(withTitle: device.label)
                    devicePicker.lastItem?.representedObject = device.serial
                }
            }
        }
        devicePicker.isEnabled = !model.devices.isEmpty && !model.isScanning && !model.isMirroring
        if let index = model.devices.firstIndex(where: { $0.serial == model.selectedSerial }) {
            devicePicker.selectItem(at: index)
        }
        refreshButton.isEnabled = !model.isScanning
        unlockButton.isEnabled = model.currentSerial != nil
        statusLabel.stringValue = model.status
        let error = model.status.contains("失败") || model.status.contains("无法") ||
            model.status.contains("中断")
        statusDot.layer?.backgroundColor = (error ? NSColor.systemRed :
            model.isMirroring ? NSColor.systemGreen : NSColor.secondaryLabelColor).cgColor
        mirrorButton.title = model.isMirroring ? "停止镜像" : "开始镜像"
        mirrorButton.isEnabled = model.isMirroring || model.selectedDevice?.isReady == true
        logButton.isHidden = model.logText.isEmpty
        logView?.string = model.logText
        syncMirrorUI()
    }

    private func syncMirrorUI() {
        if model.isMirroring && !wasMirroring {
            wasMirroring = true
            window.orderOut(nil)
        } else if !model.isMirroring && wasMirroring {
            wasMirroring = false
            showControls()
        }
    }

    private func showControls() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showControlsFromMenu(_ sender: Any?) { showControls() }

    @objc private func showControlsFromMirror(_ notification: Notification) { showControls() }

    @objc private func refresh(_ sender: Any?) { model.refreshDevices() }

    @objc private func deviceChanged(_ sender: Any?) {
        if let serial = devicePicker.selectedItem?.representedObject as? String {
            model.selectDevice(serial)
        }
    }

    @objc private func toggleMirror(_ sender: Any?) {
        model.isMirroring ? model.stop() : model.start()
    }

    @objc private func showSettings(_ sender: NSButton) {
        helpPopover?.close()
        unlockPopover?.close()
        if settingsPopover?.isShown == true {
            settingsPopover?.close()
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        let serial = model.currentSerial
        popover.contentViewController = SettingsController(model: model, serial: serial) { [weak self] in
            self?.model.settingsChanged()
        }
        settingsPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func showHelp(_ sender: NSButton) {
        settingsPopover?.close()
        unlockPopover?.close()
        if helpPopover?.isShown == true {
            helpPopover?.close()
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = HelpController()
        helpPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func showUnlock(_ sender: NSButton) {
        settingsPopover?.close()
        helpPopover?.close()
        if unlockPopover?.isShown == true {
            unlockPopover?.close()
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = UnlockController(model: model, serial: model.currentSerial)
        unlockPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func showLog(_ sender: Any?) {
        if logWindow == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 320),
                                 styleMask: [.titled, .closable, .resizable],
                                 backing: .buffered, defer: false)
            panel.title = "scrcpy 运行日志"
            panel.isReleasedWhenClosed = false
            panel.center()
            let scroll = NSScrollView(frame: panel.contentView!.bounds)
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds)
            text.isEditable = false
            text.isSelectable = true
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.autoresizingMask = [.width]
            scroll.documentView = text
            panel.contentView?.addSubview(scroll)
            logView = text
            logWindow = panel
        }
        logView?.string = model.logText
        logWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
private let launcher = LauncherApp()
app.delegate = launcher
app.run()
