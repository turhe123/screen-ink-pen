import SwiftUI

/// The compact floating control strip shown at the top of the main display while drawing.
struct ToolbarView: View {
    @EnvironmentObject private var ink: InkController
    @AppStorage(PrefKey.hasInked) private var hasInked = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(InkTool.allCases) { tool in
                    Button { ink.tool = tool } label: {
                        Image(systemName: tool.symbol)
                            .frame(width: 26, height: 26)
                            .background(ink.tool == tool ? Color.accentColor.opacity(0.35) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("\(tool.title) (\(tool.shortcut.uppercased()))")
                }
            }
            Divider().frame(height: 22)
            HStack(spacing: 6) {
                ForEach(InkPalette.colors.indices, id: \.self) { i in
                    Button { ink.colorIndex = i } label: {
                        Circle()
                            .fill(Color(nsColor: InkPalette.colors[i]))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.primary, lineWidth: ink.colorIndex == i ? 2 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("\(InkPalette.colorNames[i]) (\(i + 1))")
                }
            }
            Divider().frame(height: 22)
            Picker("Width", selection: $ink.widthIndex) {
                ForEach(InkPalette.widths.indices, id: \.self) { i in
                    Circle().frame(width: InkPalette.widths[i] + 2, height: InkPalette.widths[i] + 2)
                        .help(InkPalette.widthNames[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 96)
            Divider().frame(height: 22)
            Button { ink.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain).disabled(!ink.canUndo).help("Undo (⌘Z)")
            Button { ink.clear() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).disabled(ink.strokes.isEmpty).help("Clear (Delete)")
            Button { ink.stopDrawing() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).help("Stop drawing (keeps ink). Esc clears and exits.")
            if !hasInked {
                Text("Press P to start inking")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.15)))
        .padding(4)
        .fixedSize()
    }
}
