// Tiny synthesized SFX. No files, no assets, no loading spinner — pencil
// scratches and pops made with oscillators and noise.
export class Sfx {
  constructor() {
    this.ctx = null;
    this.volume = 0.55;
    this.enabled = true;
  }

  unlock() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) { this.enabled = false; return; }
    this.ctx = new AC();
    this.master = this.ctx.createGain();
    this.master.gain.value = this.volume;
    this.master.connect(this.ctx.destination);
    this.noise = this.makeNoise();
  }

  makeNoise() {
    const len = this.ctx.sampleRate * 0.4;
    const buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / len) ** 2;
    return buf;
  }

  private_(fn) {
    if (!this.enabled || !this.ctx) return;
    if (this.ctx.state === 'suspended') this.ctx.resume();
    fn();
  }

  scratch(freq = 1400, dur = 0.07, gain = 0.1) {
    this.private_(() => {
      const src = this.ctx.createBufferSource();
      src.buffer = this.noise;
      src.playbackRate.value = freq / 900;
      const filt = this.ctx.createBiquadFilter();
      filt.type = 'bandpass';
      filt.frequency.value = freq;
      filt.Q.value = 3.2;
      const g = this.ctx.createGain();
      g.gain.setValueAtTime(gain, this.ctx.currentTime);
      g.gain.exponentialRampToValueAtTime(0.0001, this.ctx.currentTime + dur);
      src.connect(filt).connect(g).connect(this.master);
      src.start();
      src.stop(this.ctx.currentTime + dur + 0.02);
    });
  }

  tone(freq, dur, type = 'sine', gain = 0.12, slide = 0) {
    this.private_(() => {
      const o = this.ctx.createOscillator();
      o.type = type;
      o.frequency.setValueAtTime(freq, this.ctx.currentTime);
      if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, freq + slide), this.ctx.currentTime + dur);
      const g = this.ctx.createGain();
      g.gain.setValueAtTime(gain, this.ctx.currentTime);
      g.gain.exponentialRampToValueAtTime(0.0001, this.ctx.currentTime + dur);
      o.connect(g).connect(this.master);
      o.start();
      o.stop(this.ctx.currentTime + dur + 0.02);
    });
  }

  shoot() { this.scratch(1800, 0.06, 0.075); this.tone(220, 0.05, 'square', 0.03, -120); }
  hit() { this.scratch(700, 0.1, 0.1); this.tone(160, 0.08, 'triangle', 0.06, -60); }
  kill() {
    this.scratch(420, 0.22, 0.16);
    this.tone(180, 0.18, 'sawtooth', 0.06, -110);
    setTimeout(() => this.tone(520, 0.16, 'sine', 0.05, 180), 30);
  }
  death() { this.tone(300, 0.4, 'sawtooth', 0.09, -240); this.scratch(300, 0.35, 0.12); }
  grow() { this.tone(520, 0.09, 'sine', 0.05, 160); setTimeout(() => this.tone(760, 0.1, 'sine', 0.045, 120), 60); }
  join() { this.tone(440, 0.08, 'triangle', 0.04, 120); }
  ui() { this.tone(680, 0.05, 'triangle', 0.035, 60); }
}
