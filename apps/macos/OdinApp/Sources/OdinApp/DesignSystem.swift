import SwiftUI
import AppKit

enum OdinStyle {
    // Brand colors: Monochromatic palette
    static let accent = Color.white // Monochromatic white
    static let accentSecondary = Color(white: 0.90) // Soft silver
    static let gold = Color(white: 0.90) // Soft silver

    static let green = Color(red: 0.2, green: 0.82, blue: 0.38) // Clean green
    static let red = Color(red: 1.0, green: 0.23, blue: 0.18) // Clean red

    // Dark neutral background
    static let background = Color(white: 0.06)

    // Neutral base tint
    static let warmCream = Color.white

    static let ink = warmCream.opacity(0.94)
    static let secondaryInk = warmCream.opacity(0.68)
    static let tertiaryInk = warmCream.opacity(0.42)
    static let separator = warmCream.opacity(0.06)

    // Sizing
    static let panelRadius: CGFloat = 22
    static let cardRadius: CGFloat = 12
    static let chipRadius: CGFloat = 12

    static let cardFill = warmCream.opacity(0.05)
    static let cardFillHover = warmCream.opacity(0.10)
    static let cardStroke = warmCream.opacity(0.08)
    static let cardStrokeHover = warmCream.opacity(0.14)

    static var brandGradient: Color {
        accent
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
        let borderColor = isAccented ?
            OdinStyle.accent.opacity(0.24) :
            OdinStyle.warmCream.opacity(0.06)
        let strokeWidth: CGFloat = isIdle ? 1.0 : 0.5

        return content
            .background(
                NotchShape(cornerRadius: cornerRadius)
                    .fill(OdinStyle.background.opacity(0.30))
            )
            .glassEffect(.regular, in: NotchShape(cornerRadius: cornerRadius))
            .overlay(
                NotchBorder(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: strokeWidth)
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
            .foregroundStyle(Color.black.opacity(0.85)) // Dark text for white/silver background
            .background(OdinStyle.brandGradient)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OdinStyle.secondaryInk)
            .background(OdinStyle.warmCream.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(OdinStyle.warmCream.opacity(0.08), lineWidth: 0.5)
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
            .foregroundStyle(isPrimary ? Color.black.opacity(0.85) : OdinStyle.secondaryInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isPrimary ? OdinStyle.accent : OdinStyle.warmCream.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isPrimary ?
                        OdinStyle.accent :
                        OdinStyle.warmCream.opacity(0.12),
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CustomGlassButtonStyle {
    static var brandGlass: CustomGlassButtonStyle {
        CustomGlassButtonStyle(cornerRadius: 8, isPrimary: false)
    }
    static func brandGlass(cornerRadius: CGFloat, isPrimary: Bool = false) -> CustomGlassButtonStyle {
        CustomGlassButtonStyle(cornerRadius: cornerRadius, isPrimary: isPrimary)
    }
}

struct ScaleOnHover: ViewModifier {
    @State private var isHovering = false
    var scale: CGFloat = 1.015 // Softened from 1.02

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovering) // Smoother spring transition
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func scaleOnHover(scale: CGFloat = 1.015) -> some View {
        modifier(ScaleOnHover(scale: scale))
    }
}
