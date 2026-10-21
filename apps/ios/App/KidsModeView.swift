import SwiftUI
import FluenceCore

// MARK: - Kids Vocal Hub (Mode Enfant Sécurisé)
public struct KidsVocalHubView: View {
    var coordinator: ConversationCoordinator
    @State private var showingPinUnlock = false
    @State private var showingGuidedAccessInfo = false
    @State private var enteredPin = ""
    @State private var pinError = false
    @State private var selectedTheme: String = "animals"
    @State private var mascotBouncing = false
    @State private var energyLevel: Double = 1.0
    @State private var sessionTimer: Timer?
    @State private var sessionJustEnded = false
    
    let themes: [(id: String, title: String, icon: String, color: Color)] = [
        ("animals", "Animaux 🐶", "pawprint.fill", Color.orange),
        ("colors", "Couleurs 🎨", "paintpalette.fill", Color.pink),
        ("numbers", "Chiffres 🔢", "number.circle.fill", Color.green),
        ("magic", "Magie 🪄", "wand.and.stars", Color.purple),
        ("heroes", "Aventure 🚀", "rocket.fill", Color.blue)
    ]
    
    init(coordinator: ConversationCoordinator) {
        self.coordinator = coordinator
    }
    
    public var body: some View {
        ZStack {
            // Child-friendly warm gradient background
            LinearGradient(
                colors: [Color(hex: "#1A102F"), Color(hex: "#0F172A"), Color(hex: "#090D16")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 16) {
                topKidsBar
                mascotSection
                themeSelectorSection
                speechBubbleSection
                Spacer()
                bigVocalButton
            }
        }
        .sheet(isPresented: $showingPinUnlock) {
            ParentalGateView(coordinator: coordinator, isPresented: $showingPinUnlock)
        }
        .sheet(isPresented: $showingGuidedAccessInfo) {
            GuidedAccessHelpSheet(isPresented: $showingGuidedAccessInfo)
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var topKidsBar: some View {
        HStack {
            // Stars badge
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.title3)
                Text("\(coordinator.store.preferences.kidsStarsCount) étoiles")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            
            Spacer()
            
            // Language Flag Badge
            HStack(spacing: 6) {
                Text(LanguageRegistry.module(for: coordinator.store.preferences.kidsTargetLanguageID)?.flag ?? "🇩🇪")
                    .font(.title3)
                Text(coordinator.store.preferences.kidsChildName.isEmpty ? "Champion" : coordinator.store.preferences.kidsChildName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.indigo.opacity(0.35)))
            
            Spacer()
            
            // Guided Access hint button
            Button {
                showingGuidedAccessInfo = true
            } label: {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            
            // Parental Lock Exit Button
            Button {
                showingPinUnlock = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                    Text("Parent")
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.red.opacity(0.4)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var mascotSection: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 90
                        )
                    )
                    .frame(width: 170, height: 170)
                    .scaleEffect(coordinator.state == .active ? 1.25 : (mascotBouncing ? 1.08 : 1.0))
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: mascotBouncing)
                
                Text(mascotEmoji)
                    .font(.system(size: 82))
                    .scaleEffect(coordinator.state == .active ? 1.15 : (mascotBouncing ? 1.05 : 0.95))
                    .rotationEffect(.degrees(coordinator.state == .active ? 5 : 0))
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: coordinator.state == .active)
            }
            .onAppear { mascotBouncing = true }
            
            Text("Parle avec Fluency !")
                .font(.title2.bold())
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .yellow, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
    
    @ViewBuilder
    private var themeSelectorSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(themes, id: \.id) { theme in
                    Button {
                        selectedTheme = theme.id
                        coordinator.store.updatePreferences { $0.kidsTheme = theme.id }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: theme.icon)
                            Text(theme.title)
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                selectedTheme == theme.id
                                    ? theme.color.opacity(0.7)
                                    : Color.white.opacity(0.08)
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                selectedTheme == theme.id ? Color.white : Color.clear,
                                lineWidth: 1.5
                            )
                        )
                        .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder
    private var speechBubbleSection: some View {
        ScrollView {
            VStack(spacing: 12) {
                if coordinator.caption.isEmpty {
                    emptySpeechBubble
                } else {
                    activeSpeechBubble
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder
    private var activeSpeechBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("🤖 Fluency")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
                Spacer()
                Button {
                    coordinator.replayAudio(coordinator.caption)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
            }
            Text(coordinator.caption)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .lineSpacing(4)
            
            if !coordinator.meaning.isEmpty {
                Text(coordinator.meaning)
                    .font(.subheadline)
                    .foregroundStyle(.yellow.opacity(0.9))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "#241842").opacity(0.95))
        )
    }
    
    @ViewBuilder
    private var emptySpeechBubble: some View {
        Text("Appuie sur le gros micro en bas pour commencer l'aventure vocale !")
            .font(.headline)
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.06))
            )
    }
    
    @ViewBuilder
    private var bigVocalButton: some View {
        Button {
            if coordinator.state == .active {
                coordinator.end()
                coordinator.store.updatePreferences { $0.kidsStarsCount += 1 }
            } else {
                coordinator.store.updatePreferences {
                    $0.pedagogicalMode = "kids"
                    $0.learningLanguageID = $0.kidsTargetLanguageID
                }
                coordinator.start()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        coordinator.state == .active
                            ? LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(hex: "#6366F1"), Color(hex: "#A855F7"), Color(hex: "#EC4899")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 105, height: 105)
                    .shadow(color: (coordinator.state == .active ? Color.red : Color.purple).opacity(0.6), radius: 24, x: 0, y: 10)
                
                Image(systemName: coordinator.state == .active ? "stop.fill" : "mic.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.bottom, 24)
    }
    
    private var mascotEmoji: String {
        switch selectedTheme {
        case "animals": return "🐶"
        case "colors": return "🎨"
        case "numbers": return "🔢"
        case "magic": return "🪄"
        case "heroes": return "🚀"
        default: return "🌟"
        }
    }
}

// MARK: - Guided Access (Accès Restreint Apple) Instructions Sheet
struct GuidedAccessHelpSheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0F172A").ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Accès Guidé iOS")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                                Text("Verrouillez l'iPhone sur Fluence")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(.top, 8)
                        
                        Divider().background(Color.white.opacity(0.15))
                        
                        VStack(alignment: .leading, spacing: 16) {
                            stepRow(number: "1", title: "Activer dans iOS", description: "Ouvrez Réglages ➔ Accessibilité ➔ Accès guidé et activez l'interrupteur.")
                            stepRow(number: "2", title: "Donner le téléphone à l'enfant", description: "Ouvrez Fluence en Mode Enfant sur la leçon choisie.")
                            stepRow(number: "3", title: "Verrouiller en 1 seconde", description: "Appuyez 3 fois rapidement sur le bouton latéral (Power) de votre iPhone et touchez « Démarrer » en haut à droite.")
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("Sécurité Maximale")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            Text("L'enfant ne peut ni quitter l'application, ni voir vos photos, SMS, messages ou autres réglages sans votre Face ID ou code parent.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                        
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Ouvrir Réglages iOS")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(Color.cyan))
                                .foregroundStyle(.black)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") {
                        isPresented = false
                    }
                    .foregroundStyle(.cyan)
                }
            }
        }
    }
    
    private func stepRow(number: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline.bold())
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.indigo))
                .foregroundStyle(.white)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}


