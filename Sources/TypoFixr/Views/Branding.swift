import SwiftUI
import AppKit

enum TypoFixrBrandPalette {
    static let blue = Color(red: 0.14, green: 0.44, blue: 0.93)
    static let teal = Color(red: 0.11, green: 0.72, blue: 0.79)
    static let green = Color(red: 0.12, green: 0.75, blue: 0.45)
    static let slate = Color(red: 0.16, green: 0.20, blue: 0.31)
    static let softBorder = Color.primary.opacity(0.08)
    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let secondaryCardFill = Color(nsColor: .windowBackgroundColor)

    static let gradient = LinearGradient(
        colors: [blue, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct TypoFixrMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(TypoFixrBrandPalette.gradient)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: max(1, size * 0.015))
                )

            RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                .fill(.white.opacity(0.95))
                .frame(width: size * 0.66, height: size * 0.46)
                .offset(y: -size * 0.05)
                .overlay(alignment: .top) {
                    HStack(spacing: size * 0.045) {
                        keyDot
                        keyDot
                        keyDot
                    }
                    .offset(y: size * 0.06)
                }

            Circle()
                .fill(TypoFixrBrandPalette.green)
                .frame(width: size * 0.32, height: size * 0.32)
                .overlay {
                    CheckmarkShape()
                        .stroke(.white, style: StrokeStyle(lineWidth: max(2, size * 0.06), lineCap: .round, lineJoin: .round))
                        .padding(size * 0.1)
                }
                .offset(x: size * 0.23, y: size * 0.22)
                .shadow(color: .black.opacity(0.16), radius: size * 0.06, y: size * 0.035)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.045)
    }

    private var keyDot: some View {
        RoundedRectangle(cornerRadius: size * 0.025, style: .continuous)
            .fill(TypoFixrBrandPalette.slate.opacity(0.22))
            .frame(width: size * 0.09, height: size * 0.04)
    }
}

struct OnboardingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TypoFixrBrandPalette.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TypoFixrBrandPalette.softBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.2))
        return path
    }
}

enum TypoFixrBranding {
    static func menuBarTemplateImage(pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size)
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let lineWidth = max(1.2, pointSize * 0.1)
        let keyRect = NSRect(
            x: pointSize * 0.12,
            y: pointSize * 0.22,
            width: pointSize * 0.58,
            height: pointSize * 0.5
        )
        let keyPath = NSBezierPath(roundedRect: keyRect, xRadius: pointSize * 0.16, yRadius: pointSize * 0.16)
        keyPath.lineWidth = lineWidth
        keyPath.stroke()

        let keyInset = pointSize * 0.07
        for column in 0..<3 {
            let dashRect = NSRect(
                x: keyRect.minX + keyInset + CGFloat(column) * pointSize * 0.14,
                y: keyRect.midY - pointSize * 0.07,
                width: pointSize * 0.08,
                height: pointSize * 0.04
            )
            let dashPath = NSBezierPath(roundedRect: dashRect, xRadius: pointSize * 0.02, yRadius: pointSize * 0.02)
            dashPath.fill()
        }

        let badgeRect = NSRect(
            x: pointSize * 0.54,
            y: pointSize * 0.05,
            width: pointSize * 0.3,
            height: pointSize * 0.3
        )
        NSBezierPath(ovalIn: badgeRect).fill()

        let checkPath = NSBezierPath()
        checkPath.lineWidth = lineWidth
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkPath.move(to: CGPoint(x: badgeRect.minX + badgeRect.width * 0.24, y: badgeRect.midY))
        checkPath.line(to: CGPoint(x: badgeRect.minX + badgeRect.width * 0.44, y: badgeRect.minY + badgeRect.height * 0.24))
        checkPath.line(to: CGPoint(x: badgeRect.maxX - badgeRect.width * 0.2, y: badgeRect.maxY - badgeRect.height * 0.24))
        NSColor.white.setStroke()
        checkPath.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
