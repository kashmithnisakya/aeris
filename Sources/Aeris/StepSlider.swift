import SwiftUI

/// A slider that snaps to discrete steps (e.g. vane angles "1"…"6"). Drag or click to pick a step;
/// the command is sent once, when you let go. Dimmed while `active` is false (e.g. while swinging).
struct StepSlider: View {
    let steps: [String]
    let selected: String?
    let active: Bool
    let startIcon: String
    let endIcon: String
    let label: String
    let onCommit: (String) -> Void

    @State private var dragIndex: Int?
    private let knob: CGFloat = 18

    private var index: Int {
        dragIndex ?? selected.flatMap { steps.firstIndex(of: $0) } ?? max(0, steps.count / 2)
    }
    private var lit: Bool { active || dragIndex != nil }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: startIcon).font(.caption2).foregroundStyle(.secondary)
            GeometryReader { geo in
                let n = max(steps.count - 1, 1)
                let usable = max(geo.size.width - knob, 1)
                let x = knob / 2 + usable * CGFloat(index) / CGFloat(n)
                let midY = geo.size.height / 2
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Color.secondary.opacity(0.22))
                        .frame(width: geo.size.width, height: 4).position(x: geo.size.width / 2, y: midY)
                    Capsule().fill(lit ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: x, height: 4).position(x: x / 2, y: midY)
                    ForEach(steps.indices, id: \.self) { i in
                        Circle()
                            .fill(i <= index && lit ? Color.white.opacity(0.9) : Color.secondary.opacity(0.55))
                            .frame(width: 3, height: 3)
                            .position(x: knob / 2 + usable * CGFloat(i) / CGFloat(n), y: midY)
                    }
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(lit ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .frame(width: knob, height: knob)
                        .position(x: x, y: midY)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let raw = (v.location.x - knob / 2) / usable * CGFloat(n)
                            dragIndex = min(max(Int(raw.rounded()), 0), steps.count - 1)
                        }
                        .onEnded { _ in
                            if let i = dragIndex { onCommit(steps[i]) }
                            dragIndex = nil
                        }
                )
            }
            .frame(height: 22)
            Image(systemName: endIcon).font(.caption2).foregroundStyle(.secondary)
            Text(lit ? steps[safe: index] ?? "" : "–")
                .font(.caption.monospacedDigit()).foregroundStyle(lit ? Color.primary : Color.secondary)
                .frame(width: 12, alignment: .trailing)
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(active ? "Angle \(steps[safe: index] ?? "")" : "Swinging")
        .accessibilityAdjustableAction { dir in
            let i = index + (dir == .increment ? 1 : -1)
            if steps.indices.contains(i) { onCommit(steps[i]) }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
