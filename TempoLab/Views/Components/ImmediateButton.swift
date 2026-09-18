import SwiftUI

nonisolated struct ImmediatePressState: Equatable, Sendable {
    private(set) var isActive = false

    mutating func begin() -> Bool {
        guard !isActive else { return false }
        isActive = true
        return true
    }

    mutating func end() {
        isActive = false
    }
}

struct ImmediateButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label

    private let tint: Color
    private let isProminent: Bool
    private let keyboardShortcut: KeyboardShortcut?
    private let circularDiameter: CGFloat?

    @State private var pressState = ImmediatePressState()

    init(
        tint: Color = .accentColor,
        isProminent: Bool = false,
        circularDiameter: CGFloat? = nil,
        keyboardShortcut: KeyboardShortcut? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.tint = tint
        self.isProminent = isProminent
        self.circularDiameter = circularDiameter
        self.keyboardShortcut = keyboardShortcut
        self.action = action
        self.label = label
    }

    var body: some View {
        label()
            .font(.headline)
            .foregroundStyle(isProminent ? Color.white : tint)
            .padding(.horizontal, circularDiameter == nil ? 16 : 8)
            .padding(.vertical, circularDiameter == nil ? 10 : 6)
            .frame(
                maxWidth: circularDiameter == nil ? .infinity : nil,
                minHeight: 44
            )
            .frame(width: circularDiameter, height: circularDiameter)
            .background {
                if circularDiameter == nil {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isProminent ? tint : tint.opacity(0.1))
                } else {
                    Circle()
                        .fill(isProminent ? tint : tint.opacity(0.1))
                }
            }
            .overlay {
                if !isProminent {
                    if circularDiameter == nil {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(tint.opacity(0.35), lineWidth: 1)
                    } else {
                        Circle()
                            .stroke(tint.opacity(0.35), lineWidth: 1)
                    }
                }
            }
            .scaleEffect(pressState.isActive ? 0.98 : 1)
            .opacity(pressState.isActive ? 0.72 : 1)
            .contentShape(Rectangle())
            .gesture(immediatePressGesture)
            .background(keyboardShortcutButton)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                action()
            }
    }

    private var immediatePressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard pressState.begin() else { return }
                action()
            }
            .onEnded { _ in
                pressState.end()
            }
    }

    @ViewBuilder
    private var keyboardShortcutButton: some View {
        if let keyboardShortcut {
            Button(action: action) {
                Color.clear
                    .frame(width: 0, height: 0)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(keyboardShortcut)
            .accessibilityHidden(true)
        }
    }
}
