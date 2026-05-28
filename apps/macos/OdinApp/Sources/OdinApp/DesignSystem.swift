import SwiftUI
import AppKit

enum OdinStyle {
    // Brand colors
    static let accent = Color(red: 0.58, green: 0.38, blue: 0.98) // Electric violet
    static let accentSecondary = Color(red: 0.20, green: 0.65, blue: 0.95) // Cool cyan
    static let gold = Color(red: 0.95, green: 0.65, blue: 0.20) // Amber gold

    static let green = Color(red: 0.15, green: 0.82, blue: 0.52) // Emerald mint
    static let red = Color(red: 0.95, green: 0.34, blue: 0.32) // Coral red

    // Backgrounds
    static let background = Color(red: 0.05, green: 0.05, blue: 0.08)

    // Typography Ink opacities
    static let ink = Color.white.opacity(0.96)
    static let secondaryInk = Color.white.opacity(0.74)
    static let tertiaryInk = Color.white.opacity(0.48)
    static let separator = Color.white.opacity(0.08)

    // Sizing
    static let panelRadius: CGFloat = 22
    static let cardRadius: CGFloat = 12
    static let chipRadius: CGFloat = 12

    static let cardFill = Color.white.opacity(0.04)
    static let cardFillHover = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.08)
    static let cardStrokeHover = Color.white.opacity(0.16)

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum OdinNotchMetrics {
    static let restingHeight: CGFloat = 32
    static let fallbackRestingWidth: CGFloat = 220
    static let minimumRestingWidth: CGFloat = 200
    static let maximumRestingWidth: CGFloat = 280
    static let minimumHoverWidth: CGFloat = 240
    static let hoverHorizontalGrowth: CGFloat = 20
    static let expandedTopBleed: CGFloat = 6

    static func restingWidth(on screen: NSScreen? = NSScreen.main) -> CGFloat {
        guard let screen else { return fallbackRestingWidth }
        guard let left = screen.auxiliaryTopLeftArea?.width,
              let right = screen.auxiliaryTopRightArea?.width else {
            return fallbackRestingWidth
        }

        let measuredWidth = screen.frame.width - left - right + 4
        return min(max(measuredWidth, minimumRestingWidth), maximumRestingWidth)
    }

    static func restingSize(on screen: NSScreen? = NSScreen.main) -> CGSize {
        CGSize(width: restingWidth(on: screen), height: restingHeight)
    }

    static func hoverWidth(on screen: NSScreen? = NSScreen.main) -> CGFloat {
        max(minimumHoverWidth, restingWidth(on: screen) + hoverHorizontalGrowth)
    }

    static func activationRect(on screen: NSScreen? = NSScreen.main) -> CGRect {
        guard let screen else { return .zero }
        let width = restingWidth(on: screen) + 16
        let height = max(restingHeight + 16, 44)
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    static func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}

struct NotchShape: Shape {
    var cornerRadius: CGFloat = OdinStyle.panelRadius

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        p.closeSubpath()
        return p
    }
}

struct NotchBorder: Shape {
    var cornerRadius: CGFloat = OdinStyle.panelRadius

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - r),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

struct NotchSurface: ViewModifier {
    var cornerRadius: CGFloat = OdinStyle.panelRadius
    var isAccented: Bool = false
    var isIdle: Bool = false

    func body(content: Content) -> some View {
        let borderGradient = LinearGradient(
            colors: isAccented ?
                [OdinStyle.accent.opacity(0.4), OdinStyle.accentSecondary.opacity(0.2)] :
                [Color.white.opacity(0.12), Color.white.opacity(0.03)],
            startPoint: .top,
            endPoint: .bottom
        )
        let strokeWidth: CGFloat = isIdle ? 1.2 : 0.7

        return content
            .background(
                NotchShape(cornerRadius: cornerRadius)
                    .fill(OdinStyle.background.opacity(0.78))
            )
            .glassEffect(.regular, in: NotchShape(cornerRadius: cornerRadius))
            .overlay(
                NotchBorder(cornerRadius: cornerRadius)
                    .stroke(borderGradient, lineWidth: strokeWidth)
            )
    }
}

extension View {
    func notchSurface(
        cornerRadius: CGFloat = OdinStyle.panelRadius,
        isAccented: Bool = false,
        isIdle: Bool = false
    ) -> some View {
        modifier(NotchSurface(
            cornerRadius: cornerRadius,
            isAccented: isAccented,
            isIdle: isIdle
        ))
    }

    func glassSurface(
        cornerRadius: CGFloat = OdinStyle.panelRadius,
        isAccented: Bool = false
    ) -> some View {
        modifier(NotchSurface(cornerRadius: cornerRadius, isAccented: isAccented))
    }
}

struct SoftChip: ViewModifier {
    var radius: CGFloat = OdinStyle.chipRadius
    var height: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(height: height)
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}

extension View {
    func softChip(radius: CGFloat = OdinStyle.chipRadius, height: CGFloat = 22) -> some View {
        modifier(SoftChip(radius: radius, height: height))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(OdinStyle.brandGradient)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: OdinStyle.accent.opacity(0.24), radius: 6, y: 2)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OdinStyle.secondaryInk)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct CustomGlassButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPrimary ? .white : OdinStyle.secondaryInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isPrimary ? OdinStyle.accent.opacity(0.12) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isPrimary ?
                        LinearGradient(colors: [OdinStyle.accent.opacity(0.4), OdinStyle.accentSecondary.opacity(0.2)], startPoint: .top, endPoint: .bottom) :
                        LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CustomGlassButtonStyle {
    static func customGlass(cornerRadius: CGFloat = 8, isPrimary: Bool = false) -> CustomGlassButtonStyle {
        CustomGlassButtonStyle(cornerRadius: cornerRadius, isPrimary: isPrimary)
    }
    static var customGlass: CustomGlassButtonStyle {
        CustomGlassButtonStyle(cornerRadius: 8, isPrimary: false)
    }
}

struct ScaleOnHover: ViewModifier {
    @State private var isHovering = false
    var scale: CGFloat = 1.02

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? scale : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func scaleOnHover(scale: CGFloat = 1.02) -> some View {
        modifier(ScaleOnHover(scale: scale))
    }
}
