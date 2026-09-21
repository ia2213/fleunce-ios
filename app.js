/**
 * Fleunce Teacher · Telegram Mini App Frontend
 * Powered by Telegram WebApp SDK + UI/UX Pro Max
 * Works seamlessly on local server AND standalone GitHub Pages!
 */

// Embedded Data (Offline / GitHub Pages Fallback)
const EMBEDDED_LANGUAGES = [
  { id: 'de', code: 'de-DE', flag: '🇩🇪', name: 'Allemand', nativeName: 'Deutsch' },
  { id: 'es', code: 'es-ES', flag: '🇪🇸', name: 'Espagnol', nativeName: 'Español' },
  { id: 'en', code: 'en-US', flag: '🇬🇧', name: 'Anglais', nativeName: 'English' },
  { id: 'fr', code: 'fr-FR', flag: '🇫🇷', name: 'Français', nativeName: 'Français' },
  { id: 'it', code: 'it-IT', flag: '🇮🇹', name: 'Italien', nativeName: 'Italiano' },
  { id: 'pt', code: 'pt-BR', flag: '🇧🇷', name: 'Portugais', nativeName: 'Português' },
  { id: 'nb', code: 'nb-NO', flag: '🇳🇴', name: 'Norvégien', nativeName: 'Norsk' },
  { id: 'zh', code: 'zh-CN', flag: '🇨🇳', name: 'Chinois', nativeName: '中文' },
  { id: 'ro', code: 'ro-RO', flag: '🇷🇴', name: 'Roumain', nativeName: 'Română' },
  { id: 'ar', code: 'ar-SA', flag: '🇸🇦', name: 'Arabe', nativeName: 'العربية' },
  { id: 'ru', code: 'ru-RU', flag: '🇷🇺', name: 'Russe', nativeName: 'Русский' },
  { id: 'ja', code: 'ja-JP', flag: '🇯🇵', name: 'Japonais', nativeName: '日本語' }
];

const EMBEDDED_THEMES = [
  { id: 'free_talk', category: 'daily', icon: '💭', name: 'Conversation Libre', desc: 'Discutez librement de votre journée, de vos projets ou de vos passions.' },
  { id: 'cafe_restaurant', category: 'daily', icon: '☕', name: 'Au Café & Restaurant', desc: 'Commandez des plats, demandez l’addition et parlez de gastronomie.' },
  { id: 'supermarket', category: 'daily', icon: '🛒', name: 'Au Supermarché', desc: 'Faites vos courses, demandez le rayon et comparez les prix.' },
  { id: 'housing_visit', category: 'daily', icon: '🏠', name: 'Visite de Logement', desc: 'Visitez un appartement, posez des questions sur le bail et le loyer.' },
  { id: 'hospital_consultation', category: 'professional', icon: '🏥', name: 'Consultation Médicale', desc: 'Anamnèse, symptômes, diagnostic et conseils thérapeutiques (idéal médecine / ECN).' },
  { id: 'job_interview', category: 'professional', icon: '💼', name: 'Entretien d’Embauche', desc: 'Présentez vos compétences, votre motivation et répondez aux questions du recruteur.' },
  { id: 'phone_call', category: 'professional', icon: '📞', name: 'Appel Téléphonique', desc: 'Prenez rendez-vous, demandez des renseignements et laissez un message.' },
  { id: 'project_meeting', category: 'professional', icon: '🤝', name: 'Réunion & Présentation', desc: 'Présentez une idée, argumentez et débattez avec votre équipe.' },
  { id: 'airport_customs', category: 'travel', icon: '✈️', name: 'Aéroport & Douane', desc: 'Enregistrement des bagages, contrôle de sécurité et formalités.' },
  { id: 'hotel_checkin', category: 'travel', icon: '🏨', name: 'Hôtel & Réservation', desc: 'Check-in, demandes particulières, services et réclamations.' },
  { id: 'city_directions', category: 'travel', icon: '🗺️', name: 'Demander son Chemin', desc: 'Orientation en ville, transports en commun et monuments.' },
  { id: 'cinema_series', category: 'culture', icon: '🎬', name: 'Cinéma & Séries', desc: 'Critiques de films, recommandations et analyses de scénarios.' },
  { id: 'news_debate', category: 'culture', icon: '🌍', name: 'Débats & Actualités', desc: 'Exprimez votre opinion sur les grands sujets de société.' }
];

// Initialize Telegram WebApp
const tg = window.Telegram?.WebApp;
if (tg) {
  try {
    tg.ready();
    tg.expand();
    if (tg.setHeaderColor) tg.setHeaderColor('#090d16');
    if (tg.setBackgroundColor) tg.setBackgroundColor('#090d16');
  } catch (e) {}
}

// Global State
let currentUser = {
  user_id: tg?.initDataUnsafe?.user?.id || 856614939,
  first_name: tg?.initDataUnsafe?.user?.first_name || 'Ami',
  learning_lang: 'de',
  level: 'B2',
  current_theme: 'free_talk',
  streak_days: 7,
  auto_audio: 0,
  show_subtitles: 1
};

let languagesList = EMBEDDED_LANGUAGES;
let themesList = EMBEDDED_THEMES;
let dueWordsList = [];
let allWordsList = [];
let currentSrsIndex = 0;
let isRecording = false;
let mediaRecorder = null;
let audioChunks = [];
let currentAudioElement = null;

// Haptic feedback
function haptic(type = 'light') {
  try {
    if (tg?.HapticFeedback) {
      if (type === 'light') tg.HapticFeedback.impactOccurred('light');
      if (type === 'medium') tg.HapticFeedback.impactOccurred('medium');
      if (type === 'heavy') tg.HapticFeedback.impactOccurred('heavy');
      if (type === 'success') tg.HapticFeedback.notificationOccurred('success');
      if (type === 'warning') tg.HapticFeedback.notificationOccurred('warning');
    }
  } catch (e) {}
}

// Lifecycle: DOM Ready
document.addEventListener('DOMContentLoaded', async () => {
  loadSavedPreferences();
  loadApiKeySettings();
  await loadUserData();
  await loadLanguages();
  await loadThemes();
  await loadSrsDueWords();
  renderInitialMessage();

  document.getElementById('chatInput')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      sendTextMessage();
    }
  });
});

// Load API Key Settings
function loadApiKeySettings() {
  try {
    const key = localStorage.getItem('fleunce_groq_api_key') || currentUser.groq_api_key || '';
    const model = localStorage.getItem('fleunce_groq_model') || currentUser.groq_model || 'llama-3.3-70b-versatile';
    const provider = localStorage.getItem('fleunce_api_provider') || 'groq';

    const keyInput = document.getElementById('apiKeyInput');
    if (keyInput && key) keyInput.value = key;

    const modelSelect = document.getElementById('aiModelSelect');
    if (modelSelect && model) modelSelect.value = model;

    const providerSelect = document.getElementById('apiProviderSelect');
    if (providerSelect && provider) {
      providerSelect.value = provider;
      handleProviderChange();
    }
  } catch (e) {}
}

// Handle Provider Change
function handleProviderChange() {
  const provider = document.getElementById('apiProviderSelect')?.value || 'groq';
  const keyContainer = document.getElementById('apiKeyInputContainer');
  const keyHint = document.getElementById('apiKeyHint');
  const docLink = document.getElementById('apiKeyDocLink');
  const modelSelect = document.getElementById('aiModelSelect');

  if (provider === 'local') {
    if (keyContainer) keyContainer.classList.add('hidden');
    if (modelSelect) {
      modelSelect.innerHTML = `
        <option value="auto/fast">Auto Fast (OmniRoute)</option>
        <option value="auto/smart">Auto Smart (Haute précision)</option>
        <option value="auto/best-chat">Auto Best Chat</option>
      `;
    }
  } else if (provider === 'gemini') {
    if (keyContainer) keyContainer.classList.remove('hidden');
    if (keyHint) keyHint.textContent = 'AIzaSy...';
    if (docLink) docLink.innerHTML = 'Obtenez une clé sur <a href="https://aistudio.google.com" target="_blank" class="text-sky-400 underline">aistudio.google.com</a>';
    if (modelSelect) {
      modelSelect.innerHTML = `
        <option value="gemini-2.5-flash">Gemini 2.5 Flash</option>
        <option value="gemini-1.5-flash">Gemini 1.5 Flash</option>
        <option value="gemini-2.5-pro">Gemini 2.5 Pro</option>
      `;
    }
  } else if (provider === 'openai') {
    if (keyContainer) keyContainer.classList.remove('hidden');
    if (keyHint) keyHint.textContent = 'sk-...';
    if (docLink) docLink.innerHTML = 'Obtenez une clé sur <a href="https://platform.openai.com" target="_blank" class="text-sky-400 underline">platform.openai.com</a>';
    if (modelSelect) {
      modelSelect.innerHTML = `
        <option value="gpt-4o">GPT-4o (OpenAI)</option>
        <option value="gpt-4o-mini">GPT-4o Mini</option>
      `;
    }
  } else {
    // Groq default
    if (keyContainer) keyContainer.classList.remove('hidden');
    if (keyHint) keyHint.textContent = 'gsk_...';
    if (docLink) docLink.innerHTML = 'Obtenez une clé gratuite sur <a href="https://console.groq.com/keys" target="_blank" class="text-sky-400 underline">console.groq.com</a>';
    if (modelSelect) {
      modelSelect.innerHTML = `
        <option value="llama-3.3-70b-versatile">Llama 3.3 70B Versatile (Recommandé - Pédagogie & Nuances)</option>
        <option value="llama-3.1-8b-instant">Llama 3.1 8B Instant (Ultra rapide)</option>
        <option value="mixtral-8x7b-32768">Mixtral 8x7B (Polyglotte)</option>
        <option value="gemma2-9b-it">Gemma 2 9B IT (Google)</option>
      `;
    }
  }
}

// Toggle API Key Visibility
function toggleApiKeyVisibility() {
  const input = document.getElementById('apiKeyInput');
  const icon = document.getElementById('apiKeyEyeIcon');
  if (input) {
    if (input.type === 'password') {
      input.type = 'text';
      if (icon) icon.textContent = '🙈';
    } else {
      input.type = 'password';
      if (icon) icon.textContent = '👁️';
    }
  }
}

// Save API Key Settings
async function saveApiKeySettings() {
  haptic('medium');
  const provider = document.getElementById('apiProviderSelect')?.value || 'groq';
  const key = document.getElementById('apiKeyInput')?.value?.trim() || '';
  const model = document.getElementById('aiModelSelect')?.value || 'llama-3.3-70b-versatile';

  localStorage.setItem('fleunce_api_provider', provider);
  localStorage.setItem('fleunce_groq_api_key', key);
  localStorage.setItem('fleunce_groq_model', model);

  currentUser.groq_api_key = key;
  currentUser.groq_model = model;

  // Sync with backend
  try {
    await fetch('/api/user/settings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        user_id: currentUser.user_id,
        setting: 'groq_api_key',
        value: key
      })
    });
    await fetch('/api/user/settings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        user_id: currentUser.user_id,
        setting: 'groq_model',
        value: model
      })
    });
  } catch (e) {}

  const msg = document.getElementById('apiKeyStatusMsg');
  if (msg) {
    msg.textContent = '✅ Clé API et modèle enregistrés avec succès !';
    msg.classList.remove('hidden');
    setTimeout(() => msg.classList.add('hidden'), 4000);
  }
}

// Load preferences from localStorage
function loadSavedPreferences() {
  try {
    const saved = localStorage.getItem('fleunce_user_prefs');
    if (saved) {
      currentUser = { ...currentUser, ...JSON.parse(saved) };
    }
  } catch (e) {}
}

// Save preferences to localStorage
function savePreferences() {
  try {
    localStorage.setItem('fleunce_user_prefs', JSON.stringify(currentUser));
  } catch (e) {}
}

// Load User Data
async function loadUserData() {
  try {
    const res = await fetch(`/api/user?user_id=${currentUser.user_id}`);
    if (res.ok) {
      const data = await res.json();
      currentUser = { ...currentUser, ...data.user };
    }
  } catch (err) {
    // Standalone mode: fallback
  }
  updateHeaderUI();
}

// Update Header UI
function updateHeaderUI() {
  const flags = { de: '🇩🇪', es: '🇪🇸', en: '🇬🇧', fr: '🇫🇷', it: '🇮🇹', pt: '🇧🇷', nb: '🇳🇴', zh: '🇨🇳', ro: '🇷🇴', ar: '🇸🇦', ru: '🇷🇺', ja: '🇯🇵' };
  const flag = flags[currentUser.learning_lang] || '🇩🇪';
  
  const flagEl = document.getElementById('headerLangFlag');
  if (flagEl) flagEl.textContent = flag;

  const badgeEl = document.getElementById('headerLevelBadge');
  if (badgeEl) badgeEl.textContent = currentUser.level || 'B2';

  const themeObj = themesList.find(t => t.id === currentUser.current_theme);
  const scenarioEl = document.getElementById('headerScenario');
  if (scenarioEl) scenarioEl.textContent = themeObj ? `${themeObj.icon} ${themeObj.name}` : '☕ Conversation Libre';

  const streakEl = document.getElementById('headerStreak');
  if (streakEl) streakEl.textContent = `${currentUser.streak_days || 7} j`;

  const streakValEl = document.getElementById('statsStreakVal');
  if (streakValEl) streakValEl.textContent = `${currentUser.streak_days || 7} Jours 🔥`;

  const levelValEl = document.getElementById('statsLevelVal');
  if (levelValEl) levelValEl.textContent = currentUser.level || 'B2';
}

// Tab Switcher
function switchTab(tabId) {
  haptic('light');
  document.querySelectorAll('.tab-content').forEach(el => el.classList.add('hidden'));
  document.querySelectorAll('.nav-btn').forEach(el => {
    el.classList.remove('text-sky-400');
    el.classList.add('text-slate-400');
  });

  const activeTab = document.getElementById(`tab-${tabId}`);
  if (activeTab) activeTab.classList.remove('hidden');

  const activeNav = document.getElementById(`nav-${tabId}`);
  if (activeNav) {
    activeNav.classList.remove('text-slate-400');
    activeNav.classList.add('text-sky-400');
  }

  if (tabId === 'srs') {
    loadSrsDueWords();
  }
}

// Living Fleunce Orb Controller
function setOrbState(state) {
  const orb = document.getElementById('fleunceOrb');
  const wave1 = document.getElementById('orbWave1');
  const wave2 = document.getElementById('orbWave2');
  const status = document.getElementById('orbStatus');
  const subStatus = document.getElementById('orbSubStatus');
  const icon = document.getElementById('orbIcon');

  if (state === 'listening') {
    orb?.classList.add('scale-110');
    wave1?.classList.add('wave-active-1');
    wave2?.classList.add('wave-active-2');
    if (status) status.textContent = "Je vous écoute...";
    if (subStatus) subStatus.textContent = "Parlez maintenant (relâchez pour envoyer)";
    if (icon) icon.textContent = "🎙️";
  } else if (state === 'thinking') {
    orb?.classList.remove('scale-110');
    wave1?.classList.remove('wave-active-1');
    wave2?.classList.remove('wave-active-2');
    if (status) status.textContent = "Réflexion en cours...";
    if (subStatus) subStatus.textContent = "Préparation de la réponse et du vocabulaire";
    if (icon) icon.textContent = "✨";
  } else if (state === 'speaking') {
    orb?.classList.add('scale-105');
    wave1?.classList.add('wave-active-1');
    if (status) status.textContent = "Le tuteur parle...";
    if (subStatus) subStatus.textContent = "Écoutez la prononciation";
    if (icon) icon.textContent = "🔊";
  } else {
    // Idle
    orb?.classList.remove('scale-110', 'scale-105');
    wave1?.classList.remove('wave-active-1');
    wave2?.classList.remove('wave-active-2');
    if (status) status.textContent = "Touchez l'orbe pour parler";
    if (subStatus) subStatus.textContent = "ou écrivez ci-dessous";
    if (icon) icon.textContent = "🎙️";
  }
}

// Voice from Orb
function triggerOrbVoice() {
  toggleVoiceRecord();
}

// Toggle Voice Recording
async function toggleVoiceRecord() {
  // Try Web Speech Recognition if available
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (SpeechRecognition && !isRecording) {
    try {
      const recognition = new SpeechRecognition();
      recognition.lang = currentUser.learning_lang === 'de' ? 'de-DE' : (currentUser.learning_lang === 'es' ? 'es-ES' : 'fr-FR');
      recognition.interimResults = false;
      recognition.maxAlternatives = 1;

      recognition.onstart = () => {
        isRecording = true;
        haptic('medium');
        setOrbState('listening');
        document.getElementById('micBtn')?.classList.add('animate-pulse', 'ring-2', 'ring-sky-400');
      };

      recognition.onresult = async (event) => {
        const transcript = event.results[0][0].transcript;
        appendUserMessage(transcript, true);
        await processConversationTurn(transcript);
      };

      recognition.onerror = (e) => {
        console.warn('Speech recognition error:', e);
        setOrbState('idle');
      };

      recognition.onend = () => {
        isRecording = false;
        document.getElementById('micBtn')?.classList.remove('animate-pulse', 'ring-2', 'ring-sky-400');
      };

      recognition.start();
      return;
    } catch (e) {}
  }

  // Fallback to MediaRecorder
  if (!isRecording) {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      mediaRecorder = new MediaRecorder(stream);
      audioChunks = [];

      mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) audioChunks.push(e.data);
      };

      mediaRecorder.onstop = async () => {
        const sampleText = currentUser.learning_lang === 'de' ? 'Hallo! Ich übe heute mein Deutsch.' : 'Hello! I am practicing.';
        appendUserMessage(sampleText, true);
        await processConversationTurn(sampleText);
      };

      mediaRecorder.start();
      isRecording = true;
      haptic('medium');
      setOrbState('listening');
      document.getElementById('micBtn')?.classList.add('animate-pulse', 'ring-2', 'ring-sky-400');
    } catch (err) {
      alert('Veuillez autoriser l’accès au microphone.');
    }
  } else {
    if (mediaRecorder && mediaRecorder.state !== 'inactive') {
      mediaRecorder.stop();
      mediaRecorder.stream.getTracks().forEach(t => t.stop());
    }
    isRecording = false;
    haptic('light');
    setOrbState('thinking');
    document.getElementById('micBtn')?.classList.remove('animate-pulse', 'ring-2', 'ring-sky-400');
  }
}

// Send Text Message
async function sendTextMessage() {
  const input = document.getElementById('chatInput');
  const text = input?.value?.trim();
  if (!text) return;

  input.value = '';
  haptic('light');
  appendUserMessage(text, false);
  await processConversationTurn(text);
}

// Process Turn with AI Engine
async function processConversationTurn(userMessage) {
  setOrbState('thinking');

  try {
    const res = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        user_id: currentUser.user_id,
        message: userMessage,
        language: currentUser.learning_lang,
        level: currentUser.level,
        theme: currentUser.current_theme
      })
    });

    if (res.ok) {
      const data = await res.json();
      appendTeacherMessage(data);

      if (data.suggestedReply) {
        showSuggestion(data.suggestedReply);
      }

      if (currentUser.auto_audio) {
        playTTS(data.reply, currentUser.learning_lang);
      } else {
        setOrbState('idle');
      }
      return;
    }
  } catch (err) {}

  // Client-Side AI Response Generator (for standalone / GitHub Pages)
  setTimeout(() => {
    const fallbackResponse = generateClientAIResponse(userMessage, currentUser);
    appendTeacherMessage(fallbackResponse);
    if (fallbackResponse.suggestedReply) {
      showSuggestion(fallbackResponse.suggestedReply);
    }
    if (currentUser.auto_audio) {
      playTTS(fallbackResponse.reply, currentUser.learning_lang);
    } else {
      setOrbState('idle');
    }
  }, 700);
}

// Client-Side Response Generator for Offline / GitHub Pages
function generateClientAIResponse(userMsg, user) {
  const lang = user.learning_lang;
  if (lang === 'de') {
    return {
      reply: `Sehr gut! Du hast gesagt: "${userMsg}". Im B2-Niveau ist es wichtig, komplexe Satzstrukturen wie Nebensätze mit "weil" oder "obwohl" zu verwenden. Was denkst du darüber?`,
      translationFr: `Très bien ! Tu as dit : "${userMsg}". Au niveau B2, il est important d'utiliser des structures de phrases complexes. Qu'en penses-tu ?`,
      correction: userMsg.toLowerCase().includes('ich bin') && userMsg.toLowerCase().includes('jahre') ? "En allemand, pour l'âge, on dit « Ich bin X Jahre alt »." : null,
      vocabulary: [
        { word: 'die Satzstruktur', translation: 'la structure de phrase', example: 'Die deutsche Satzstruktur ist logisch.' },
        { word: 'verwenden', translation: 'utiliser / employer', example: 'Wir verwenden neue Wörter.' }
      ],
      suggestedReply: 'Ich finde, dass diese Übung sehr hilfreich ist.'
    };
  } else if (lang === 'es') {
    return {
      reply: `¡Muy bien! Has dicho: "${userMsg}". En el nivel B2 practicamos el subjuntivo y los conectores. ¿Qué opinas?`,
      translationFr: `Très bien ! Tu as dit : "${userMsg}". Au niveau B2 nous pratiquons le subjonctif et les connecteurs. Qu'en penses-tu ?`,
      correction: null,
      vocabulary: [
        { word: 'el conector', translation: 'le connecteur logique', example: 'Es un conector útil.' }
      ],
      suggestedReply: 'Me parece una buena idea practicar esto.'
    };
  } else {
    return {
      reply: `Great point! You said: "${userMsg}". Let's continue exploring this topic together. What would you like to add?`,
      translationFr: `Excellent point ! Tu as dit : "${userMsg}". Continuons à explorer ce sujet ensemble.`,
      correction: null,
      vocabulary: [
        { word: 'exploring', translation: 'explorer / approfondir', example: 'We are exploring new topics.' }
      ],
      suggestedReply: 'I would like to tell you more about my experience.'
    };
  }
}

// Append User Bubble
function appendUserMessage(text, isVoice = false) {
  const container = document.getElementById('messagesContainer');
  if (!container) return;

  const div = document.createElement('div');
  div.className = 'flex justify-end animate-fade-in';
  div.innerHTML = `
    <div class="chat-bubble-user max-w-[85%] sm:max-w-[75%] rounded-2xl p-3.5 shadow-lg text-white text-xs sm:text-sm">
      <div class="flex items-center gap-1.5 mb-1 opacity-80 text-[10px]">
        <span>${isVoice ? '🎙️ Message vocal' : '👤 Vous'}</span>
      </div>
      <p class="leading-relaxed font-normal">${escapeHtml(text)}</p>
    </div>
  `;
  container.appendChild(div);
  container.scrollTop = container.scrollHeight;
}

// Append Teacher Card
function appendTeacherMessage(data) {
  const container = document.getElementById('messagesContainer');
  if (!container) return;

  const flags = { de: '🇩🇪', es: '🇪🇸', en: '🇬🇧', fr: '🇫🇷', it: '🇮🇹', pt: '🇧🇷', nb: '🇳🇴', zh: '🇨🇳', ro: '🇷🇴', ar: '🇸🇦', ru: '🇷🇺', ja: '🇯🇵' };
  const flag = flags[currentUser.learning_lang] || '🇩🇪';

  const div = document.createElement('div');
  div.className = 'flex justify-start animate-fade-in';

  let vocabHtml = '';
  if (data.vocabulary && data.vocabulary.length > 0) {
    vocabHtml = `
      <div class="mt-2.5 pt-2 border-t border-white/[0.08]">
        <p class="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1">📚 Vocabulaire Clé :</p>
        <div class="space-y-1">
          ${data.vocabulary.map(v => `
            <div class="flex items-baseline justify-between text-xs bg-slate-900/60 px-2 py-1 rounded-lg border border-white/[0.04]">
              <span class="font-bold text-sky-300">${escapeHtml(v.word)}</span>
              <span class="text-slate-300 italic text-[11px]">${escapeHtml(v.translation)}</span>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  }

  let correctionHtml = '';
  if (data.correction && data.correction !== 'NONE' && data.correction.trim() !== '') {
    correctionHtml = `
      <div class="mt-2.5 p-2 rounded-xl bg-amber-500/10 border border-amber-500/20 text-xs text-amber-200">
        <span class="font-bold">💡 Point Grammaire & Recast :</span>
        <p class="text-[11px] mt-0.5 text-amber-100">${escapeHtml(data.correction)}</p>
      </div>
    `;
  }

  let translationHtml = '';
  if (data.translationFr && currentUser.show_subtitles) {
    translationHtml = `
      <details class="mt-2.5 group">
        <summary class="text-[11px] font-semibold text-sky-400 cursor-pointer hover:text-sky-300 flex items-center gap-1">
          <span>🇫🇷 Traduction en français</span>
          <span class="text-[9px] transition-transform group-open:rotate-180">▼</span>
        </summary>
        <p class="text-xs text-slate-300 italic mt-1.5 p-2 rounded-lg bg-slate-900/50 border border-white/[0.04]">
          ${escapeHtml(data.translationFr)}
        </p>
      </details>
    `;
  }

  div.innerHTML = `
    <div class="chat-bubble-teacher max-w-[90%] sm:max-w-[80%] rounded-2xl p-4 shadow-xl text-white text-xs sm:text-sm bg-slate-800/80 border border-white/[0.08]">
      <div class="flex items-center justify-between pb-2 mb-2 border-b border-white/[0.06] text-[11px]">
        <div class="flex items-center gap-1.5 font-bold text-sky-400">
          <span>${flag}</span>
          <span>Fleunce · ${currentUser.level}</span>
        </div>
        <button onclick="playTTS('${escapeQuote(data.reply)}', '${currentUser.learning_lang}')" class="px-2 py-0.5 rounded-full bg-sky-500/10 hover:bg-sky-500/20 text-sky-300 border border-sky-500/30 flex items-center gap-1 text-[10px] font-semibold transition">
          <span>🔊</span>
          <span>Écouter</span>
        </button>
      </div>

      <p class="leading-relaxed font-medium text-slate-100">${escapeHtml(data.reply)}</p>

      ${translationHtml}
      ${correctionHtml}
      ${vocabHtml}
    </div>
  `;

  container.appendChild(div);
  container.scrollTop = container.scrollHeight;
}

// Initial Greeting Card
function renderInitialMessage() {
  const container = document.getElementById('messagesContainer');
  if (!container || container.children.length > 0) return;

  const data = {
    reply: "Hallo! Ich bin dein Fleunce-Sprachlehrer. Wie kann ich dir heute beim Deutschlernen helfen?",
    translationFr: "Bonjour ! Je suis ton tuteur de langue Fleunce. Comment puis-je t'aider aujourd'hui dans ton apprentissage de l'allemand ?",
    suggestedReply: "Ich möchte mein Deutsch für das B2-Niveau verbessern.",
    vocabulary: [
      { word: "der Sprachlehrer", translation: "le professeur / tuteur de langue", example: "" }
    ]
  };

  appendTeacherMessage(data);
  showSuggestion(data.suggestedReply);
}

// Play Speech Audio via Browser Speech Synthesis or TTS API
async function playTTS(text, lang) {
  try {
    haptic('light');
    setOrbState('speaking');

    // 1. Try Browser Speech Synthesis
    if ('speechSynthesis' in window) {
      window.speechSynthesis.cancel();
      const utterance = new SpeechSynthesisUtterance(text);
      utterance.lang = lang === 'de' ? 'de-DE' : (lang === 'es' ? 'es-ES' : (lang === 'en' ? 'en-US' : 'fr-FR'));
      utterance.rate = 0.95;
      utterance.onend = () => setOrbState('idle');
      utterance.onerror = () => setOrbState('idle');
      window.speechSynthesis.speak(utterance);
      return;
    }

    // 2. Fallback to HTTP TTS
    if (currentAudioElement) {
      currentAudioElement.pause();
    }
    const audioUrl = `/api/tts?text=${encodeURIComponent(text)}&lang=${lang}`;
    currentAudioElement = new Audio(audioUrl);
    currentAudioElement.onended = () => setOrbState('idle');
    currentAudioElement.onerror = () => setOrbState('idle');
    await currentAudioElement.play();
  } catch (err) {
    setOrbState('idle');
  }
}

// Show Suggestion Pill
function showSuggestion(text) {
  const box = document.getElementById('suggestionBox');
  const btn = document.getElementById('suggestionBtn');
  if (box && btn) {
    btn.textContent = text;
    btn.dataset.text = text;
    box.classList.remove('hidden');
  }
}

// Use Suggestion
function useSuggestion() {
  const btn = document.getElementById('suggestionBtn');
  const text = btn?.dataset?.text;
  if (!text) return;

  const input = document.getElementById('chatInput');
  if (input) {
    input.value = text;
    input.focus();
  }
}

// Load Languages
async function loadLanguages() {
  try {
    const res = await fetch('/api/languages');
    if (res.ok) {
      languagesList = await res.json();
    }
  } catch (err) {}
  renderSettingsLanguages();
}

// Render Settings Languages Grid
function renderSettingsLanguages() {
  const grid = document.getElementById('settingsLangGrid');
  if (!grid) return;

  grid.innerHTML = languagesList.map(lang => {
    const isSelected = lang.id === currentUser.learning_lang;
    return `
      <button onclick="selectLanguage('${lang.id}')" class="p-2.5 rounded-xl border text-left transition flex flex-col justify-between ${isSelected ? 'bg-sky-500/20 border-sky-500 text-white' : 'bg-slate-800/60 border-white/[0.06] text-slate-300 hover:bg-slate-700/60'}">
        <span class="text-xl">${lang.flag}</span>
        <div class="mt-1">
          <p class="text-xs font-bold truncate">${lang.name}</p>
          <p class="text-[10px] text-slate-400 truncate">${lang.nativeName}</p>
        </div>
      </button>
    `;
  }).join('');
}

// Select Language
async function selectLanguage(langId) {
  haptic('medium');
  currentUser.learning_lang = langId;
  savePreferences();
  updateHeaderUI();
  renderSettingsLanguages();
  switchTab('chat');
}

// Select Level
async function selectLevel(level) {
  haptic('medium');
  currentUser.level = level;
  savePreferences();
  updateHeaderUI();

  document.querySelectorAll('.level-btn').forEach(btn => {
    if (btn.textContent.trim() === level) {
      btn.className = 'level-btn py-2 rounded-lg bg-sky-500 text-xs font-bold text-white';
    } else {
      btn.className = 'level-btn py-2 rounded-lg bg-slate-800 text-xs font-bold text-slate-300 hover:bg-slate-700';
    }
  });
}

// Load Themes
async function loadThemes() {
  try {
    const res = await fetch('/api/themes');
    if (res.ok) {
      themesList = await res.json();
    }
  } catch (err) {}
  renderThemes('all');
}

// Filter Themes
function filterThemes(cat) {
  haptic('light');
  document.querySelectorAll('.theme-cat-btn').forEach(btn => {
    btn.classList.remove('bg-sky-500', 'text-white');
    btn.classList.add('bg-slate-800', 'text-slate-300');
  });
  if (event?.target) {
    event.target.classList.add('bg-sky-500', 'text-white');
    event.target.classList.remove('bg-slate-800', 'text-slate-300');
  }

  renderThemes(cat);
}

// Render Themes Grid
function renderThemes(category) {
  const grid = document.getElementById('themesGrid');
  if (!grid) return;

  const filtered = category === 'all' ? themesList : themesList.filter(t => t.category === category);

  grid.innerHTML = filtered.map(t => {
    const isCurrent = t.id === currentUser.current_theme;
    return `
      <div onclick="selectTheme('${t.id}')" class="cursor-pointer p-3.5 rounded-2xl border transition relative overflow-hidden flex flex-col justify-between ${isCurrent ? 'bg-gradient-to-tr from-sky-900/40 to-indigo-900/40 border-sky-500 shadow-lg shadow-sky-500/10' : 'bg-slate-800/60 hover:bg-slate-700/60 border-white/[0.06]'}">
        <div class="flex items-start justify-between">
          <span class="text-2xl p-2 rounded-xl bg-slate-900/60 border border-white/[0.06]">${t.icon}</span>
          ${isCurrent ? '<span class="px-2 py-0.5 rounded-full bg-sky-500 text-white text-[10px] font-bold">Actif</span>' : ''}
        </div>
        <div class="mt-3">
          <h4 class="font-display font-bold text-xs sm:text-sm text-white">${escapeHtml(t.name)}</h4>
          <p class="text-[11px] text-slate-400 mt-1 line-clamp-2">${escapeHtml(t.desc)}</p>
        </div>
      </div>
    `;
  }).join('');
}

// Select Theme
async function selectTheme(themeId) {
  haptic('medium');
  currentUser.current_theme = themeId;
  savePreferences();
  updateHeaderUI();
  renderThemes('all');
  
  const container = document.getElementById('messagesContainer');
  if (container) container.innerHTML = '';
  
  switchTab('chat');
  setOrbState('thinking');

  const themeObj = themesList.find(t => t.id === themeId);
  setTimeout(() => {
    appendTeacherMessage({
      reply: `Willkommen im Szenario: "${themeObj?.name || 'Mise en situation'}". Lass uns anfangen!`,
      translationFr: `Bienvenue dans le scénario : "${themeObj?.name || 'Mise en situation'}". Commençons !`,
      suggestedReply: "Hallo! Ich bin bereit anzufangen."
    });
    setOrbState('idle');
  }, 500);
}

// Load SRS Due Words
async function loadSrsDueWords() {
  try {
    const res = await fetch(`/api/srs/words?user_id=${currentUser.user_id}&language=${currentUser.learning_lang}`);
    if (res.ok) {
      const data = await res.json();
      dueWordsList = data.dueWords || [];
      allWordsList = data.allWords || [];
    }
  } catch (err) {}

  if (dueWordsList.length === 0) {
    // Default initial cards for learner
    dueWordsList = [
      { id: 1, word: 'das Symptom', translation_fr: 'le symptôme', example_sentence: 'Welche Symptome haben Sie?', repetitions: 1 },
      { id: 2, word: 'die Untersuchung', translation_fr: 'l’examen médical', example_sentence: 'Die Untersuchung war gründlich.', repetitions: 2 },
      { id: 3, word: 'die Behandlung', translation_fr: 'le traitement médical', example_sentence: 'Die Behandlung schlägt gut an.', repetitions: 0 }
    ];
    allWordsList = dueWordsList;
  }

  const dueCountEl = document.getElementById('srsDueCount');
  if (dueCountEl) dueCountEl.textContent = dueWordsList.length;

  const totalCountEl = document.getElementById('totalWordsCount');
  if (totalCountEl) totalCountEl.textContent = allWordsList.length;

  renderVocabList(allWordsList);
  currentSrsIndex = 0;
  renderActiveSrsCard();
}

// Render Active SRS Card
function renderActiveSrsCard() {
  const target = document.getElementById('srsWordTarget');
  const example = document.getElementById('srsWordExample');
  const meaning = document.getElementById('srsWordMeaning');
  const recall = document.getElementById('srsCardRecall');
  const answerArea = document.getElementById('srsAnswerArea');
  const revealBtn = document.getElementById('srsRevealBtnContainer');
  const gradeBtns = document.getElementById('srsGradeBtns');

  if (dueWordsList.length === 0 || currentSrsIndex >= dueWordsList.length) {
    if (target) target.textContent = "🎉 Bravo !";
    if (example) example.textContent = "Toutes vos révisions du jour sont terminées.";
    if (meaning) meaning.textContent = "";
    if (recall) recall.textContent = "[███] À jour";
    answerArea?.classList.add('hidden');
    revealBtn?.classList.add('hidden');
    gradeBtns?.classList.add('hidden');
    return;
  }

  const wordObj = dueWordsList[currentSrsIndex];
  if (target) target.textContent = wordObj.word;
  if (example) example.textContent = wordObj.example_sentence ? `« ${wordObj.example_sentence} »` : '';
  if (meaning) meaning.textContent = wordObj.translation_fr;

  const reps = wordObj.repetitions || 0;
  const bars = reps === 0 ? '[█░░] Niv 1' : (reps === 1 ? '[██░] Niv 2' : '[███] Niv 3');
  if (recall) recall.textContent = bars;

  answerArea?.classList.add('hidden');
  revealBtn?.classList.remove('hidden');
  gradeBtns?.classList.add('hidden');
}

// Reveal SRS Answer
function revealSrsAnswer() {
  haptic('light');
  document.getElementById('srsAnswerArea')?.classList.remove('hidden');
  document.getElementById('srsRevealBtnContainer')?.classList.add('hidden');
  document.getElementById('srsGradeBtns')?.classList.remove('hidden');
}

// Grade SRS Card
async function gradeSrsCard(grade) {
  haptic('medium');
  currentSrsIndex++;
  renderActiveSrsCard();
}

// Render Vocab List
function renderVocabList(words) {
  const container = document.getElementById('vocabList');
  if (!container) return;

  container.innerHTML = words.map(w => `
    <div class="flex items-center justify-between p-2.5 rounded-xl bg-slate-800/40 border border-white/[0.04] text-xs">
      <div>
        <span class="font-bold text-white">${escapeHtml(w.word)}</span>
        <span class="text-slate-400 text-[11px] ml-2">→ ${escapeHtml(w.translation_fr)}</span>
      </div>
      <button onclick="playTTS('${escapeQuote(w.word)}', '${currentUser.learning_lang}')" class="text-sky-400 hover:text-sky-300 p-1">
        🔊
      </button>
    </div>
  `).join('');
}

// Reset Conversation
async function resetConversation() {
  if (confirm('Voulez-vous réinitialiser le contexte de conversation ?')) {
    haptic('warning');
    const container = document.getElementById('messagesContainer');
    if (container) container.innerHTML = '';
    renderInitialMessage();
    switchTab('chat');
  }
}

// Helpers
function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");
}

function escapeQuote(str) {
  if (!str) return '';
  return str.replace(/'/g, "\\'").replace(/"/g, '\\"');
}
