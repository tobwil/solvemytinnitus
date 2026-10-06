import { h } from './dom';

const NS = 'http://www.w3.org/2000/svg';
let gid = 0;

function s<K extends keyof SVGElementTagNameMap>(tag: K, attrs: Record<string, string | number>, text?: string): SVGElementTagNameMap[K] {
  const e = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
  if (text !== undefined) e.textContent = text;
  return e;
}

export interface Series {
  name: string;
  color: string;
  points: { x: number; y: number }[];
  dashed?: boolean;
  area?: boolean;
  dots?: boolean;
}

export interface ChartOpts {
  series: Series[];
  height?: number;
  xLog?: boolean;
  xMin?: number;
  xMax?: number;
  yMin?: number;
  yMax?: number;
  yInvert?: boolean;
  xTicks?: number[];
  yTicks?: number[];
  xFormat?: (x: number) => string;
  yFormat?: (y: number) => string;
  markers?: { x: number; color: string; label?: string }[];
  bands?: { x1: number; x2: number; color: string }[];
  legend?: boolean;
  empty?: string;
}

/** Smooth monotone-ish path via Catmull-Rom → Bézier. */
function smoothPath(pts: [number, number][]): string {
  if (pts.length < 3) return pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join('');
  let d = `M${pts[0][0].toFixed(1)},${pts[0][1].toFixed(1)}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] ?? pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] ?? p2;
    const t = 0.18;
    const c1 = [p1[0] + (p2[0] - p0[0]) * t, p1[1] + (p2[1] - p0[1]) * t];
    const c2 = [p2[0] - (p3[0] - p1[0]) * t, p2[1] - (p3[1] - p1[1]) * t];
    d += `C${c1[0].toFixed(1)},${c1[1].toFixed(1)} ${c2[0].toFixed(1)},${c2[1].toFixed(1)} ${p2[0].toFixed(1)},${p2[1].toFixed(1)}`;
  }
  return d;
}

export function lineChart(o: ChartOpts): HTMLElement {
  const W = 360;
  const H = Math.round((o.height ?? 220) * 0.62);
  const pad = { l: 28, r: 8, t: 10, b: 22 };
  const svg = s('svg', { viewBox: `0 0 ${W} ${H}`, class: 'chart', role: 'img' });
  const all = o.series.flatMap((x) => x.points);
  if (!all.length) {
    svg.appendChild(s('text', { x: W / 2, y: H / 2, 'text-anchor': 'middle', class: 'empty' }, o.empty ?? 'Noch keine Daten'));
    return h('div', null, svg as unknown as Node);
  }
  const tx = (x: number) => (o.xLog ? Math.log2(x) : x);
  const xs = all.map((p) => tx(p.x));
  let x0 = o.xMin !== undefined ? tx(o.xMin) : Math.min(...xs);
  let x1 = o.xMax !== undefined ? tx(o.xMax) : Math.max(...xs);
  if (x0 === x1) { x0 -= 1; x1 += 1; }
  const ys = all.map((p) => p.y);
  const y0 = o.yMin ?? Math.min(...ys);
  const y1 = o.yMax ?? Math.max(...ys);
  const span = y1 - y0 || 1;
  const sx = (x: number) => pad.l + ((tx(x) - x0) / (x1 - x0)) * (W - pad.l - pad.r);
  const sy = (y: number) => {
    const f = (y - y0) / span;
    return o.yInvert ? pad.t + f * (H - pad.t - pad.b) : H - pad.b - f * (H - pad.t - pad.b);
  };

  const yT = o.yTicks ?? [0, 0.25, 0.5, 0.75, 1].map((f) => y0 + f * span);
  for (const yv of yT) {
    const y = sy(yv);
    svg.appendChild(s('line', { x1: pad.l, x2: W - pad.r, y1: y, y2: y, class: 'grid' }));
    svg.appendChild(s('text', { x: pad.l - 6, y: y + 3.5, 'text-anchor': 'end', class: 'tick' }, o.yFormat ? o.yFormat(yv) : String(Math.round(yv))));
  }
  const xT = o.xTicks ?? [0, 0.25, 0.5, 0.75, 1].map((f) => {
    const v = x0 + f * (x1 - x0);
    return o.xLog ? Math.pow(2, v) : v;
  });
  for (const xv of xT) {
    svg.appendChild(s('text', { x: Math.min(W - 14, Math.max(pad.l + 10, sx(xv))), y: H - 5, 'text-anchor': 'middle', class: 'tick' }, o.xFormat ? o.xFormat(xv) : String(Math.round(xv))));
  }
  for (const b of o.bands ?? []) {
    const a = Math.max(pad.l, sx(b.x1));
    const z = Math.min(W - pad.r, sx(b.x2));
    svg.appendChild(s('rect', { x: a, y: pad.t, width: Math.max(0, z - a), height: H - pad.t - pad.b, fill: b.color, rx: 6 }));
  }
  for (const m of o.markers ?? []) {
    const x = sx(m.x);
    svg.appendChild(s('line', { x1: x, x2: x, y1: pad.t, y2: H - pad.b, stroke: m.color, 'stroke-width': 1.5, 'stroke-dasharray': '4 4' }));
    if (m.label) svg.appendChild(s('text', { x: x > W - 70 ? x - 5 : x + 5, y: pad.t + 9, fill: m.color, 'font-size': 10.5, 'font-weight': 700, 'text-anchor': x > W - 70 ? 'end' : 'start' }, m.label));
  }
  const defs = s('defs', {});
  svg.appendChild(defs);
  for (const ser of o.series) {
    const pts = ser.points.slice().sort((a, b) => a.x - b.x).map((p) => [sx(p.x), sy(p.y)] as [number, number]);
    if (!pts.length) continue;
    const d = smoothPath(pts);
    if (ser.area && pts.length > 1) {
      const id = `g${++gid}`;
      const lg = s('linearGradient', { id, x1: 0, x2: 0, y1: 0, y2: 1 });
      lg.append(s('stop', { offset: '0%', 'stop-color': ser.color, 'stop-opacity': 0.32 }), s('stop', { offset: '100%', 'stop-color': ser.color, 'stop-opacity': 0 }));
      defs.appendChild(lg);
      const base = o.yInvert ? pad.t : H - pad.b;
      svg.appendChild(s('path', { d: `${d}L${pts[pts.length - 1][0]},${base}L${pts[0][0]},${base}Z`, fill: `url(#${id})` }));
    }
    if (pts.length > 1) svg.appendChild(s('path', { d, fill: 'none', stroke: ser.color, 'stroke-width': 2, 'stroke-linecap': 'round', 'stroke-dasharray': ser.dashed ? '4 4' : 'none' }));
    if (ser.dots !== false) for (const p of pts) svg.appendChild(s('circle', { cx: p[0], cy: p[1], r: pts.length > 30 ? 1.6 : 2.8, fill: ser.color }));
  }
  const legend = o.legend === false || o.series.length < 2 ? null : h('div', { class: 'legend' }, ...o.series.map((x) => h('span', null, h('i', { style: `background:${x.color}` }), x.name)));
  return h('div', null, svg as unknown as Node, legend);
}

/** Vertical bars on a log-frequency axis (tinnitus likeness spectrum). */
export function spectrumBars(points: { freq: number; value: number }[], opts: { max?: number; color?: string; peak?: number; height?: number } = {}): HTMLElement {
  const W = 360, H = Math.round((opts.height ?? 170) * 0.7), pad = { l: 2, r: 2, t: 8, b: 20 };
  const svg = s('svg', { viewBox: `0 0 ${W} ${H}`, class: 'chart' });
  if (!points.length) return h('div', null, svg as unknown as Node);
  const max = opts.max ?? Math.max(...points.map((p) => p.value), 1);
  const lmin = Math.log2(Math.min(...points.map((p) => p.freq)));
  const lmax = Math.log2(Math.max(...points.map((p) => p.freq)));
  const n = points.length;
  const slot = (W - pad.l - pad.r) / n;
  const id = `sb${++gid}`;
  const defs = s('defs', {});
  const lg = s('linearGradient', { id, x1: 0, x2: 0, y1: 0, y2: 1 });
  lg.append(s('stop', { offset: '0%', 'stop-color': opts.color ?? 'var(--lab)' }), s('stop', { offset: '100%', 'stop-color': opts.color ?? 'var(--lab)', 'stop-opacity': 0.25 }));
  defs.appendChild(lg);
  svg.appendChild(defs);
  points.slice().sort((a, b) => a.freq - b.freq).forEach((p, i) => {
    const hgt = Math.max(3, (p.value / max) * (H - pad.t - pad.b));
    const x = pad.l + i * slot + slot * 0.18;
    const isPeak = opts.peak !== undefined && Math.abs(Math.log2(p.freq / opts.peak)) < 0.01;
    svg.appendChild(s('rect', { x, y: H - pad.b - hgt, width: slot * 0.64, height: hgt, rx: 5, fill: isPeak ? 'var(--tin)' : `url(#${id})` }));
    const lbl = p.freq >= 1000 ? `${+(p.freq / 1000).toFixed(1)}k` : String(p.freq);
    svg.appendChild(s('text', { x: x + slot * 0.32, y: H - 5, 'text-anchor': 'middle', class: 'tick' }, lbl));
  });
  void lmin; void lmax;
  return h('div', null, svg as unknown as Node);
}

export function sparkline(values: number[], opts: { min?: number; max?: number; color?: string; height?: number } = {}): HTMLElement {
  const W = 300, H = opts.height ?? 56;
  const svg = s('svg', { viewBox: `0 0 ${W} ${H}`, class: 'chart', preserveAspectRatio: 'none', style: `height:${H}px` });
  if (values.length < 2) return h('div', null, svg as unknown as Node);
  const min = opts.min ?? Math.min(...values);
  const max = opts.max ?? Math.max(...values);
  const pts = values.map((v, i) => [(i / (values.length - 1)) * W, H - 4 - ((v - min) / (max - min || 1)) * (H - 8)] as [number, number]);
  const id = `sp${++gid}`;
  const defs = s('defs', {});
  const lg = s('linearGradient', { id, x1: 0, x2: 0, y1: 0, y2: 1 });
  const c = opts.color ?? 'var(--sound)';
  lg.append(s('stop', { offset: '0%', 'stop-color': c, 'stop-opacity': 0.35 }), s('stop', { offset: '100%', 'stop-color': c, 'stop-opacity': 0 }));
  defs.appendChild(lg);
  svg.appendChild(defs);
  const d = smoothPath(pts);
  svg.appendChild(s('path', { d: `${d}L${W},${H}L0,${H}Z`, fill: `url(#${id})` }));
  svg.appendChild(s('path', { d, fill: 'none', stroke: c, 'stroke-width': 2.5, 'stroke-linecap': 'round', 'vector-effect': 'non-scaling-stroke' }));
  return h('div', null, svg as unknown as Node);
}

/** Circular progress ring; returns element and setter (0..1). */
export function ring(color = 'var(--sound)', stroke = 10): { el: SVGSVGElement; set(f: number): void } {
  const R = 100 - stroke;
  const C = 2 * Math.PI * R;
  const svg = s('svg', { viewBox: '0 0 200 200' });
  svg.appendChild(s('circle', { cx: 100, cy: 100, r: R, fill: 'none', 'stroke-width': stroke, class: 'ring-bg' }));
  const fg = s('circle', { cx: 100, cy: 100, r: R, fill: 'none', 'stroke-width': stroke, 'stroke-linecap': 'round', class: 'ring-fg', 'stroke-dasharray': C, 'stroke-dashoffset': C });
  fg.style.stroke = color;
  svg.appendChild(fg);
  return { el: svg, set: (f) => fg.setAttribute('stroke-dashoffset', String(C * (1 - Math.max(0, Math.min(1, f))))) };
}
