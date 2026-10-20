import AppKit
import Carbon.HIToolbox

/// A borderless, transparent, nonactivating panel covering one display at screen-saver level.
/// It ignores the mouse except in drawing mode and routes drawing-mode keyboard shortcuts.
final class OverlayWindow: NSPanel {
    let canvas: InkCanvasView

    init(screen: NSScreen, displayID: CGDirectDisplayID) {
        canvas = InkCanvasView(displayID: displayID)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = canvas
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        MainActor.assumeIsolated {
            if !handleKey(event) { super.keyDown(with: event) }
        }
    }

    @MainActor
    private func handleKey(_ event: NSEvent) -> Bool {
        let ink = InkController.shared
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch Int(event.keyCode) {
        case kVK_Escape: ink.exitAndClear(); return true
        case kVK_Delete, kVK_ForwardDelete: ink.clear(); return true
        default: break
        }
        if flags.contains(.command) {
            guard key == "z" else { return false }
            flags.contains(.shift) ? ink.redo() : ink.undo()
            return true
        }
        if let tool = InkTool.allCases.first(where: { $0.shortcut == key }) {
            ink.tool = tool
            return true
        }
        if let n = Int(key), (1...InkPalette.colors.count).contains(n) {
            ink.colorIndex = n - 1
            return true
        }
        return false
    }
}

/// The per-display canvas: turns mouse drags into strokes and renders them with CoreGraphics.
/// Once a display holds several hundred static strokes, older ones are flattened into a cached image.
final class InkCanvasView: NSView {
    let displayID: CGDirectDisplayID
    private static let flattenThreshold = 300
    private var cache: CGImage?
    private var cachedCount = 0
    private var cachedGeneration = -1
    private var cachedSize = CGSize.zero
    private var erasing = false
    private var erasedSomething = false

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        MainActor.assumeIsolated {
            if InkController.shared.isDrawing { addCursorRect(bounds, cursor: .crosshair) }
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        MainActor.assumeIsolated {
            window?.makeKey()
            let ink = InkController.shared
            let p = convert(event.locationInWindow, from: nil)
            if ink.tool == .eraser {
                erasing = true
                ink.pushUndo()
                erasedSomething = ink.erase(at: p, on: displayID, radius: 8)
                needsDisplay = true
                return
            }
            let points = ink.tool.isShape ? [p, p] : [p]
            ink.begin(Stroke(tool: ink.tool, color: ink.color, width: ink.width, displayID: displayID, points: points))
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        MainActor.assumeIsolated {
            let ink = InkController.shared
            let p = convert(event.locationInWindow, from: nil)
            if erasing {
                if ink.erase(at: p, on: displayID, radius: 8) { erasedSomething = true; needsDisplay = true }
                return
            }
            ink.updateLast { stroke in
                if stroke.tool.isShape { stroke.points[stroke.points.count - 1] = p } else { stroke.points.append(p) }
            }
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        MainActor.assumeIsolated {
            let ink = InkController.shared
            if erasing {
                erasing = false
                if !erasedSomething { ink.discardLastUndo() }
                return
            }
            ink.finishLast()
            needsDisplay = true
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        MainActor.assumeIsolated {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let ink = InkController.shared
            let mine = ink.strokes.filter { $0.displayID == displayID }
            let fading = UserDefaults.standard.bool(forKey: PrefKey.fadeEnabled)

            if cachedGeneration != ink.generation || cachedSize != bounds.size || fading || cachedCount > mine.count {
                cache = nil
                cachedCount = 0
            }
            if !fading, mine.count > Self.flattenThreshold, mine.count - cachedCount > Self.flattenThreshold / 2 {
                rebuildCache(with: Array(mine.dropLast(20)))
                cachedGeneration = ink.generation
            }
            if let cache { ctx.draw(cache, in: bounds) }
            for stroke in mine.dropFirst(cachedCount) { stroke.draw(in: ctx) }
        }
    }

    /// Renders `strokes` into an offscreen bitmap at backing resolution.
    private func rebuildCache(with strokes: [Stroke]) {
        let scale = window?.backingScaleFactor ?? 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        bitmap.scaleBy(x: scale, y: scale)
        strokes.forEach { $0.draw(in: bitmap) }
        cache = bitmap.makeImage()
        cachedCount = cache == nil ? 0 : strokes.count
        cachedSize = bounds.size
    }
}
