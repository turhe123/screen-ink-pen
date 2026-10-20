import SwiftUI

/// App entry point: a menu-bar-only app with a pencil MenuBarExtra and a Settings window.
@main
struct ScreenInkPenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var ink = InkController.shared

    var body: some Scene {
        MenuBarExtra("ScreenInkPen", systemImage: "pencil.tip") {
            MenuContent().environmentObject(ink)
        }
        Settings {
            SettingsView()
        }
    }
}

/// Sets up overlays and the global hotkey once the app has launched.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            InkController.shared.rebuildOverlays()
            HotKeyService.shared.onPress = { Task { @MainActor in InkController.shared.toggle() } }
            HotKeyService.shared.start()
        }
    }
}

/// The MenuBarExtra menu: start/stop, clear, tool and colour submenus, settings, support and quit.
struct MenuContent: View {
    @EnvironmentObject private var ink: InkController
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PrefKey.hotKeyCode) private var keyCode = Int(HotKeyService.defaultKeyCode)
    @AppStorage(PrefKey.hotKeyModifiers) private var modifiers = Int(HotKeyService.defaultModifiers)

    var body: some View {
        Button(ink.isDrawing ? "Stop Drawing" : "Start Drawing  (\(HotKeyService.describe(code: UInt32(keyCode), modifiers: UInt32(modifiers))))") {
            // Let the menu close before the overlay takes the mouse.
            DispatchQueue.main.async { InkController.shared.toggle() }
        }
        Button("Clear") { ink.clear() }
            .disabled(ink.strokes.isEmpty)
        Divider()
        Picker("Tool", selection: $ink.tool) {
            ForEach(InkTool.allCases) { tool in
                Label("\(tool.title)  (\(tool.shortcut.uppercased()))", systemImage: tool.symbol).tag(tool)
            }
        }
        Picker("Color", selection: $ink.colorIndex) {
            ForEach(InkPalette.colors.indices, id: \.self) { i in
                Text("\(InkPalette.colorNames[i])  (\(i + 1))").tag(i)
            }
        }
        Picker("Width", selection: $ink.widthIndex) {
            ForEach(InkPalette.widths.indices, id: \.self) { i in Text(InkPalette.widthNames[i]).tag(i) }
        }
        Divider()
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Support / Donate ❤️") { Support.openDonationPage() }
        Divider()
        Button("Quit ScreenInkPen") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
