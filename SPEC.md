# ScreenInkPen — specification

**Tagline:** Draw arrows, boxes and freehand ink right on top of your screen during demos and calls, then wipe it clean.

**Category:** Presentation & Cursor

**Inspired by (paid):** Presentify ($7 one-time)

**Frameworks:** SwiftUI, AppKit, CoreGraphics, ServiceManagement, Carbon

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Presentify lets you draw over whatever is on your display with pens, arrows, shapes and text while presenting, and it costs around seven dollars on the Mac App Store and Setapp. Reviewers in Mac blogs praise its small control strip and the way it works in video calls, which is why it keeps showing up in recommendation lists for teachers and streamers.

Our clean-room feature set: a global hotkey toggles drawing mode. In drawing mode a transparent full-screen overlay window per display captures the mouse. Tools are freehand pen, highlighter with transparency, straight line, arrow, rectangle, ellipse and eraser. Five preset colors and three stroke widths. Undo and redo for strokes, clear all with one key, and an option for strokes to fade out after a few seconds. Pressing Escape exits drawing mode and removes the ink. Aim for around five hundred lines.

UI spec: a MenuBarExtra with a pencil icon offering Start Drawing, Clear, Tool submenu, Color submenu, Settings and Quit. While drawing, a small floating toolbar panel sits at the top center of the main display, with tool buttons, color dots, width selector, undo and clear. Keyboard shortcuts inside drawing mode: P pen, H highlighter, L line, A arrow, R rectangle, O ellipse, E eraser, number keys one to five for colors, Command Z undo, Shift Command Z redo, Delete clear. Settings window: global hotkey recorder, default color, default width, fade out toggle with seconds field, launch at login. Empty state: a first-run hint inside the toolbar says press P to start inking.

Technical approach: for each NSScreen create a borderless NSWindow at the screen saver level with a clear background, ignoresMouseEvents toggled false only in drawing mode, and collection behavior canJoinAllSpaces plus fullScreenAuxiliary so it shows over full screen apps. The canvas is an NSView hosted via NSViewRepresentable or pure AppKit that stores an array of stroke models and draws them with CGContext paths in draw. Fade timers use a Timer that lowers alpha per stroke. The global hotkey uses RegisterEventHotKey from Carbon, so no Accessibility permission is needed. No screen recording permission is required because we never read pixels. Settings persist in UserDefaults through AppStorage, and launch at login uses SMAppService.

Edge cases: when displays are added or removed, rebuild overlay windows from the screen parameters changed notification. When the app is toggled while a menu is open, dismiss it first. Make sure the toolbar panel never steals focus from the presenting app by using a nonactivating panel style. Highlighter strokes should use multiply blending so text below stays readable. Large stroke counts should be flattened into a cached image after a few hundred strokes to keep drawing smooth. Respect Reduce Motion by disabling fade animations.
