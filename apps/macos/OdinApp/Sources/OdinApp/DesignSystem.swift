import SwiftUI
import AppKit

enum OdinStyle {
    static let accent = Color.white
    static let gold = accent

    static let green = Color(red: 0.20, green: 0.83, blue: 0.55)
    static let red = Color(red: 0.92, green: 0.42, blue: 0.40)

    static let ink = Color.white.opacity(0.96)
    static let secondaryInk = Color.white.opacity(0.78)
    static let tertiaryInk = Color.white.opacity(0.55)
    static let separator = Color.white.opacity(0.10)

    static let panelRadius: CGFloat = 22
    static let cardRadius: CGFloat = 10
    static let chipRadius: CGFloat = 11

    static let cardFill = Color.white.opacity(0.04)
    static let cardFillHover = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.08)
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
        let strokeColor: Color = {
            if isIdle { return Color.white.opacity(0.34) }
            if isAccented { return Color.white.opacity(0.22) }
            return Color.white.opacity(0.12)
        }()
        let strokeWidth: CGFloat = isIdle ? 1.2 : 0.7

        return content
            .glassEffect(.regular, in: NotchShape(cornerRadius: cornerRadius))
            .overlay(
                NotchBorder(cornerRadius: cornerRadius)
                    .stroke(strokeColor, lineWidth: strokeWidth)
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
            .foregroundStyle(OdinStyle.ink)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OdinStyle.ink)
            .glassEffect(
                .regular.interactive(),
                in: .rect(cornerRadius: 7)
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}
