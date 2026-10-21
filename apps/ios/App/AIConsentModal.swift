import SwiftUI
import FluenceCore

// MARK: - AI Consent Modal (Ticket 3)

struct AIConsentModalView: View {
    let agree: () -> Void
    let decline: () -> Void
    var store: LearningStore

    private var preferences: Preferences { store.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer().frame(height: 8)

            // Icône
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(FluenceColor.accent)
                .padding(.bottom, 4)

            // Titre
            Text("Consentement au traitement par IA")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .accessibilityIdentifier("ai-consent-title")

            // Fournisseur sélectionné
            VStack(alignment: .leading, spacing: 6) {
                Text("Fournisseur IA sélectionné :")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(FluenceColor.secondary)
                Text(providerDisplayName)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(FluenceColor.ink)
                    .lineLimit(2)
                if !endpointDisplay.isEmpty {
                    Text(endpointDisplay)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(FluenceColor.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 4)

            Divider()
                .background(Color.white.opacity(0.08))

            // Données envoyées
            VStack(alignment: .leading, spacing: 10) {
                Text("Données transmises au fournisseur :")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(FluenceColor.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    BulletText(text: "Votre texte de conversation (messages, réponses et corrections)")
                    BulletText(text: audioSentText)
                }
                .font(.system(.body, design: .rounded))
                .foregroundStyle(FluenceColor.ink)
            }

            // Mention tiers
            Text("Ces données peuvent être traitées par le fournisseur tiers sélectionné selon ses propres politiques de confidentialité. Fluence ne stocke pas l’audio brut sur ses serveurs.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(FluenceColor.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            // Boutons
            VStack(spacing: 12) {
                Button("J’accepte", action: agree)
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(FluenceColor.accent, in: Capsule())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("ai-consent-accept")

                Button("Refuser / Modifier", action: decline)
                    .font(.system(.subheadline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .foregroundStyle(FluenceColor.secondary)
                    .accessibilityIdentifier("ai-consent-decline")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
        .padding(28)
        .foregroundStyle(FluenceColor.ink)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FluenceColor.background)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    // MARK: - Provider info

    private var providerDisplayName: String {
        let id = preferences.providerID.lowercased()
        switch id {
        case "groq": return "Groq (Ultra-Rapide)"
        case "openai": return "OpenAI (GPT-4o / o1)"
        case "anthropic": return "Anthropic (Claude 3.5)"
        case "google", "gemini": return "Google Gemini (2.0 Flash)"
        case "deepseek": return "DeepSeek (V3 / R1)"
        case "mistral": return "Mistral AI (Large / Small)"
        case "openrouter": return "OpenRouter (100+ modèles)"
        case "hermes_vps", "hermes": return "VPS Personnel (Hermes)"
        case "custom": return "Serveur personnalisé"
        default: return "Auto (sélection automatique)"
        }
    }

    private var endpointDisplay: String {
        let id = preferences.providerID.lowercased()
        switch id {
        case "groq": return "api.groq.com/openai/v1"
        case "openai": return "api.openai.com/v1"
        case "anthropic": return "api.anthropic.com/v1"
        case "google", "gemini": return "generativelanguage.googleapis.com"
        case "deepseek": return "api.deepseek.com"
        case "mistral": return "api.mistral.ai/v1"
        case "openrouter": return "openrouter.ai/api/v1"
        case "hermes_vps", "hermes":
            if !preferences.vpsEndpoint.isEmpty {
                return preferences.vpsEndpoint
            }
            return "hermes-agent.nousresearch.com"
        case "custom":
            if !preferences.customEndpoint.isEmpty {
                return preferences.customEndpoint
            }
            return "(non configuré)"
        default: return "(auto)"
        }
    }

    private var audioSentText: String {
        if preferences.ttsEngine == "ios" {
            return "Votre audio vocal (si le mode vocal est activé)"
        }
        return "Aucun audio vocal (mode textuel uniquement)"
    }
}

// MARK: - Bullet text helper

private struct BulletText: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Text("•")
                .foregroundStyle(FluenceColor.accent)
            Text(text)
        }
    }
}
