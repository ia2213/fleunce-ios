# HANDOFF & MÉMOIRE PROJET : MURAL (Mural-Gemini)

> **Document de reprise automatique / Handoff**  
> Ce document récapitule l'état complet du projet, l'architecture, les secrets/configs, et les procédures pour reprendre le travail sans repartir de zéro.

---

## 1. Vue d'ensemble & Dépôt
- **Nom du projet** : Mural (Mural-Gemini)
- **Dépôt Git** : `https://github.com/ia2213/mural-gemini.git`
- **Branche principale** : `main`
- **Dossier local** : `C:/Users/Marc Hopf/mural_project/repo`
- **Livraison finale IPA** : Bureau client `C:/Users/Marc Hopf/Desktop/Mural-Gemini.ipa` + Bot Telegram `@CerveauPriveeBot` (chat_id: `856614939`)

---

## 2. Architecture & Fonctionnalités Clés

### A. Moteur IA Multi-Fournisseurs (Auto-Failover)
- **3 Fournisseurs configurés** dans `APIClient.swift` & `Models.swift` :
  1. **Groq API** (Par défaut : `qwen/qwen3.8-27b` ou `llama-3.1-8b-instant`)
  2. **Google Gemini API** (`gemini-1.5-flash` / `openai/chat/completions` endpoint)
  3. **Agent Personal Hermes VPS** (`http://<IP-VPS>:20128/v1/chat/completions`)
- **Auto-Failover** : Basculement automatique transparent sur erreurs HTTP 400, 403, 404, 429 (rate limit) et 500+.

### B. Audio & Vocal
- **STT (Reconnaissance)** : Groq Whisper Turbo (`whisper-large-v3-turbo`)
- **TTS (Synthèse)** : Native iOS `AVSpeechSynthesizer` (voix haute qualité `.premium` / `.enhanced`, préécoute, vitesse 0.8x-1.2x).
- **VAD & micro** : Pause automatique du micro pendant le TTS pour éviter les boucles d'auto-réponse.

### C. Interface & Compatibilité
- **iPad Support** : `NavigationSplitView`, layout responsive sidebar/detail, `TARGETED_DEVICE_FAMILY = "1,2"`, orientations complètes.
- **WidgetKit Widgets** : Extension `MuralWidgetExtension` (tailles Small, Medium, Large) connectée via `UserDefaults` partagés (`group.no.william.mural`).
- **Telegram Mini App & Bot** :
  - Mini App : `https://ia2213.github.io/mural-gemini/` (`index.html`)
  - Bot Telegram : `@MuralTeacherBot` avec commandes `/correction`, `/provider`, `/key`.

### D. Niveaux de correction
- Réglable dans l'UI (Réglages / Preferences) : **Fort**, **Moyen**, **Faible** (`correctionLevel` dans `TeachingPolicy.swift`).

---

## 3. Configuration du Build & CI/CD (GitHub Actions)

- **Workflow CI** : `.github/workflows/build-ios.yml`
- **Mécanisme de packaging IPA** :
  - `xcodebuild` génère le binaire Release non signé pour iPhoneOS.
  - Structure de l'IPA :
    ```
    Payload/
    └── Mural.app/
        └── PlugIns/
            └── MuralWidgetExtension.appex
    ```
  - Widget Kit : Inclus dans `PlugIns/` pour apparaître dans le sélecteur de widgets iOS.

---

## 4. Fichiers Clés du Codebase

| Fichier / Repertoire | Rôle |
|---|---|
| `apps/ios/Mural.xcodeproj/project.pbxproj` | Configuration Xcode (Targets `Mural`, `MuralWidgetExtension`, `MuralUITests`). |
| `apps/ios/App/APIClient.swift` | Moteur tri-fournisseurs (Groq, Gemini, Hermes VPS) + Auto-Failover. |
| `apps/ios/App/Models.swift` | Modèles de données (`providerID`, `correctionLevel`, etc.). |
| `apps/ios/Core/TeachingPolicy.swift` | Prompts pédagogiques ajustables selon `correctionLevel`. |
| `apps/ios/App/RootView.swift` | Layout principal iPad (`NavigationSplitView`) et iPhone. |
| `apps/ios/App/Storage.swift` | Stockage et synchro `UserDefaults` partagés pour Widgets. |
| `apps/ios/Widget/MuralWidget.swift` | Code Swift du WidgetKit (Small/Medium/Large). |
| `index.html` | Code source Telegram Mini App (GitHub Pages). |
| `mural_telegram_runner.py` | Bot Python Telegram `@MuralTeacherBot`. |
| `.github/workflows/build-ios.yml` | Pipeline de build automatique et génération d'IPA. |

---

## 5. Guide de Reprise Rapide (Pour l'Agent ou le Développeur)

Si une nouvelle session démarre ou si tu veux relancer/modifier le projet :

1. **Lire ce fichier** : `HANDOFF.md` à la racine du dépôt.
2. **Se placer dans le répertoire** :
   ```bash
   cd "C:/Users/Marc Hopf/mural_project/repo"
   ```
3. **Pousser des modifications & déclencher le build IPA** :
   ```bash
   git add .
   git commit -m "Description de la modif"
   git push origin main
   ```
4. **Récupérer l'IPA compilé** :
   - Automatiquement téléchargé par les scripts Python sur `C:/Users/Marc Hopf/Desktop/Mural-Gemini.ipa` et envoyé sur Telegram au bot.

---
*Dernière mise à jour : 20 Septembre 2026*
