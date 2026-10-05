import { Ear } from '../data/model';
import { clampFreq, createEarRouter, dbToGain, engine } from './engine';

/**
 * Acoustic Coordinated Reset (CR) neuromodulation, after Tass et al. 2012:
 * four tones around the tinnitus frequency ft (0.766, 0.9, 1.1, 1.395 × ft) are played in random
 * order within each cycle (1.5 Hz). Three cycles with stimulation are followed by two silent cycles.
 * The idea is to desynchronise pathologically synchronised neuronal populations in the auditory cortex.
 */
export interface CrOptions {
  ft: number;
  ear: Ear;
  levelDb: number;
  cycleHz?: number; // default 1.5
  onCycles?: number; // default 3
  offCycles?: number; // default 2
  toneMs?: number; // default 150
}

export const CR_RATIOS = [0.766, 0.9, 1.1, 1.395];

export class CrStimulator {
  private timer: number | null = null;
  private nextCycleTime = 0;
  private cycleIndex = 0;
  private router: ReturnType<typeof createEarRouter>;
  private level: GainNode;
  private running = false;
  readonly freqs: number[];

  constructor(private opts: CrOptions) {
    this.router = createEarRouter(opts.ear);
    this.level = engine.ctx.createGain();
    this.freqs = CR_RATIOS.map((r) => clampFreq(opts.ft * r));
    this.level.gain.value = dbToGain(opts.levelDb);
    this.level.connect(this.router.input);
  }

  get isRunning(): boolean {
    return this.running;
  }

  setLevel(db: number): void {
    this.level.gain.setTargetAtTime(dbToGain(db), engine.ctx.currentTime, 0.02);
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.nextCycleTime = engine.ctx.currentTime + 0.1;
    this.cycleIndex = 0;
    this.timer = window.setInterval(() => this.schedule(), 60);
    this.schedule();
  }

  stop(): void {
    this.running = false;
    if (this.timer !== null) window.clearInterval(this.timer);
    this.timer = null;
    const now = engine.ctx.currentTime;
    this.level.gain.cancelScheduledValues(now);
    this.level.gain.setValueAtTime(this.level.gain.value, now);
    this.level.gain.linearRampToValueAtTime(0, now + 0.05);
    setTimeout(() => {
      try {
        this.level.disconnect();
        this.router.dispose();
      } catch {
        /* ignore */
      }
    }, 120);
  }

  private schedule(): void {
    const ctx = engine.ctx;
    const cycleHz = this.opts.cycleHz ?? 1.5;
    const cycleDur = 1 / cycleHz;
    const onCycles = this.opts.onCycles ?? 3;
    const offCycles = this.opts.offCycles ?? 2;
    const period = onCycles + offCycles;
    const lookahead = 0.3;
    while (this.nextCycleTime < ctx.currentTime + lookahead) {
      const inPeriod = this.cycleIndex % period;
      if (inPeriod < onCycles) {
        const order = shuffle([0, 1, 2, 3]);
        const slot = cycleDur / 4;
        const toneDur = Math.min(slot * 0.9, (this.opts.toneMs ?? 150) / 1000);
        order.forEach((idx, k) => {
          this.scheduleTone(this.freqs[idx], this.nextCycleTime + k * slot, toneDur);
        });
      }
      this.nextCycleTime += cycleDur;
      this.cycleIndex++;
    }
  }

  private scheduleTone(freq: number, at: number, dur: number): void {
    const ctx = engine.ctx;
    const osc = ctx.createOscillator();
    osc.type = 'sine';
    osc.frequency.value = freq;
    const env = ctx.createGain();
    env.gain.setValueAtTime(0, at);
    env.gain.linearRampToValueAtTime(1, at + 0.01);
    env.gain.setValueAtTime(1, at + dur - 0.01);
    env.gain.linearRampToValueAtTime(0, at + dur);
    osc.connect(env).connect(this.level);
    osc.start(at);
    osc.stop(at + dur + 0.02);
    osc.onended = () => {
      try {
        osc.disconnect();
        env.disconnect();
      } catch {
        /* ignore */
      }
    };
  }
}

function shuffle<T>(arr: T[]): T[] {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}
