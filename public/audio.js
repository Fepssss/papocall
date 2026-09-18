/**
 * PapoCall - Audio Engine (Web Audio API)
 * Captura de microfone com VAD e sintetizador de sons
 */

class AudioEngine {
  constructor() {
    this.audioCtx = null;
    this.micStream = null;
    this.analyser = null;
    this.sourceNode = null;
    this.isMuted = false;
    this.isDeafened = false;
    this.isSpeaking = false;
    this.speakingHangoverTimer = null;
    this.analysisActive = false;
    this.speakingThreshold = 18; // percent

    // Callbacks
    this.onSpeakingChange = null;
    this.onVolumeMeter = null;
  }

  ensureContext() {
    if (!this.audioCtx) {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      this.audioCtx = new AudioContextClass();
    }
    if (this.audioCtx.state === 'suspended') {
      this.audioCtx.resume();
    }
  }

  // --- Sound Effects Synthesizer ---
  playTone(freq, type, duration, delay = 0, force = false) {
    try {
      this.ensureContext();
      if (this.isDeafened && !force) return;

      const osc = this.audioCtx.createOscillator();
      const gain = this.audioCtx.createGain();

      osc.type = type;
      osc.frequency.setValueAtTime(freq, this.audioCtx.currentTime + delay);

      gain.gain.setValueAtTime(0.08, this.audioCtx.currentTime + delay);
      gain.gain.exponentialRampToValueAtTime(0.0001, this.audioCtx.currentTime + delay + duration);

      osc.connect(gain);
      gain.connect(this.audioCtx.destination);

      osc.start(this.audioCtx.currentTime + delay);
      osc.stop(this.audioCtx.currentTime + delay + duration);
    } catch (e) {
      console.warn('Erro ao tocar som:', e);
    }
  }

  playConnect() {
    // Two-tone rising chime (TeamSpeak style connected)
    this.playTone(440, 'sine', 0.12, 0);
    this.playTone(880, 'sine', 0.20, 0.1);
  }

  playDisconnect() {
    // Two-tone falling chime (TeamSpeak style disconnected)
    this.playTone(660, 'sine', 0.12, 0);
    this.playTone(330, 'sine', 0.22, 0.1);
  }

  playMute(muted) {
    if (muted) {
      this.playTone(400, 'triangle', 0.08, 0);
      this.playTone(250, 'triangle', 0.12, 0.06);
    } else {
      this.playTone(250, 'triangle', 0.08, 0);
      this.playTone(500, 'triangle', 0.12, 0.06);
    }
  }

  playDeafen(deafened) {
    if (deafened) {
      this.playTone(350, 'triangle', 0.09, 0, true);
      this.playTone(180, 'triangle', 0.14, 0.07, true);
    } else {
      this.playTone(180, 'triangle', 0.09, 0, true);
      this.playTone(380, 'triangle', 0.14, 0.07, true);
    }
  }

  playMessageSound() {
    this.playTone(520, 'sine', 0.09, 0);
  }

  // --- Microphone & Voice Activity Detection ---
  async startMicrophone() {
    this.ensureContext();
    try {
      this.micStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      });

      this.analyser = this.audioCtx.createAnalyser();
      this.analyser.fftSize = 512;
      this.analyser.smoothingTimeConstant = 0.4;

      this.sourceNode = this.audioCtx.createMediaStreamSource(this.micStream);
      this.sourceNode.connect(this.analyser);

      this.analysisActive = true;
      this.analyzeAudioLoop();
      return true;
    } catch (err) {
      console.warn('Acesso ao microfone não concedido ou indisponível:', err);
      // Fallback: simulate voice activity on user action or allow silence
      return false;
    }
  }

  stopMicrophone() {
    this.analysisActive = false;
    if (this.speakingHangoverTimer) {
      clearTimeout(this.speakingHangoverTimer);
      this.speakingHangoverTimer = null;
    }

    if (this.isSpeaking) {
      this.isSpeaking = false;
      if (this.onSpeakingChange) this.onSpeakingChange(false);
    }

    if (this.sourceNode) {
      try { this.sourceNode.disconnect(); } catch (e) {}
      this.sourceNode = null;
    }

    if (this.micStream) {
      this.micStream.getTracks().forEach(t => t.stop());
      this.micStream = null;
    }

    if (this.onVolumeMeter) {
      this.onVolumeMeter(0);
    }
  }

  analyzeAudioLoop() {
    if (!this.analysisActive || !this.analyser) return;

    const buffer = new Uint8Array(this.analyser.frequencyBinCount);
    this.analyser.getByteTimeDomainData(buffer);

    // Calculate RMS volume level
    let sum = 0;
    for (let i = 0; i < buffer.length; i++) {
      const val = (buffer[i] - 128) / 128;
      sum += val * val;
    }
    const rms = Math.sqrt(sum / buffer.length);
    const volumePercent = this.isMuted ? 0 : Math.min(100, Math.round(rms * 250));

    if (this.onVolumeMeter) {
      this.onVolumeMeter(volumePercent);
    }

    // Voice Activity Detection threshold check
    if (!this.isMuted && volumePercent >= this.speakingThreshold) {
      if (this.speakingHangoverTimer) {
        clearTimeout(this.speakingHangoverTimer);
        this.speakingHangoverTimer = null;
      }
      if (!this.isSpeaking) {
        this.isSpeaking = true;
        if (this.onSpeakingChange) this.onSpeakingChange(true);
      }
    } else if (this.isSpeaking && !this.speakingHangoverTimer) {
      // Hangover delay so green light doesn't flicker between syllables
      this.speakingHangoverTimer = setTimeout(() => {
        this.isSpeaking = false;
        this.speakingHangoverTimer = null;
        if (this.onSpeakingChange) this.onSpeakingChange(false);
      }, 350);
    }

    requestAnimationFrame(() => this.analyzeAudioLoop());
  }

  setMute(muted) {
    this.isMuted = muted;
    this.playMute(muted);
    if (this.micStream) {
      this.micStream.getAudioTracks().forEach(t => {
        t.enabled = !muted;
      });
    }
    if (muted && this.isSpeaking) {
      this.isSpeaking = false;
      if (this.onSpeakingChange) this.onSpeakingChange(false);
    }
  }

  setDeafen(deafened) {
    this.isDeafened = deafened;
    if (deafened) {
      this.setMute(true);
    }
  }
}

window.audioEngine = new AudioEngine();
