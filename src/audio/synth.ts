import { Ear } from '../data/model';
import { clampFreq, createEarRouter, dbToGain, engine } from './engine';

export interface Voice {
  /** Fade out and release all nodes */
  stop(fadeMs?: number): void;
  setLevel(db: number, rampMs?: number): void;
  readonly output: GainNode;
}

const RAMP = 0.02;

function makeVoice(source: AudioNode, ear: Ear, levelDb: number, extraStop: () => void): Voice {
  const ctx = engine.ctx;
  const router = createEarRouter(ear);
  const level = ctx.createGain();
  level.gain.value = 0;
  source.connect(level).connect(router.input);
  const t = ctx.currentTime;
  level.gain.setValueAtTime(0, t);
  level.gain.linearRampToValueAtTime(dbToGain(levelDb), t + RAMP);
  let stopped = false;
  return {
    output: level,
    setLevel(db, rampMs = 30) {
      level.gain.cancelScheduledValues(ctx.currentTime);
      level.gain.setTargetAtTime(dbToGain(db), ctx.currentTime, rampMs / 1000 / 3);
    },
    stop(fadeMs = 30) {
      if (stopped) return;
      stopped = true;
      const now = ctx.currentTime;
      level.gain.cancelScheduledValues(now);
      level.gain.setValueAtTime(level.gain.value, now);
      level.gain.linearRampToValueAtTime(0, now + fadeMs / 1000);
      setTimeout(() => {
        try {
          extraStop();
          source.disconnect();
          level.disconnect();
          router.dispose();
        } catch {
          /* ignore */
        }
      }, fadeMs + 50);
    },
  };
}

/** Continuous pure tone. */
export function playTone(freq: number, ear: Ear, levelDb: number): Voice & { setFreq(f: number): void } {
  const ctx = engine.ctx;
  const osc = ctx.createOscillator();
  osc.type = 'sine';
  osc.frequency.value = clampFreq(freq);
  osc.start();
  const v = makeVoice(osc, ear, levelDb, () => osc.stop());
  return {
    ...v,
    setFreq(f: number) {
      osc.frequency.setTargetAtTime(clampFreq(f), ctx.currentTime, 0.01);
    },
  };
}

/** Short pulsed tone burst train (for hearing threshold testing). */
export function playToneBursts(freq: number, ear: Ear, levelDb: number, count = 3, onMs = 200, offMs = 150): Voice {
  const ctx = engine.ctx;
  const osc = ctx.createOscillator();
  osc.type = 'sine';
  osc.frequency.value = clampFreq(freq);
  const env = ctx.createGain();
  env.gain.value = 0;
  osc.connect(env);
  const t0 = ctx.currentTime + 0.02;
  for (let i = 0; i < count; i++) {
    const s = t0 + i * (onMs + offMs) / 1000;
    env.gain.setValueAtTime(0, s);
    env.gain.linearRampToValueAtTime(1, s + 0.01);
    env.gain.setValueAtTime(1, s + onMs / 1000 - 0.01);
    env.gain.linearRampToValueAtTime(0, s + onMs / 1000);
  }
  osc.start();
  const total = count * (onMs + offMs) / 1000 + 0.1;
  osc.stop(t0 + total);
  return makeVoice(env, ear, levelDb, () => {});
}

let whiteBuffer: AudioBuffer | null = null;
let pinkBuffer: AudioBuffer | null = null;
let brownBuffer: AudioBuffer | null = null;

function noiseBuffer(kind: 'white' | 'pink' | 'brown'): AudioBuffer {
  const ctx = engine.ctx;
  const len = ctx.sampleRate * 6;
  if (kind === 'white') {
    if (!whiteBuffer) {
      whiteBuffer = ctx.createBuffer(1, len, ctx.sampleRate);
      const d = whiteBuffer.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    }
    return whiteBuffer;
  }
  if (kind === 'pink') {
    if (!pinkBuffer) {
      pinkBuffer = ctx.createBuffer(1, len, ctx.sampleRate);
      const d = pinkBuffer.getChannelData(0);
      let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
      for (let i = 0; i < len; i++) {
        const w = Math.random() * 2 - 1;
        b0 = 0.99886 * b0 + w * 0.0555179;
        b1 = 0.99332 * b1 + w * 0.0750759;
        b2 = 0.969 * b2 + w * 0.153852;
        b3 = 0.8665 * b3 + w * 0.3104856;
        b4 = 0.55 * b4 + w * 0.5329522;
        b5 = -0.7616 * b5 - w * 0.016898;
        d[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11;
        b6 = w * 0.115926;
      }
    }
    return pinkBuffer;
  }
  if (!brownBuffer) {
    brownBuffer = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = brownBuffer.getChannelData(0);
    let last = 0;
    for (let i = 0; i < len; i++) {
      const w = Math.random() * 2 - 1;
      last = (last + 0.02 * w) / 1.02;
      d[i] = last * 3.5;
    }
  }
  return brownBuffer;
}

function noiseSource(kind: 'white' | 'pink' | 'brown'): AudioBufferSourceNode {
  const ctx = engine.ctx;
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(kind);
  src.loop = true;
  src.loopStart = 0;
  src.loopEnd = src.buffer.duration;
  src.start(0, Math.random() * src.buffer.duration);
  return src;
}

/** Broadband noise. */
export function playNoise(kind: 'white' | 'pink' | 'brown', ear: Ear, levelDb: number): Voice {
  const src = noiseSource(kind);
  return makeVoice(src, ear, levelDb, () => src.stop());
}

/**
 * Narrowband noise centred at `freq` with bandwidth of `widthOctaves` octaves.
 * Two cascaded bandpass biquads give steep skirts; a makeup gain compensates for the lost energy.
 */
export function playNarrowbandNoise(
  freq: number,
  widthOctaves: number,
  ear: Ear,
  levelDb: number,
): Voice & { setFreq(f: number): void } {
  const ctx = engine.ctx;
  const src = noiseSource('white');
  const f = clampFreq(freq);
  const q = Math.sqrt(Math.pow(2, widthOctaves)) / (Math.pow(2, widthOctaves) - 1);
  const bp1 = ctx.createBiquadFilter();
  const bp2 = ctx.createBiquadFilter();
  for (const bp of [bp1, bp2]) {
    bp.type = 'bandpass';
    bp.frequency.value = f;
    bp.Q.value = q;
  }
  const makeup = ctx.createGain();
  const bw = f / q;
  makeup.gain.value = Math.min(30, Math.sqrt((ctx.sampleRate / 2) / bw) * 1.3);
  src.connect(bp1).connect(bp2).connect(makeup);
  const v = makeVoice(makeup, ear, levelDb, () => src.stop());
  return {
    ...v,
    setFreq(nf: number) {
      const cf = clampFreq(nf);
      bp1.frequency.setTargetAtTime(cf, ctx.currentTime, 0.01);
      bp2.frequency.setTargetAtTime(cf, ctx.currentTime, 0.01);
    },
  };
}

/**
 * Builds a notch (band-stop) filter graph: parallel 4th-order Butterworth low-pass and high-pass.
 * Stop band spans `widthOctaves` centred (geometrically) on `centerFreq`.
 */
export function createNotch(centerFreq: number, widthOctaves: number): { input: GainNode; output: GainNode; dispose(): void } {
  const ctx = engine.ctx;
  const half = Math.pow(2, widthOctaves / 2);
  const lo = clampFreq(centerFreq / half);
  const hi = clampFreq(centerFreq * half);
  const input = ctx.createGain();
  const output = ctx.createGain();
  // 8th-order Butterworth as four cascaded biquads. Note: Web Audio interprets Q of lowpass/highpass
  // biquads in dB (resonance), so the linear Butterworth Q values are converted with 20*log10(Q).
  const qs = [0.5098, 0.6013, 0.8999, 2.5629].map((q) => 20 * Math.log10(q));
  const mk = (type: BiquadFilterType, f: number) => {
    const nodes = qs.map((q) => {
      const b = ctx.createBiquadFilter();
      b.type = type;
      b.frequency.value = f;
      b.Q.value = q;
      return b;
    });
    for (let i = 0; i < nodes.length - 1; i++) nodes[i].connect(nodes[i + 1]);
    return nodes;
  };
  const lp = mk('lowpass', lo);
  const hp = mk('highpass', hi);
  input.connect(lp[0]);
  input.connect(hp[0]);
  lp[lp.length - 1].connect(output);
  hp[hp.length - 1].connect(output);
  return {
    input,
    output,
    dispose() {
      [input, output, ...lp, ...hp].forEach((n) => {
        try {
          n.disconnect();
        } catch {
          /* ignore */
        }
      });
    },
  };
}

/** Broadband noise with a notch at the tinnitus frequency (notched noise therapy). */
export function playNotchedNoise(kind: 'white' | 'pink' | 'brown', centerFreq: number, widthOctaves: number, ear: Ear, levelDb: number): Voice {
  const src = noiseSource(kind);
  const notch = createNotch(centerFreq, widthOctaves);
  src.connect(notch.input);
  return makeVoice(notch.output, ear, levelDb, () => {
    src.stop();
    notch.dispose();
  });
}

/** Any external source (e.g. music) through the notch. */
export function playNotchedSource(source: AudioNode, centerFreq: number, widthOctaves: number, ear: Ear, levelDb: number, onStop: () => void): Voice {
  const notch = createNotch(centerFreq, widthOctaves);
  source.connect(notch.input);
  return makeVoice(notch.output, ear, levelDb, () => {
    notch.dispose();
    onStop();
  });
}

function createRainSource(): { node: AudioNode; stop(): void } {
  const ctx = engine.ctx;
  const src = noiseSource('pink');
  const hp = ctx.createBiquadFilter();
  hp.type = 'highpass';
  hp.frequency.value = 400;
  const lfoGain = ctx.createGain();
  lfoGain.gain.value = 0.8;
  const lfo = ctx.createOscillator();
  lfo.type = 'sine';
  lfo.frequency.value = 0.13;
  const lfoDepth = ctx.createGain();
  lfoDepth.gain.value = 0.2;
  lfo.connect(lfoDepth).connect(lfoGain.gain);
  lfo.start();
  src.connect(hp).connect(lfoGain);
  return {
    node: lfoGain,
    stop() {
      src.stop();
      lfo.stop();
    },
  };
}

/** Synthetic "rain" built from filtered noise, for sound enrichment. */
export function playRain(ear: Ear, levelDb: number): Voice {
  const rain = createRainSource();
  return makeVoice(rain.node, ear, levelDb, () => rain.stop());
}

/** Rain through the notch filter. */
export function playNotchedRain(centerFreq: number, widthOctaves: number, ear: Ear, levelDb: number): Voice {
  const rain = createRainSource();
  return playNotchedSource(rain.node, centerFreq, widthOctaves, ear, levelDb, () => rain.stop());
}
