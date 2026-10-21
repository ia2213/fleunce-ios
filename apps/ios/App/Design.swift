import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum FluenceColor {
    static let background = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1.0)
            : UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0)
    })
    static let surface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.13, blue: 0.16, alpha: 1.0)
            : UIColor(white: 1.0, alpha: 1.0)
    })
    static let surfaceSecondary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 1.0)
            : UIColor(red: 0.92, green: 0.94, blue: 0.96, alpha: 1.0)
    })
    static let ink = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 1.0)
            : UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)
    })
    static let secondary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1.0)
            : UIColor(red: 0.42, green: 0.48, blue: 0.56, alpha: 1.0)
    })
    static let accent = Color(red: 0.36, green: 0.48, blue: 0.92) // Calm Apple Indigo
    static let emerald = Color(red: 0.20, green: 0.78, blue: 0.50) // Soft Forest Mint
    static let coral = Color(red: 0.92, green: 0.45, blue: 0.38)
    
    // Legacy mapping to avoid breaking other views immediately
    static let cream = surface
    static let orange = accent
    static let peach = Color(red: 0.85, green: 0.88, blue: 0.95)
    static let lilac = Color(red: 0.80, green: 0.82, blue: 0.95)
    static let sage = Color(red: 0.80, green: 0.90, blue: 0.90)
    static let butter = Color(red: 0.92, green: 0.90, blue: 0.80)
    static let panels = [peach, lilac, sage, butter]
}

struct Brand: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("fluence").font(.system(size: 26, weight: .bold, design: .rounded)).tracking(-1.0)
        }.foregroundStyle(FluenceColor.ink).accessibilityLabel("Fluence")
    }
}

// MARK: - Sober Glass Card Modifier
struct SoftGlass: ViewModifier {
    var tint: Color = .white.opacity(0.45)
    func body(content: Content) -> some View {
        content.background(FluenceColor.surface, in: Capsule())
    }
}

struct OrganicGlass: ViewModifier {
    var cornerRadius: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(FluenceColor.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.08)
                                    : Color.black.opacity(0.06),
                                lineWidth: 1
                            )
                    )
            }
    }
}

extension View {
    func organicGlass(cornerRadius: CGFloat = 20) -> some View {
        self.modifier(OrganicGlass(cornerRadius: cornerRadius))
    }
}

// MARK: - SOBER & CALM VOICE WAVEFORM PRESENCE (Fin des effets agressifs)
struct SoberWaveformView: View {
    var energy: Double = 0
    var isListening: Bool = false
    var isSpeaking: Bool = false
    var onTap: (() -> Void)? = nil
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    
    private let barCount = 5
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45, paused: reduceMotion || scenePhase != .active)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let rawE = min(1.0, max(0.0, energy))
            let dynamicE = reduceMotion ? 0.15 : rawE
            
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                onTap?()
            } label: {
                HStack(spacing: 7) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let phase = Double(index) * 0.75
                        let wave = (isListening || isSpeaking) ? sin(t * 4.5 + phase) : sin(t * 1.8 + phase)
                        let baseHeight: CGFloat = (isListening || isSpeaking)
                            ? 14 + CGFloat(abs(wave)) * 16 + CGFloat(dynamicE * 28)
                            : 8 + CGFloat(abs(wave)) * 8
                        
                        Capsule()
                            .fill(
                                isListening
                                    ? FluenceColor.emerald
                                    : isSpeaking
                                        ? FluenceColor.accent
                                        : FluenceColor.secondary.opacity(0.40)
                            )
                            .frame(width: 5, height: max(6, min(50, baseHeight)))
                    }
                }
                .frame(width: 80, height: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isListening ? "Écoute en cours" : isSpeaking ? "Fluence parle" : "Activer la voix")
        }
    }
}

// MARK: - FluenceAura (Supprimé pour éliminer tout éblouissement)
struct FluenceAura: View {
    var energy: Double = 0
    var listening = false
    var active = true
    
    var body: some View {
        EmptyView()
    }
}

struct WhisperText: View {
    var text: AttributedString
    var isLarge: Bool = false
    
    var body: some View {
        Text(text)
            .font(.system(size: isLarge ? 28 : 17, weight: isLarge ? .bold : .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(isLarge ? FluenceColor.ink : FluenceColor.secondary)
            .animation(.easeInOut(duration: 0.25), value: String(text.characters))
    }
}

struct RecallBars: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in Capsule().fill(index < count ? FluenceColor.accent : FluenceColor.secondary.opacity(0.3)).frame(width: 18, height: 5) }
        }.accessibilityLabel("\(count) of 3 recall bars")
    }
}

struct PageHeading: View {
    var eyebrow: String
    var title: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased()).font(.system(.caption, design: .rounded, weight: .bold)).tracking(1.2).foregroundStyle(FluenceColor.secondary)
            Text(title).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(FluenceColor.ink)
            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(FluenceColor.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
