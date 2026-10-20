import AppKit
import SwiftUI

/// Central state for ScreenInkPen: drawing mode, current tool/colour/width, the stroke list with
/// undo/redo history, fade-out timing, and the per-display overlay windows plus floating toolbar.
@MainActor
final class InkController: ObservableObject {
    static let shared = InkController()

    @Published private(set) var isDrawing = false
    @Published var tool: InkTool = .pen
    @Published var colorIndex = 0
    @Published var widthIndex = 1
    @Published private(set) var strokes: [Stroke] = []
    /// Bumped whenever strokes change in a way other than appending, so canvases drop their caches.
    private(set) var generation = 0

    private var undoStack: [[Stroke]] = []
    private var redoStack: [[Stroke]] = []
    private var overlays: [CGDirectDisplayID: OverlayWindow] = [:]
    private var toolbar: NSPanel?
    private var fadeTimer: Timer?
    private weak var trackedMenu: NSMenu?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var color: NSColor { InkPalette.color(at: colorIndex) }
    var width: CGFloat { InkPalette.width(at: widthIndex) * (tool == .highlighter ? 3 : 1) }

    private init() {
        applyDefaults()
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in InkController.shared.rebuildOverlays() }
        }
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
            let menu = note.object as? NSMenu
            Task { @MainActor in InkController.shared.trackedMenu = menu }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in InkController.shared.trackedMenu = nil }
        }
    }

    /// Loads the default colour and width chosen in Settings.
    func applyDefaults() {
        let d = UserDefaults.standard
        colorIndex = max(0, min(InkPalette.colors.count - 1, d.integer(forKey: PrefKey.defaultColor)))
        widthIndex = d.object(forKey: PrefKey.defaultWidth) == nil ? 1 : max(0, min(2, d.integer(forKey: PrefKey.defaultWidth)))
    }

    // MARK: Drawing mode

    /// Toggles drawing mode, dismissing any open menu first so the overlay can take the mouse.
    func toggle() {
        if let menu = trackedMenu {
            menu.cancelTracking()
            trackedMenu = nil
            DispatchQueue.main.async { InkController.shared.toggle() }
            return
        }
        isDrawing ? stopDrawing() : startDrawing()
    }

    func startDrawing() {
        guard !isDrawing else { return }
        isDrawing = true
        if overlays.isEmpty { rebuildOverlays() }
        for window in overlays.values {
            window.ignoresMouseEvents = false
            window.orderFrontRegardless()
        }
        // Key focus goes to the overlay under the mouse so shortcuts work; panels are nonactivating,
        // so the presenting app stays frontmost.
        let mouse = NSEvent.mouseLocation
        let target = overlays.values.first { $0.frame.contains(mouse) } ?? overlays.values.first
        target?.makeKey()
        showToolbar()
        NSCursor.crosshair.set()
    }

    func stopDrawing() {
        guard isDrawing else { return }
        isDrawing = false
        for window in overlays.values {
            window.ignoresMouseEvents = true
            window.orderOut(nil)
            window.orderFrontRegardless()
        }
        toolbar?.orderOut(nil)
        NSCursor.arrow.set()
    }

    /// Escape: leave drawing mode and wipe the ink.
    func exitAndClear() {
        clear()
        stopDrawing()
    }

    // MARK: Stroke editing

    func begin(_ stroke: Stroke) {
        pushUndo()
        strokes.append(stroke)
        UserDefaults.standard.set(true, forKey: PrefKey.hasInked)
    }

    func updateLast(_ update: (inout Stroke) -> Void) {
        guard !strokes.isEmpty else { return }
        update(&strokes[strokes.count - 1])
    }

    func finishLast() {
        updateLast { $0.finishedAt = Date() }
        startFadeTimerIfNeeded()
    }

    /// Removes strokes on `display` near `point`. Returns whether anything was erased.
    @discardableResult
    func erase(at point: CGPoint, on display: CGDirectDisplayID, radius: CGFloat) -> Bool {
        let before = strokes.count
        strokes.removeAll { $0.displayID == display && $0.hitTest(point, radius: radius) }
        guard strokes.count != before else { return false }
        generation += 1
        return true
    }

    func pushUndo() {
        undoStack.append(strokes)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Drops the most recent undo snapshot (used when an eraser drag removed nothing).
    func discardLastUndo() { _ = undoStack.popLast() }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        replace(with: previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        replace(with: next)
    }

    func clear() {
        guard !strokes.isEmpty else { return }
        pushUndo()
        replace(with: [])
    }

    private func replace(with newStrokes: [Stroke]) {
        let now = Date()
        // Restored strokes get a fresh fade clock so they don't vanish immediately.
        strokes = newStrokes.map { var s = $0; s.alpha = 1; if s.finishedAt != nil { s.finishedAt = now }; return s }
        generation += 1
        startFadeTimerIfNeeded()
        redrawAll()
    }

    func redrawAll() {
        for window in overlays.values { window.canvas.needsDisplay = true }
    }

    // MARK: Fade-out

    private func startFadeTimerIfNeeded() {
        guard UserDefaults.standard.bool(forKey: PrefKey.fadeEnabled), fadeTimer == nil, !strokes.isEmpty else { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in InkController.shared.tickFade() }
        }
    }

    /// Lowers each finished stroke's alpha once it is older than the fade delay; removes faded strokes.
    private func tickFade() {
        let d = UserDefaults.standard
        guard d.bool(forKey: PrefKey.fadeEnabled), !strokes.isEmpty else {
            fadeTimer?.invalidate(); fadeTimer = nil; return
        }
        let delay = max(1, d.double(forKey: PrefKey.fadeSeconds))
        let fadeDuration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 1.0
        let now = Date()
        var changed = false
        var updated = strokes
        for i in updated.indices {
            guard let done = updated[i].finishedAt else { continue }
            let age = now.timeIntervalSince(done) - delay
            guard age > 0 else { continue }
            let alpha = fadeDuration > 0 ? CGFloat(max(0, 1 - age / fadeDuration)) : 0
            if alpha != updated[i].alpha { updated[i].alpha = alpha; changed = true }
        }
        guard changed else { return }
        updated.removeAll { $0.alpha <= 0 }
        strokes = updated
        generation += 1
        redrawAll()
    }

    // MARK: Windows

    /// Creates one transparent overlay per screen; called at launch and when displays change.
    func rebuildOverlays() {
        for window in overlays.values { window.orderOut(nil) }
        overlays.removeAll()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let window = OverlayWindow(screen: screen, displayID: id)
            window.ignoresMouseEvents = !isDrawing
            window.orderFrontRegardless()
            overlays[id] = window
        }
        if isDrawing { showToolbar() }
    }

    private func showToolbar() {
        let panel = toolbar ?? makeToolbar()
        toolbar = panel
        guard let screen = NSScreen.screens.first else { return }
        let size = panel.contentView?.fittingSize ?? NSSize(width: 560, height: 48)
        panel.setContentSize(size)
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 12))
        panel.orderFrontRegardless()
    }

    private func makeToolbar() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 48),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: ToolbarView().environmentObject(self))
        panel.contentView = host
        return panel
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
