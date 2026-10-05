import { Ear } from '../data/model';

/**
 * Central audio engine. All sound is relative: 0 dB = full scale sine at master volume.
 * A brick-wall-ish compressor and a hard master cap protect the ears from accidental peaks.
 */
class AudioEngine {
  private _ctx: AudioContext | null = null;
  private master!: GainNode;
  private limiter!: DynamicsCompressorNode;
  private masterVolume = 0.5;

  get ctx(): AudioContext {
    if (!this._ctx) {
      const Ctx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      this._ctx = new Ctx({ latencyHint: 'playback', sampleRate: 48000 });
      this.limiter = this._ctx.createDynamicsCompressor();
      this.limiter.threshold.value = -6;
      this.limiter.knee.value = 0;
      this.limiter.ratio.value = 20;
      this.limiter.attack.value = 0.001;
      this.limiter.release.value = 0.05;
      this.master = this._ctx.createGain();
      this.master.gain.value = this.masterVolume;
      this.limiter.connect(this.master).connect(this._ctx.destination);
    }
    return this._ctx;
  }

  get sampleRate(): number {
    return this.ctx.sampleRate;
  }

  /** Must be called from a user gesture on iOS/Safari. */
  async ensure(): Promise<AudioContext> {
    const ctx = this.ctx;
    if (ctx.state !== 'running') {
      try {
        await ctx.resume();
      } catch (e) {
        console.warn('AudioContext resume failed', e);
      }
    }
    return ctx;
  }

  get input(): AudioNode {
    this.ctx;
    return this.limiter;
  }

  setMasterVolume(v: number): void {
    this.masterVolume = Math.min(1, Math.max(0, v));
    if (this._ctx) this.master.gain.setTargetAtTime(this.masterVolume, this._ctx.currentTime, 0.02);
  }

  getMasterVolume(): number {
    return this.masterVolume;
  }

  get now(): number {
    return this.ctx.currentTime;
  }
}

export const engine = new AudioEngine();

export function dbToGain(db: number): number {
  return Math.pow(10, db / 20);
}

export function gainToDb(g: number): number {
  return 20 * Math.log10(Math.max(1e-9, g));
}

/**
 * Creates a mono-in node that routes to left / right / both channels.
 * Returns { input, output }. output is already connected to the engine.
 */
export function createEarRouter(ear: Ear): { input: GainNode; dispose: () => void } {
  const ctx = engine.ctx;
  const input = ctx.createGain();
  const gl = ctx.createGain();
  const gr = ctx.createGain();
  gl.gain.value = ear === 'right' ? 0 : 1;
  gr.gain.value = ear === 'left' ? 0 : 1;
  const merger = ctx.createChannelMerger(2);
  input.connect(gl).connect(merger, 0, 0);
  input.connect(gr).connect(merger, 0, 1);
  merger.connect(engine.input);
  return {
    input,
    dispose: () => {
      try {
        input.disconnect();
        gl.disconnect();
        gr.disconnect();
        merger.disconnect();
      } catch {
        /* ignore */
      }
    },
  };
}

export function clampFreq(f: number): number {
  const nyq = engine.sampleRate / 2 - 500;
  return Math.min(nyq, Math.max(100, f));
}

export function formatHz(f: number): string {
  if (f >= 1000) return `${(f / 1000).toFixed(f >= 10000 ? 1 : 2)} kHz`;
  return `${Math.round(f)} Hz`;
}

/** Fraction of an octave between two frequencies */
export function octaveDistance(a: number, b: number): number {
  return Math.abs(Math.log2(a / b));
}
