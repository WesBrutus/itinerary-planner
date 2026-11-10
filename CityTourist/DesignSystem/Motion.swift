import SwiftUI

// MARK: - Press feedback

/// Buttons give under the finger and spring back, so a tap is felt before the
/// screen changes.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Shake

/// A short sideways shake for a rejected entry. Animate `animatableData` from
/// one whole number to the next.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}

// MARK: - The route
//
// The line with three stops from the launch animation is the app's signature.
// Onboarding reuses it as its hero and as its progress bar.

struct RouteShape: Shape {
    /// Where the three stops sit, as fractions of the frame.
    static let stops = [CGPoint(x: 0.08, y: 0.78), CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.92, y: 0.62)]

    static func stop(_ index: Int, in size: CGSize) -> CGPoint {
        let point = stops[min(max(index, 0), stops.count - 1)]
        return CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    func path(in rect: CGRect) -> Path {
        let size = rect.size
        let first = Self.stop(0, in: size), second = Self.stop(1, in: size), third = Self.stop(2, in: size)
        var path = Path()
        path.move(to: first)
        path.addCurve(to: second,
                      control1: CGPoint(x: size.width * 0.28, y: first.y),
                      control2: CGPoint(x: size.width * 0.3, y: second.y))
        path.addCurve(to: third,
                      control1: CGPoint(x: size.width * 0.7, y: second.y),
                      control2: CGPoint(x: size.width * 0.72, y: third.y))
        return path
    }
}

/// A dot that rides the route: the traveller on their way.
struct RouteTraveler: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let route = RouteShape().path(in: rect)
        let clamped = min(max(progress, 0), 1)
        let point = clamped <= 0.001
            ? RouteShape.stop(0, in: rect.size)
            : route.trimmedPath(from: 0, to: clamped).currentPoint ?? RouteShape.stop(0, in: rect.size)
        return Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
    }
}

/// The route drawn large, with a category badge springing in at each stop.
struct RouteHero: View {
    /// Symbols shown at the three stops.
    var symbols = ["fork.knife", "building.columns", "leaf"]
    /// Marks every stop as visited, for the finish.
    var completed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var travelling = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RouteShape().stroke(Palette.hairline, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                RouteShape().trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Brand.rausch, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.9).delay(0.1), value: drawn)
                if !reduceMotion && !completed {
                    RouteTraveler(progress: travelling ? 1 : 0)
                        .fill(Brand.rauschDeep)
                        .opacity(drawn ? 1 : 0)
                        .animation(.easeInOut(duration: 3.2).delay(1.2).repeatForever(autoreverses: true), value: travelling)
                }
                ForEach(0..<3, id: \.self) { index in
                    badge(index)
                        .scaleEffect(drawn ? 1 : 0.3)
                        .opacity(drawn ? 1 : 0)
                        .animation(reduceMotion ? nil : Animation.spring(response: 0.4, dampingFraction: 0.55)
                            .delay(0.15 + Double(index) * 0.32), value: drawn)
                        .position(RouteShape.stop(index, in: proxy.size))
                }
            }
        }
        .onAppear { drawn = true; travelling = true }
        .accessibilityHidden(true)
    }

    private func badge(_ index: Int) -> some View {
        Image(systemName: completed ? "checkmark" : symbols[index % symbols.count])
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(completed ? Color.white : Brand.rausch)
            .frame(width: 52, height: 52)
            .background(completed ? Brand.rausch : Palette.elevated, in: Circle())
            .overlay(Circle().stroke(Brand.rausch, lineWidth: 3))
            .floatingShadow()
    }
}

/// Onboarding's progress bar: one stop per step, filled as the traveller
/// reaches it.
struct RouteProgress: View {
    let stops: Int
    /// How many stops have been reached, 0 through `stops`.
    let reached: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let dot: CGFloat = 14
            let width = max(0, proxy.size.width - dot)
            let gap = stops > 1 ? width / CGFloat(stops - 1) : 0
            let filled = stops > 1 ? CGFloat(max(0, min(reached, stops) - 1)) / CGFloat(stops - 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.hairline).frame(width: width, height: 3).offset(x: dot / 2)
                Capsule().fill(Brand.rausch).frame(width: width * filled, height: 3).offset(x: dot / 2)
                ForEach(0..<stops, id: \.self) { index in
                    Circle()
                        .fill(index < reached ? Brand.rausch : Palette.canvas)
                        .overlay(Circle().stroke(index < reached ? Brand.rausch : Palette.hairline, lineWidth: 3))
                        .frame(width: dot, height: dot)
                        .scaleEffect(index == reached - 1 ? 1.3 : 1)
                        .offset(x: CGFloat(index) * gap)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 20)
        .animation(reduceMotion ? nil : Animation.spring(response: 0.45, dampingFraction: 0.6), value: reached)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Step %d of %d", reached, stops))
    }
}
