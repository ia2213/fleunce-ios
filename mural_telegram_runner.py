#!/usr/bin/env python3
"""
Mural Telegram Bot Runner - 100% Self-contained Multi-User Language Teacher
Bot Username: @MuralTeacherBot
Token: 8817348445:AAEK2DaFFzB9IoTQcutlZTwx3cpWp4CM4J4
"""

import os
import sys
import time
import io
import json
import logging
import requests
try:
    from gtts import gTTS
except ImportError:
    gTTS = None

logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO)
logger = logging.getLogger("mural_bot")

BOT_TOKEN = "8817348445:AAEK2DaFFzB9IoTQcutlZTwx3cpWp4CM4J4"
BASE_URL = f"https://api.telegram.org/bot{BOT_TOKEN}"
USER_DATA_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "user_sessions.json")

LANGUAGES = {
    "de": {"name": "Allemand 🇩🇪", "locale": "de", "greeting": "Hallo! Wie geht es dir heute?"},
    "fr": {"name": "Français 🇫🇷", "locale": "fr", "greeting": "Bonjour ! Comment vas-tu aujourd'hui ?"},
    "en-US": {"name": "Anglais (US) 🇺🇸", "locale": "en", "greeting": "Hey there! How are you doing today?"},
    "en-GB": {"name": "Anglais (UK) 🇬🇧", "locale": "en", "greeting": "Hello! How are you today?"},
    "es": {"name": "Espagnol 🇪🇸", "locale": "es", "greeting": "¡Hola! ¿Cómo estás hoy?"},
    "it": {"name": "Italien 🇮🇹", "locale": "it", "greeting": "Ciao! Come stai oggi?"},
    "ro": {"name": "Roumain 🇷🇴", "locale": "ro", "greeting": "Salut! Ce mai faci astăzi?"},
    "ar": {"name": "Arabe 🇸🇦", "locale": "ar", "greeting": "مرحبًا! كيف حالك اليوم؟"},
    "he": {"name": "Hébreu 🇮🇱", "locale": "he", "greeting": "שלום! מה שלומך היום?"},
    "ja": {"name": "Japonais 🇯🇵", "locale": "ja", "greeting": "こんにちは！お元気ですか？"},
    "ru": {"name": "Russe 🇷🇺", "locale": "ru", "greeting": "Привет! Как твои дела сегодня?"},
}

def load_user_db():
    if os.path.exists(USER_DATA_FILE):
        try:
            with open(USER_DATA_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_user_db(db):
    with open(USER_DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(db, f, indent=2, ensure_ascii=False)

user_db = load_user_db()

def get_user_cfg(user_id: str):
    if user_id not in user_db:
        user_db[user_id] = {
            "lang": "de",
            "api_key": "",
            "model": "qwen/qwen3.8-27b",
            "history": []
        }
        save_user_db(user_db)
    return user_db[user_id]

def call_ai_llm(user_id: str, prompt: str) -> str:
    cfg = get_user_cfg(user_id)
    provider_mode = cfg.get("provider", "auto")
    key = cfg.get("api_key") or os.getenv("GROQ_API_KEY", "")
    vps_url = cfg.get("vps_url") or ""
    lang_info = LANGUAGES.get(cfg.get("lang", "de"), LANGUAGES["de"])
    
    corr_level = cfg.get("correction", "medium").lower()
    corr_instruction = {
        "high": "CORRECTION LEVEL: HIGH / STRICT. Actively point out and correct grammar, syntax, vocabulary, and pronunciation mistakes right after the learner finishes speaking.",
        "low": "CORRECTION LEVEL: LOW / MINIMAL. Only correct major errors where meaning is unclear. Focus primarily on conversational flow and encouraging communication.",
        "medium": "CORRECTION LEVEL: MEDIUM / BALANCED. Correct meaningful or recurring errors gently after the learner finishes, maintaining a natural conversation flow."
    }.get(corr_level, "CORRECTION LEVEL: MEDIUM / BALANCED.")

    system_msg = (
        f"You are a friendly language teacher helping the user practice {lang_info['name']}. "
        f"Always reply in {lang_info['name']}. Keep your responses clear, natural, and conversational (1 to 3 sentences max). "
        f"{corr_instruction}"
    )
    
    history = cfg.get("history", [])
    history.append({"role": "user", "content": prompt})
    history = history[-10:]
    cfg["history"] = history
    save_user_db(user_db)
    
    messages = [{"role": "system", "content": system_msg}] + history
    
    attempts = []
    if provider_mode in ("groq", "auto"):
        attempts.append({
            "url": "https://api.groq.com/openai/v1/chat/completions",
            "headers": {"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            "body": {"model": cfg.get("model", "qwen/qwen3.8-27b"), "messages": messages, "max_tokens": 300}
        })
    if provider_mode in ("google", "auto"):
        attempts.append({
            "url": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            "headers": {"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            "body": {"model": "gemini-2.5-flash", "messages": messages, "max_tokens": 300}
        })
    if provider_mode in ("hermes_vps", "auto") and vps_url:
        attempts.append({
            "url": vps_url,
            "headers": {"Content-Type": "application/json"},
            "body": {"model": "auto/best-coding", "messages": messages, "max_tokens": 300}
        })
        
    for attempt in attempts:
        try:
            r = requests.post(attempt["url"], headers=attempt["headers"], json=attempt["body"], timeout=20)
            if r.status_code == 200:
                text = r.json()["choices"][0]["message"]["content"]
                history.append({"role": "assistant", "content": text})
                cfg["history"] = history[-10:]
                save_user_db(user_db)
                return text
        except Exception as e:
            logger.warning(f"Provider {attempt['url']} failed: {e}")
            
    return "Désolé, impossible de se connecter aux IA (Groq, Gemini, VPS). Vérifie ta clé API avec /key."

def transcribe_whisper(user_id: str, audio_bytes: bytes) -> str:
    cfg = get_user_cfg(user_id)
    key = cfg.get("api_key") or os.getenv("GROQ_API_KEY", "")
    lang_code = cfg.get("lang", "de").split("-")[0]
    
    url = "https://api.groq.com/openai/v1/audio/transcriptions"
    headers = {"Authorization": f"Bearer {key}"}
    files = {"file": ("voice.ogg", audio_bytes, "audio/ogg")}
    data = {"model": "whisper-large-v3-turbo", "language": lang_code}
    
    try:
        r = requests.post(url, headers=headers, files=files, data=data, timeout=30)
        if r.status_code == 200:
            return r.json().get("text", "").strip()
        return ""
    except Exception as e:
        logger.error(f"Whisper STT error: {e}")
        return ""

def generate_tts_voice(text: str, lang: str) -> bytes:
    if gTTS is not None:
        code = lang.split("-")[0]
        tts = gTTS(text=text, lang=code, slow=False)
        fp = io.BytesIO()
        tts.write_to_fp(fp)
        fp.seek(0)
        return fp.read()
    return b""

def send_message(chat_id: int, text: str, reply_markup=None):
    payload = {"chat_id": chat_id, "text": text, "parse_mode": "Markdown"}
    if reply_markup:
        payload["reply_markup"] = reply_markup
    requests.post(f"{BASE_URL}/sendMessage", json=payload)

def broadcast_announcement(announcement_text: str) -> int:
    db = load_user_db()
    sent_count = 0
    formatted = f"🚀 *NOUVELLE MISE À JOUR MURAL v1.0.0*\n\n{announcement_text}\n\n📱 _Consultez la Mini App ou tapez /start pour voir les nouveautés !_"
    for uid in list(db.keys()):
        try:
            cid = int(uid)
            send_message(cid, formatted)
            sent_count += 1
        except Exception as e:
            logger.error(f"Could not send announcement to user {uid}: {e}")
    return sent_count

def send_voice(chat_id: int, voice_bytes: bytes, caption=""):
    files = {"voice": ("voice.ogg", voice_bytes, "audio/ogg")}
    data = {"chat_id": chat_id, "caption": caption}
    requests.post(f"{BASE_URL}/sendVoice", data=data, files=files)

def build_language_keyboard():
    inline_keyboard = [
        [{"text": "🚀 Ouvrir la Mini App Mural", "web_app": {"url": "https://ia2213.github.io/mural-gemini/"}}]
    ]
    row = []
    for code, info in LANGUAGES.items():
        row.append({"text": info["name"], "callback_data": f"lang_{code}"})
        if len(row) == 2:
            inline_keyboard.append(row)
            row = []
    if row:
        inline_keyboard.append(row)
    return {"inline_keyboard": inline_keyboard}

def handle_update(update):
    if "message" in update:
        msg = update["message"]
        chat_id = msg["chat"]["id"]
        user_id = str(msg["from"]["id"])
        cfg = get_user_cfg(user_id)
        
        text = msg.get("text", "")
        
        if text.startswith("/start") or text.startswith("/setup"):
            kb = build_language_keyboard()
            welcome = (
                "👋 *Bienvenue sur @MuralTeacherBot !*\n\n"
                "Je suis ton professeur de langue virtuel propulsé par l'API Groq.\n\n"
                "1️⃣ **Sélectionne la langue que tu souhaites pratiquer ci-dessous :**\n"
                "2️⃣ Tu peux ajouter ta propre clé API Groq avec `/key gsk_...`"
            )
            send_message(chat_id, welcome, reply_markup=kb)
            return
            
        if text.startswith("/key"):
            parts = text.split(maxsplit=1)
            if len(parts) > 1 and parts[1].strip().startswith("gsk_"):
                cfg["api_key"] = parts[1].strip()
                save_user_db(user_db)
                send_message(chat_id, "🔒 *Ta clé API Groq a été enregistrée en toute sécurité !*")
            else:
                send_message(chat_id, "Pour enregistrer ta propre clé Groq, envoie :\n`/key gsk_ton_token`")
            return

        if text.startswith("/correction"):
            kb = {
                "inline_keyboard": [
                    [{"text": "🔴 Fort / Strict (Corrige tout)", "callback_data": "corr_high"}],
                    [{"text": "🟡 Moyen / Équilibré (Naturel)", "callback_data": "corr_medium"}],
                    [{"text": "🟢 Faible / Fluide (Erreurs majeures)", "callback_data": "corr_low"}]
                ]
            }
            send_message(chat_id, "🎯 *Choisis ton niveau de correction :*", reply_markup=kb)
            return

        if text.startswith("/provider"):
            kb = {
                "inline_keyboard": [
                    [{"text": "⚡ Auto (Groq → Gemini → VPS)", "callback_data": "prov_auto"}],
                    [{"text": "🚀 Groq API", "callback_data": "prov_groq"}],
                    [{"text": "✨ Google Gemini API", "callback_data": "prov_google"}],
                    [{"text": "🤖 Mon Agent Hermes VPS", "callback_data": "prov_hermes_vps"}]
                ]
            }
            send_message(chat_id, "🤖 *Choisis ton moteur d'IA :*", reply_markup=kb)
            return

        if text.startswith("/voice") or text.startswith("/tts"):
            kb = {
                "inline_keyboard": [
                    [{"text": "🗣️ Voix Standard / Native (gTTS)", "callback_data": "tts_standard"}],
                    [{"text": "✨ Voix Google Gemini (IA Audio API)", "callback_data": "tts_gemini"}]
                ]
            }
            send_message(chat_id, "🎙️ *Choisis ton moteur de synthèse vocale :*", reply_markup=kb)
            return

        if text.startswith("/announce") or text.startswith("/broadcast"):
            parts = text.split(maxsplit=1)
            if len(parts) > 1:
                content = parts[1].strip()
                count = broadcast_announcement(content)
                send_message(chat_id, f"✅ *Annonce de mise à jour envoyée à {count} utilisateur(s) !*")
            else:
                send_message(chat_id, "📢 *Usage :* `/announce Les nouveautés de la mise à jour...`")
            return
            
        if "voice" in msg:
            file_id = msg["voice"]["file_id"]
            r_file = requests.get(f"{BASE_URL}/getFile?file_id={file_id}").json()
            if r_file.get("ok"):
                file_path = r_file["result"]["file_path"]
                audio_url = f"https://api.telegram.org/file/bot{BOT_TOKEN}/{file_path}"
                audio_bytes = requests.get(audio_url).content
                
                # Transcribe with Groq Whisper Turbo
                transcript = transcribe_whisper(user_id, audio_bytes)
                if transcript:
                    send_message(chat_id, f"📝 *Transcription :* \"{transcript}\"")
                    reply = call_ai_llm(user_id, transcript)
                    send_message(chat_id, reply)
                    try:
                        tts_bytes = generate_tts_voice(reply, cfg.get("lang", "de"))
                        send_voice(chat_id, tts_bytes, caption="🔊 Réponse vocale")
                    except Exception as e:
                        logger.error(f"TTS error: {e}")
                else:
                    send_message(chat_id, "⚠️ Je n'ai pas pu entendre ton message vocal. Essaie de reparler clairement !")
            return
            
        if text and not text.startswith("/"):
            reply = call_ai_llm(user_id, text)
            send_message(chat_id, reply)
            try:
                tts_bytes = generate_tts_voice(reply, cfg.get("lang", "de"))
                send_voice(chat_id, tts_bytes, caption="🔊 Écoute la prononciation")
            except Exception as e:
                logger.error(f"TTS error: {e}")
                
    elif "callback_query" in update:
        cq = update["callback_query"]
        cq_id = cq["id"]
        chat_id = cq["message"]["chat"]["id"]
        user_id = str(cq["from"]["id"])
        data = cq.get("data", "")
        
        requests.post(f"{BASE_URL}/answerCallbackQuery", json={"callback_query_id": cq_id})
        
        if data.startswith("lang_"):
            lang_code = data[5:]
            cfg = get_user_cfg(user_id)
            cfg["lang"] = lang_code
            cfg["history"] = []
            save_user_db(user_db)
            
            info = LANGUAGES.get(lang_code, LANGUAGES["de"])
            send_message(
                chat_id,
                f"✅ *Langue sélectionnée : {info['name']}*\n\n"
                f"Professeur : _{info['greeting']}_\n\n"
                f"Dis-moi quelque chose par texte ou envoie un **message vocal** 🎙️ !"
            )
        elif data.startswith("corr_"):
            corr_val = data[5:]
            cfg = get_user_cfg(user_id)
            cfg["correction"] = corr_val
            save_user_db(user_db)
            labels = {"high": "🔴 Fort / Strict", "medium": "🟡 Moyen / Équilibré", "low": "🟢 Faible / Fluide"}
            send_message(chat_id, f"✅ *Niveau de correction mis à jour : {labels.get(corr_val, corr_val)}*")
        elif data.startswith("prov_"):
            prov_val = data[5:]
            cfg = get_user_cfg(user_id)
            cfg["provider"] = prov_val
            save_user_db(user_db)
            labels = {"auto": "⚡ Auto (Groq → Gemini → VPS)", "groq": "🚀 Groq API", "google": "✨ Google Gemini API", "hermes_vps": "🤖 Mon Agent Hermes VPS"}
            send_message(chat_id, f"✅ *Moteur d'IA mis à jour : {labels.get(prov_val, prov_val)}*")
        elif data.startswith("tts_"):
            tts_val = data[4:]
            cfg = get_user_cfg(user_id)
            cfg["tts_engine"] = tts_val
            save_user_db(user_db)
            labels = {"standard": "🗣️ Voix Standard / Native", "gemini": "✨ Voix Google Gemini (IA Audio API)"}
            send_message(chat_id, f"✅ *Moteur vocal mis à jour : {labels.get(tts_val, tts_val)}*")

def main():
    logger.info("Starting Mural Telegram Bot polling loop...")
    offset = 0
    while True:
        try:
            r = requests.get(f"{BASE_URL}/getUpdates?offset={offset}&timeout=20", timeout=25)
            if r.status_code == 200:
                updates = r.json().get("result", [])
                for u in updates:
                    offset = max(offset, u["update_id"] + 1)
                    try:
                        handle_update(u)
                    except Exception as ex:
                        logger.error(f"Error handling update: {ex}")
            else:
                time.sleep(3)
        except Exception as e:
            logger.error(f"Polling loop exception: {e}")
            time.sleep(3)

if __name__ == "__main__":
    main()
