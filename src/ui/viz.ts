import { engine, formatHz } from '../audio/engine';
import { h } from './dom';

export interface VizOpts {
  tinnitusHz?: number;
  notch?: { lo: number; hi: number } | null;
  color?: string;
  height?: number;
}

const F_LO = 150;
const F_HI = 20000;

/**
 * Live log-frequency spectrum of everything the engine is currently playing.
 * Marks the tinnitus frequency and an optional notch band. Stops itself when detached.
 */
export function spectrumViz(o: VizOpts = {}): { el: HTMLElement; setNotch(n: { lo: number; hi: number } | null): void } {
  const canvas = h('canvas', { class: 'viz', style: `height:${o.height ?? 120}px` }) as HTMLCanvasElement;
  const label = o.tinnitusHz ? h('div', { class: 'viz-label' }, `Tinnitus ${formatHz(o.tinnitusHz)}`) : null;
  const el = h('div', { class: 'viz-wrap' }, canvas, label);
  let notch = o.notch ?? null;
  const analyser = engine.analyser;
  const bins = new Float32Array(analyser.frequencyBinCount);
  const smooth = new Float32Array(160);
  const ctx2d = canvas.getContext('2d')!;
  const css = getComputedStyle(document.documentElement);
  const color = o.color ?? (css.getPropertyValue('--sound').trim() || '#5eead4');
  const tin = css.getPropertyValue('--tin').trim() || '#fbbf24';
  const sr = engine.sampleRate;
  const xOf = (f: number, w: number) => (Math.log2(f / F_LO) / Math.log2(F_HI / F_LO)) * w;
  let raf = 0;
  let started = false;

  const draw = () => {
    if (started && !canvas.isConnected) { cancelAnimationFrame(raf); return; }
    started = true;
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth, hgt = canvas.clientHeight;
    if (canvas.width !== Math.round(w * dpr)) { canvas.width = Math.round(w * dpr); canvas.height = Math.round(hgt * dpr); }
    ctx2d.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx2d.clearRect(0, 0, w, hgt);
    if (notch) {
      const a = xOf(notch.lo, w), b = xOf(notch.hi, w);
      ctx2d.fillStyle = 'rgba(251,191,36,0.08)';
      ctx2d.fillRect(a, 0, b - a, hgt);
    }
    analyser.getFloatFrequencyData(bins);
    const N = smooth.length;
    for (let i = 0; i < N; i++) {
      const f0 = F_LO * Math.pow(F_HI / F_LO, i / N);
      const f1 = F_LO * Math.pow(F_HI / F_LO, (i + 1) / N);
      const b0 = Math.floor((f0 / (sr / 2)) * bins.length);
      const b1 = Math.max(b0 + 1, Math.floor((f1 / (sr / 2)) * bins.length));
      let m = -140;
      for (let b = b0; b < b1 && b < bins.length; b++) m = Math.max(m, bins[b]);
      const v = Math.max(0, Math.min(1, (m + 110) / 85));
      smooth[i] = smooth[i] * 0.72 + v * 0.28;
    }
    const grad = ctx2d.createLinearGradient(0, 0, 0, hgt);
    grad.addColorStop(0, color);
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    ctx2d.beginPath();
    ctx2d.moveTo(0, hgt);
    for (let i = 0; i < N; i++) {
      const x = (i / (N - 1)) * w;
      const y = hgt - smooth[i] * (hgt - 6);
      ctx2d.lineTo(x, y);
    }
    ctx2d.lineTo(w, hgt);
    ctx2d.closePath();
    ctx2d.globalAlpha = 0.5;
    ctx2d.fillStyle = grad;
    ctx2d.fill();
    ctx2d.globalAlpha = 1;
    ctx2d.beginPath();
    for (let i = 0; i < N; i++) {
      const x = (i / (N - 1)) * w;
      const y = hgt - smooth[i] * (hgt - 6);
      if (i) ctx2d.lineTo(x, y); else ctx2d.moveTo(x, y);
    }
    ctx2d.strokeStyle = color;
    ctx2d.lineWidth = 2;
    ctx2d.shadowColor = color;
    ctx2d.shadowBlur = 10;
    ctx2d.stroke();
    ctx2d.shadowBlur = 0;
    if (o.tinnitusHz) {
      const x = xOf(o.tinnitusHz, w);
      ctx2d.strokeStyle = tin;
      ctx2d.setLineDash([3, 4]);
      ctx2d.lineWidth = 1.5;
      ctx2d.beginPath();
      ctx2d.moveTo(x, 22);
      ctx2d.lineTo(x, hgt);
      ctx2d.stroke();
      ctx2d.setLineDash([]);
      if (label) label.style.left = `${Math.min(w - 50, Math.max(50, x))}px`;
    }
    raf = requestAnimationFrame(draw);
  };
  raf = requestAnimationFrame(draw);
  return { el, setNotch: (n) => (notch = n) };
}
