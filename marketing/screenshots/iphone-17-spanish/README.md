# Fleunce screenshots — Spanish

Four original PNG captures from the iPhone 17 simulator, iOS 26.4, at 1206 × 2622 pixels. Captured 12 September 2026 with a 09:41 status bar, full signal and full battery. No device frame, resizing or image retouching.

1. **01-hola.png** — Spanish greeting and voice controls.
2. **02-conversacion.png** — Sample café conversation with English meaning subtitles.
3. **03-temas.png** — Spanish learning module’s theme selection.
4. **04-palabras.png** — Sample Spanish vocabulary showing all three recall strengths.

The interface and meanings remain in English, as in the current app. Dialogue and vocabulary are sample data supplied through a simulator-only debug preview, not the owner’s personal conversations or measured learning progress. The preview makes no API requests.

To reproduce, build the Debug simulator target, then launch with `--preview --screenshot=greeting`, `conversation`, `themes`, or `words` as the screenshot value. Capture through `xcrun simctl io <simulator-id> screenshot <absolute-output-path>`.
