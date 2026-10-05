import { formatHz } from '../audio/engine';
import { h } from './dom';

export interface PadOpts {
  fMin: number;
  fMax: number;
  value: number;
  overlay?: { freq: number; value: number }[]; // likeness spectrum 0..10
  onStart(f: number): void;
  onMove(f: number): void;
  onEnd(f: number): void;
}

/**
 * Touch frequency pad: drag horizontally across a log-frequency field to sweep the comparison tone.
 * Releasing keeps the last frequency. Draws octave grid and the likeness spectrum as a heat overlay.
 */
export function freqPad(o: PadOpts): { el: HTMLElement; set(f: number): void; get(): number } {
  const canvas = h('canvas', { class: 'pad' }) as HTMLCanvasElement;
  const fEl = h('div', { class: 'f' }, formatHz(o.value));
  const hint = h('div', { class: 'h' }, 'Halten & ziehen');
  const el = h('div', { class: 'pad-wrap' }, canvas, h('div', { class: 'pad-readout' }, fEl, hint));
  let f = o.value;
  let active = false;
  let trail: { x: number; t: number }[] = [];
  const ctx = canvas.getContext('2d')!;
  const css = getComputedStyle(document.documentElement);
  const lab = css.getPropertyValue('--lab').trim() || '#7dd3fc';
  const tin = css.getPropertyValue('--tin').trim() || '#fbbf24';
  const txt = css.getPropertyValue('--text-3').trim() || 'rgba(255,255,255,.4)';
  const strokeC = css.getPropertyValue('--stroke').trim() || 'rgba(255,255,255,.08)';

  const l0 = Math.log2(o.fMin), l1 = Math.log2(o.fMax);
  const M = 26; // inner horizontal margin
  const xOf = (fr: number, w: number) => M + ((Math.log2(fr) - l0) / (l1 - l0)) * (w - 2 * M);
  const fOf = (x: number, w: number) => Math.pow(2, l0 + (Math.max(0, Math.min(w - 2 * M, x - M)) / (w - 2 * M)) * (l1 - l0));

  let raf = 0;
  let started = false;
  const draw = () => {
    if (started && !canvas.isConnected) { cancelAnimationFrame(raf); return; }
    started = true;
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth, H = canvas.clientHeight;
    if (canvas.width !== Math.round(w * dpr)) { canvas.width = Math.round(w * dpr); canvas.height = Math.round(H * dpr); }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, H);
    // likeness overlay
    if (o.overlay?.length) {
      const pts = o.overlay.slice().sort((a, b) => a.freq - b.freq);
      const g = ctx.createLinearGradient(0, H, 0, H * 0.35);
      g.addColorStop(0, 'rgba(251,191,36,0.0)');
      g.addColorStop(1, 'rgba(251,191,36,0.22)');
      ctx.beginPath();
      ctx.moveTo(xOf(pts[0].freq, w), H);
      for (const p of pts) ctx.lineTo(xOf(p.freq, w), H - (p.value / 10) * H * 0.6);
      ctx.lineTo(xOf(pts[pts.length - 1].freq, w), H);
      ctx.closePath();
      ctx.fillStyle = g;
      ctx.fill();
    }
    // octave grid
    ctx.font = '600 11px -apple-system, system-ui, sans-serif';
    ctx.textAlign = 'center';
    for (const gf of [500, 1000, 2000, 4000, 8000, 16000]) {
      if (gf < o.fMin || gf > o.fMax) continue;
      const x = xOf(gf, w);
      ctx.strokeStyle = strokeC;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x, 64);
      ctx.lineTo(x, H - 22);
      ctx.stroke();
      ctx.fillStyle = txt;
      ctx.fillText(gf >= 1000 ? `${gf / 1000}k` : String(gf), x, H - 8);
    }
    // trail
    const now = performance.now();
    trail = trail.filter((p) => now - p.t < 600);
    for (const p of trail) {
      const a = 1 - (now - p.t) / 600;
      ctx.fillStyle = `rgba(125,211,252,${0.12 * a})`;
      ctx.fillRect(p.x - 2, 0, 4, H);
    }
    // cursor
    const x = xOf(f, w);
    const g2 = ctx.createLinearGradient(x - 40, 0, x + 40, 0);
    g2.addColorStop(0, 'rgba(125,211,252,0)');
    g2.addColorStop(0.5, active ? 'rgba(125,211,252,0.35)' : 'rgba(125,211,252,0.15)');
    g2.addColorStop(1, 'rgba(125,211,252,0)');
    ctx.fillStyle = g2;
    ctx.fillRect(x - 40, 0, 80, H);
    ctx.strokeStyle = active ? lab : tin;
    ctx.lineWidth = 2.5;
    ctx.shadowColor = active ? lab : tin;
    ctx.shadowBlur = 16;
    ctx.beginPath();
    ctx.moveTo(x, 58);
    ctx.lineTo(x, H - 24);
    ctx.stroke();
    ctx.shadowBlur = 0;
    ctx.fillStyle = active ? lab : tin;
    ctx.beginPath();
    ctx.arc(x, H / 2 + 10, active ? 11 : 8, 0, Math.PI * 2);
    ctx.fill();
    raf = requestAnimationFrame(draw);
  };
  raf = requestAnimationFrame(draw);

  const pos = (e: PointerEvent) => {
    const r = canvas.getBoundingClientRect();
    return fOf(e.clientX - r.left, r.width);
  };
  canvas.addEventListener('pointerdown', (e) => {
    canvas.setPointerCapture(e.pointerId);
    active = true;
    f = pos(e);
    fEl.textContent = formatHz(f);
    hint.textContent = 'Loslassen zum Stoppen';
    o.onStart(f);
  });
  canvas.addEventListener('pointermove', (e) => {
    if (!active) return;
    f = pos(e);
    trail.push({ x: xOf(f, canvas.getBoundingClientRect().width), t: performance.now() });
    fEl.textContent = formatHz(f);
    o.onMove(f);
  });
  const end = () => {
    if (!active) return;
    active = false;
    hint.textContent = 'Halten & ziehen';
    o.onEnd(f);
  };
  canvas.addEventListener('pointerup', end);
  canvas.addEventListener('pointercancel', end);

  return {
    el,
    set(v: number) {
      f = Math.min(o.fMax, Math.max(o.fMin, v));
      fEl.textContent = formatHz(f);
    },
    get: () => f,
  };
}
