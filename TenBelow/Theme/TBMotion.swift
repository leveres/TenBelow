import SwiftUI

enum TBMotion {
    enum Duration {
        static let instant: Double = 0.12
        static let quick: Double = 0.20
        static let standard: Double = 0.30
        static let slow: Double = 0.46
    }

    static let press = Animation.spring(response: 0.24, dampingFraction: 0.86)
    static let stateChange = Animation.easeInOut(duration: Duration.quick)
    static let surface = Animation.spring(response: 0.32, dampingFraction: 0.90)
    static let success = Animation.spring(response: 0.38, dampingFraction: 0.82)

    static func surfaceTransition(reduceMotion: Bool, edge: Edge = .trailing) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: edge).combined(with: .opacity)
    }

    static func subtleReveal(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .offset(y: 6).combined(with: .opacity)
    }
}

private struct TBMotionAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func tbAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(TBMotionAnimationModifier(animation: animation, value: value))
    }
}

/// TabView keeps off-screen tabs mounted; gate continuous animations so only the selected tab runs them.
private struct TBTabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var tbTabIsActive: Bool {
        get { self[TBTabIsActiveKey.self] }
        set { self[TBTabIsActiveKey.self] = newValue }
    }
}
