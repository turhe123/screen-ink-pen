import SwiftUI
import ServiceManagement

/// Preferences: global hotkey, default colour/width, fade-out, launch at login and support link.
struct SettingsView: View {
    @AppStorage(PrefKey.defaultColor) private var defaultColor = 0
    @AppStorage(PrefKey.defaultWidth) private var defaultWidth = 1
    @AppStorage(PrefKey.fadeEnabled) private var fadeEnabled = false
    @AppStorage(PrefKey.fadeSeconds) private var fadeSeconds = 3.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Drawing mode") {
                LabeledContent("Toggle hotkey") { HotKeyRecorder() }
                Picker("Default color", selection: $defaultColor) {
                    ForEach(InkPalette.colors.indices, id: \.self) { i in Text(InkPalette.colorNames[i]).tag(i) }
                }
                Picker("Default width", selection: $defaultWidth) {
                    ForEach(InkPalette.widths.indices, id: \.self) { i in Text(InkPalette.widthNames[i]).tag(i) }
                }
            }
            Section("Fade out") {
                Toggle("Fade strokes out automatically", isOn: $fadeEnabled)
                TextField("Seconds before fading", value: $fadeSeconds, format: .number.precision(.fractionLength(0...1)))
                    .disabled(!fadeEnabled)
                Text("With Reduce Motion on, strokes disappear without animating.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Text("No Accessibility or Screen Recording permission is needed — ScreenInkPen never reads your screen.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Support / Donate ❤️") { Support.openDonationPage() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onChange(of: defaultColor) { _, _ in InkController.shared.applyDefaults() }
        .onChange(of: defaultWidth) { _, _ in InkController.shared.applyDefaults() }
        .onChange(of: fadeSeconds) { _, value in if value < 1 { fadeSeconds = 1 } }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription). You can manage it in System Settings › General › Login Items."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click-to-record control that captures the next key combination as the global hotkey.
struct HotKeyRecorder: View {
    @AppStorage(PrefKey.hotKeyCode) private var keyCode = Int(HotKeyService.defaultKeyCode)
    @AppStorage(PrefKey.hotKeyModifiers) private var modifiers = Int(HotKeyService.defaultModifiers)
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(recording ? "Press keys…" : HotKeyService.describe(code: UInt32(keyCode), modifiers: UInt32(modifiers))) {
                recording ? stop() : start()
            }
            .frame(minWidth: 110)
            Button("Reset") {
                keyCode = Int(HotKeyService.defaultKeyCode)
                modifiers = Int(HotKeyService.defaultModifiers)
                HotKeyService.shared.register()
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53 { stop(); return nil } // Escape cancels
            // Require at least one of ⌘ ⌥ ⌃ so the shortcut doesn't swallow normal typing.
            guard !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            keyCode = Int(event.keyCode)
            modifiers = Int(HotKeyService.carbonModifiers(flags))
            HotKeyService.shared.register()
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
