import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide hotkey through Carbon's `RegisterEventHotKey`
/// (no Accessibility permission required) and invokes a handler when it fires.
final class HotKeyService {
    static let shared = HotKeyService()

    /// Default shortcut: ⌃⌥P.
    static let defaultKeyCode = UInt32(kVK_ANSI_P)
    static let defaultModifiers = UInt32(controlKey | optionKey)

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Installs the Carbon event handler once and registers the stored shortcut.
    func start() {
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyService.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, &handlerRef)
        }
        register()
    }

    /// (Re)registers the shortcut stored in UserDefaults.
    func register() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        let (code, mods) = Self.current()
        let id = EventHotKeyID(signature: OSType(0x494E4B50), id: 1) // 'INKP'
        let status = RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { NSLog("ScreenInkPen: hotkey registration failed (\(status))") }
    }

    static func current() -> (UInt32, UInt32) {
        let d = UserDefaults.standard
        guard d.object(forKey: PrefKey.hotKeyCode) != nil else { return (defaultKeyCode, defaultModifiers) }
        return (UInt32(d.integer(forKey: PrefKey.hotKeyCode)), UInt32(d.integer(forKey: PrefKey.hotKeyModifiers)))
    }

    /// Converts AppKit modifier flags to Carbon modifier bits.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// Human-readable description such as "⌃⌥P".
    static func describe(code: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName(code)
    }

    private static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_F1: "F1", kVK_F2: "F2",
                                      kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8"]
        if let name = special[Int(code)] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let result = data.withUnsafeBytes { buf -> OSStatus in
            guard let layout = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard result == noErr, length > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
