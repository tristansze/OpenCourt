import SwiftUI

enum Purdue {
    static let black = Color(red: 0.05, green: 0.05, blue: 0.05)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let gold = Color(red: 0.812, green: 0.725, blue: 0.569)
    static let track = Color.white.opacity(0.08)
    static let muted = Color(red: 0.62, green: 0.62, blue: 0.58)

    /// Open courts stay gold. The ring warms toward amber as more courts fill.
    static func usageColor(_ percent: Int) -> Color {
        let t = min(max(Double(percent), 0), 100) / 100
        let open = RGB(0.812, 0.725, 0.569)
        let mid = RGB(0.86, 0.62, 0.28)
        let packed = RGB(0.86, 0.32, 0.18)
        if t < 0.5 {
            return open.mix(mid, amount: t / 0.5).color
        }
        return mid.mix(packed, amount: (t - 0.5) / 0.5).color
    }

    static func usageLabel(_ percent: Int) -> String {
        switch percent {
        case ..<35: "Wide open"
        case ..<70: "Picking up"
        default: "Packed"
        }
    }
}

private struct RGB {
    var red: Double
    var green: Double
    var blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    func mix(_ other: RGB, amount: Double) -> RGB {
        RGB(
            red + (other.red - red) * amount,
            green + (other.green - green) * amount,
            blue + (other.blue - blue) * amount
        )
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

struct UsageRing: View {
    let percent: Int
    var lineWidth: CGFloat = 18
    var showsCaption = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Purdue.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(
                    Purdue.usageColor(percent),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.7), value: percent)
            if showsCaption {
                VStack(spacing: 2) {
                    Text("\(percent)%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("IN USE")
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(Purdue.gold)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent) percent of courts in use")
    }
}

extension View {
    func purdueScreen() -> some View {
        self
            .background(Purdue.black.ignoresSafeArea())
            .tint(Purdue.gold)
            .toolbarBackground(Purdue.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
    }
}
