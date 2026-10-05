import { h } from './dom';

const NS = 'http://www.w3.org/2000/svg';

function svgEl<K extends keyof SVGElementTagNameMap>(tag: K, attrs: Record<string, string | number>): SVGElementTagNameMap[K] {
  const e = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
  return e;
}

export interface Series {
  name: string;
  color: string;
  points: { x: number; y: number }[];
  dashed?: boolean;
}

export interface LineChartOpts {
  series: Series[];
  width?: number;
  height?: number;
  xLabel?: string;
  yLabel?: string;
  xLog?: boolean;
  yMin?: number;
  yMax?: number;
  yInvert?: boolean;
  xTicks?: number[];
  xFormat?: (x: number) => string;
  yFormat?: (y: number) => string;
}

export function lineChart(o: LineChartOpts): HTMLElement {
  const W = o.width ?? 640;
  const H = o.height ?? 260;
  const pad = { l: 44, r: 14, t: 14, b: 34 };
  const svg = svgEl('svg', { viewBox: `0 0 ${W} ${H}`, class: 'chart' });
  const all = o.series.flatMap((s) => s.points);
  if (!all.length) {
    const t = svgEl('text', { x: W / 2, y: H / 2, 'text-anchor': 'middle', class: 'chart-empty' });
    t.textContent = 'Noch keine Daten';
    svg.appendChild(t);
    return h('div', { class: 'chart-wrap' }, svg as unknown as Node);
  }
  const xs = all.map((p) => (o.xLog ? Math.log2(p.x) : p.x));
  const ys = all.map((p) => p.y);
  let xMin = Math.min(...xs);
  let xMax = Math.max(...xs);
  if (xMin === xMax) {
    xMin -= 1;
    xMax += 1;
  }
  const yMin = o.yMin ?? Math.min(...ys);
  const yMax = o.yMax ?? Math.max(...ys);
  const span = yMax - yMin || 1;
  const sx = (x: number) => pad.l + ((o.xLog ? Math.log2(x) : x) - xMin) / (xMax - xMin) * (W - pad.l - pad.r);
  const sy = (y: number) => {
    const f = (y - yMin) / span;
    return o.yInvert ? pad.t + f * (H - pad.t - pad.b) : H - pad.b - f * (H - pad.t - pad.b);
  };

  // grid
  const yTicks = 5;
  for (let i = 0; i <= yTicks; i++) {
    const yv = yMin + (span * i) / yTicks;
    const y = sy(yv);
    svg.appendChild(svgEl('line', { x1: pad.l, x2: W - pad.r, y1: y, y2: y, class: 'grid' }));
    const t = svgEl('text', { x: pad.l - 6, y: y + 4, 'text-anchor': 'end', class: 'tick' });
    t.textContent = o.yFormat ? o.yFormat(yv) : String(Math.round(yv));
    svg.appendChild(t);
  }
  const xTicks = o.xTicks ?? (() => {
    const n = 5;
    const out: number[] = [];
    for (let i = 0; i <= n; i++) {
      const v = xMin + ((xMax - xMin) * i) / n;
      out.push(o.xLog ? Math.pow(2, v) : v);
    }
    return out;
  })();
  for (const xv of xTicks) {
    const x = sx(xv);
    svg.appendChild(svgEl('line', { x1: x, x2: x, y1: pad.t, y2: H - pad.b, class: 'grid' }));
    const t = svgEl('text', { x, y: H - pad.b + 16, 'text-anchor': 'middle', class: 'tick' });
    t.textContent = o.xFormat ? o.xFormat(xv) : String(Math.round(xv));
    svg.appendChild(t);
  }
  if (o.xLabel) {
    const t = svgEl('text', { x: (W + pad.l) / 2, y: H - 4, 'text-anchor': 'middle', class: 'axis-label' });
    t.textContent = o.xLabel;
    svg.appendChild(t);
  }
  if (o.yLabel) {
    const t = svgEl('text', { x: 12, y: pad.t + 4, class: 'axis-label', transform: `rotate(-90 12 ${pad.t + 4})`, 'text-anchor': 'end' });
    t.textContent = o.yLabel;
    svg.appendChild(t);
  }
  for (const s of o.series) {
    const pts = s.points.slice().sort((a, b) => a.x - b.x);
    if (pts.length > 1) {
      const d = pts.map((p, i) => `${i ? 'L' : 'M'}${sx(p.x).toFixed(1)} ${sy(p.y).toFixed(1)}`).join(' ');
      svg.appendChild(svgEl('path', { d, fill: 'none', stroke: s.color, 'stroke-width': 2, 'stroke-dasharray': s.dashed ? '5 4' : 'none' }));
    }
    for (const p of pts) svg.appendChild(svgEl('circle', { cx: sx(p.x), cy: sy(p.y), r: 3.5, fill: s.color }));
  }
  const legend = h(
    'div',
    { class: 'legend' },
    ...o.series.map((s) => h('span', { class: 'legend-item' }, h('i', { style: `background:${s.color}` }), s.name)),
  );
  return h('div', { class: 'chart-wrap' }, svg as unknown as Node, legend);
}

export function sparkBars(values: number[], max: number, color: string): HTMLElement {
  const W = 200, H = 40;
  const svg = svgEl('svg', { viewBox: `0 0 ${W} ${H}`, class: 'spark' });
  const n = Math.max(1, values.length);
  const bw = W / n;
  values.forEach((v, i) => {
    const hgt = (v / max) * (H - 2);
    svg.appendChild(svgEl('rect', { x: i * bw + 1, y: H - hgt, width: Math.max(1, bw - 2), height: hgt, fill: color, rx: 2 }));
  });
  return h('div', { class: 'spark-wrap' }, svg as unknown as Node);
}
