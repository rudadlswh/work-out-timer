import SwiftUI

struct TimerBackgroundView: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [TimerTheme.backgroundTop, TimerTheme.backgroundBottom]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    gradient: Gradient(colors: [TimerTheme.backgroundGlowWarm.opacity(0.35), .clear]),
                    center: .topLeading,
                    startRadius: 24,
                    endRadius: max(size.width, size.height) * 0.75
                )

                RadialGradient(
                    gradient: Gradient(colors: [TimerTheme.backgroundGlowCool.opacity(0.25), .clear]),
                    center: .bottomTrailing,
                    startRadius: 24,
                    endRadius: max(size.width, size.height) * 0.7
                )

                diagonalStripes
                    .frame(width: size.width * 1.6, height: size.height * 1.6)
                    .rotationEffect(.degrees(-12))
                    .offset(x: -size.width * 0.2, y: -size.height * 0.1)
                    .blendMode(.softLight)
                    .opacity(0.6)

                BarbellSilhouette()
                    .frame(width: size.width * 0.9, height: size.height * 0.16)
                    .foregroundStyle(Color.white.opacity(0.08))
                    .rotationEffect(.degrees(-8))
                    .position(x: size.width * 0.55, y: size.height * 0.28)

                Circle()
                    .stroke(TimerTheme.backgroundStripe, lineWidth: 1)
                    .frame(width: size.width * 0.72, height: size.width * 0.72)
                    .position(x: size.width * 0.84, y: size.height * 0.68)
            }
        }
        .ignoresSafeArea()
    }

    private var diagonalStripes: some View {
        Canvas { context, size in
            let stripeWidth: CGFloat = 12
            let stripeSpacing: CGFloat = 26
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.addRect(CGRect(x: x, y: 0, width: stripeWidth, height: size.height * 2))
                x += stripeSpacing
            }
            context.fill(path, with: .color(TimerTheme.backgroundStripe))
        }
    }
}

struct BarbellSilhouette: View {
    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let w = proxy.size.width
            let plateWidth = w * 0.06
            let innerPlateWidth = w * 0.04
            let barWidth = w * 0.6
            let plateHeight = h * 0.9
            let innerPlateHeight = h * 0.65
            let barHeight = max(CGFloat(6), h * 0.18)

            HStack(spacing: w * 0.02) {
                RoundedRectangle(cornerRadius: barHeight * 0.4)
                    .frame(width: plateWidth, height: plateHeight)
                RoundedRectangle(cornerRadius: barHeight * 0.4)
                    .frame(width: innerPlateWidth, height: innerPlateHeight)
                Capsule()
                    .frame(width: barWidth, height: barHeight)
                RoundedRectangle(cornerRadius: barHeight * 0.4)
                    .frame(width: innerPlateWidth, height: innerPlateHeight)
                RoundedRectangle(cornerRadius: barHeight * 0.4)
                    .frame(width: plateWidth, height: plateHeight)
            }
            .frame(width: w, height: h)
        }
    }
}
