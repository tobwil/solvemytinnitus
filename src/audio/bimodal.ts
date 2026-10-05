import { Ear } from '../data/model';
import { clampFreq, createEarRouter, dbToGain, engine } from './engine';

/**
 * Experimental bimodal stimulation: short narrowband noise bursts at the tinnitus frequency are paired
 * with a vibration pulse (Vibration API, where available). Inspired by auditory-somatosensory bimodal
 * protocols (Shore et al.), but WITHOUT the precise electrical somatosensory timing those use.
 */
export class BimodalStimulator {
  private timer: number | null = null;
  private router: ReturnType<typeof createEarRouter>;
  private level: GainNode;
  private noise: AudioBuffer;
  running = false;

  constructor(private ft: number, ear: Ear, levelDb: number, private intervalMs = 1000, private jitterMs = 300, private burstMs = 60) {
    this.router = createEarRouter(ear);
    this.level = engine.ctx.createGain();
    this.level.gain.value = dbToGain(levelDb);
    this.level.connect(this.router.input);
    const ctx = engine.ctx;
    const len = Math.floor(ctx.sampleRate * 0.5);
    this.noise = ctx.createBuffer(1, len, ctx.sampleRate);
    const data = this.noise.getChannelData(0);
    for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  }

  static get vibrationSupported(): boolean {
    return typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function';
  }

  setLevel(db: number): void {
    this.level.gain.setTargetAtTime(dbToGain(db), engine.ctx.currentTime, 0.02);
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    const tick = () => {
      if (!this.running) return;
      this.burst();
      try {
        navigator.vibrate?.(this.burstMs);
      } catch {
        /* ignore */
      }
      this.timer = window.setTimeout(tick, this.intervalMs + (Math.random() - 0.5) * 2 * this.jitterMs);
    };
    tick();
  }

  stop(): void {
    this.running = false;
    if (this.timer !== null) window.clearTimeout(this.timer);
    this.timer = null;
    setTimeout(() => {
      try {
        this.level.disconnect();
        this.router.dispose();
      } catch {
        /* ignore */
      }
    }, 200);
  }

  private burst(): void {
    const ctx = engine.ctx;
    const src = ctx.createBufferSource();
    src.buffer = this.noise;
    const f = clampFreq(this.ft);
    const bp1 = ctx.createBiquadFilter();
    const bp2 = ctx.createBiquadFilter();
    for (const bp of [bp1, bp2]) {
      bp.type = 'bandpass';
      bp.frequency.value = f;
      bp.Q.value = 4.3;
    }
    const env = ctx.createGain();
    const t = ctx.currentTime;
    const d = this.burstMs / 1000;
    env.gain.setValueAtTime(0, t);
    env.gain.linearRampToValueAtTime(8, t + 0.005);
    env.gain.setValueAtTime(8, t + d - 0.005);
    env.gain.linearRampToValueAtTime(0, t + d);
    src.connect(bp1).connect(bp2).connect(env).connect(this.level);
    src.start(t);
    src.stop(t + d + 0.01);
    src.onended = () => {
      try {
        src.disconnect();
        bp1.disconnect();
        bp2.disconnect();
        env.disconnect();
      } catch {
        /* ignore */
      }
    };
  }
}
