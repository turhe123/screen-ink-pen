import AppKit

/// The drawing tools available in drawing mode, with their single-key shortcuts.
enum InkTool: String, CaseIterable, Identifiable {
    case pen, highlighter, line, arrow, rectangle, ellipse, eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .eraser: return "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .eraser: return "eraser"
        }
    }

    /// Lower-case key that selects this tool inside drawing mode.
    var shortcut: String {
        switch self {
        case .pen: return "p"
        case .highlighter: return "h"
        case .line: return "l"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .eraser: return "e"
        }
    }

    /// Shapes are defined by a start and end point rather than a free path.
    var isShape: Bool { [.line, .arrow, .rectangle, .ellipse].contains(self) }
}

/// The five preset ink colours and three stroke widths.
enum InkPalette {
    static let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white]
    static let colorNames = ["Red", "Yellow", "Green", "Blue", "White"]
    static let widths: [CGFloat] = [3, 6, 12]
    static let widthNames = ["Thin", "Medium", "Thick"]

    static func color(at index: Int) -> NSColor { colors[max(0, min(colors.count - 1, index))] }
    static func width(at index: Int) -> CGFloat { widths[max(0, min(widths.count - 1, index))] }
}

/// One piece of ink: a tool, its style, the display it lives on and its points in view coordinates.
struct Stroke {
    let id = UUID()
    var tool: InkTool
    var color: NSColor
    var width: CGFloat
    var displayID: CGDirectDisplayID
    var points: [CGPoint]
    /// When the stroke was finished; drives fade-out. `nil` while still being drawn.
    var finishedAt: Date?
    var alpha: CGFloat = 1

    /// Builds the geometric path for this stroke (without the arrow head).
    func path() -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        let last = points.last ?? first
        switch tool {
        case .pen, .highlighter, .eraser:
            path.move(to: first)
            if points.count < 3 {
                path.addLine(to: last)
            } else {
                for i in 1..<points.count - 1 {
                    let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
                    path.addQuadCurve(to: mid, control: points[i])
                }
                path.addLine(to: last)
            }
        case .line, .arrow:
            path.move(to: first)
            path.addLine(to: last)
            if tool == .arrow, hypot(last.x - first.x, last.y - first.y) > 1 {
                let angle = atan2(last.y - first.y, last.x - first.x)
                let head = max(14, width * 4)
                for offset in [CGFloat.pi * 0.83, -CGFloat.pi * 0.83] {
                    path.move(to: last)
                    path.addLine(to: CGPoint(x: last.x + head * cos(angle + offset), y: last.y + head * sin(angle + offset)))
                }
            }
        case .rectangle:
            path.addRect(CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                                width: abs(last.x - first.x), height: abs(last.y - first.y)))
        case .ellipse:
            path.addEllipse(in: CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                                       width: abs(last.x - first.x), height: abs(last.y - first.y)))
        }
        return path
    }

    /// Renders the stroke into a Core Graphics context.
    func draw(in ctx: CGContext) {
        guard !points.isEmpty, alpha > 0 else { return }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if tool == .highlighter {
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(color.withAlphaComponent(0.35 * alpha).cgColor)
            ctx.setLineCap(.square)
        } else {
            ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
        }
        ctx.setLineWidth(width)
        ctx.addPath(path())
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Whether a point lies on (or near) this stroke; used by the eraser.
    func hitTest(_ point: CGPoint, radius: CGFloat) -> Bool {
        path().copy(strokingWithWidth: width + radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .contains(point)
    }
}

/// UserDefaults keys shared between `@AppStorage` and the services.
enum PrefKey {
    static let defaultColor = "defaultColor"
    static let defaultWidth = "defaultWidth"
    static let fadeEnabled = "fadeEnabled"
    static let fadeSeconds = "fadeSeconds"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let hasInked = "hasInked"
}

/// Opens the project's donation page.
enum Support {
    static func openDonationPage() {
        // Constant, known-valid URL literal.
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
