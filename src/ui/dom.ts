import { icon } from './icons';

export type Child = Node | string | number | null | undefined | false | Child[];

type Props = Record<string, unknown> & {
  class?: string;
  style?: Partial<CSSStyleDeclaration> | string;
  on?: Record<string, EventListener>;
};

export function h<K extends keyof HTMLElementTagNameMap>(tag: K, props?: Props | null, ...children: Child[]): HTMLElementTagNameMap[K];
export function h(tag: string, props?: Props | null, ...children: Child[]): HTMLElement;
export function h(tag: string, props?: Props | null, ...children: Child[]): HTMLElement {
  const el = document.createElement(tag);
  if (props) {
    for (const [k, v] of Object.entries(props)) {
      if (v === undefined || v === null || v === false) continue;
      if (k === 'class') el.className = String(v);
      else if (k === 'style') {
        if (typeof v === 'string') el.setAttribute('style', v);
        else Object.assign(el.style, v);
      } else if (k === 'on' && typeof v === 'object') {
        for (const [ev, fn] of Object.entries(v as Record<string, EventListener>)) el.addEventListener(ev, fn);
      } else if (k === 'html') el.innerHTML = String(v);
      else if (k in el && k !== 'list' && k !== 'form') (el as unknown as Record<string, unknown>)[k] = v;
      else el.setAttribute(k, String(v));
    }
  }
  append(el, children);
  return el;
}

export function append(el: Node, children: Child[]): void {
  for (const c of children) {
    if (c === null || c === undefined || c === false) continue;
    if (Array.isArray(c)) append(el, c);
    else if (c instanceof Node) el.appendChild(c);
    else el.appendChild(document.createTextNode(String(c)));
  }
}

export function clear(el: Element): void {
  while (el.firstChild) el.removeChild(el.firstChild);
}

export function swap(el: Element, ...children: Child[]): void {
  clear(el);
  append(el, children);
}

// ---------------------------------------------------------------- buttons

export interface BtnOpts {
  variant?: '' | 'sound' | 'mind' | 'lab' | 'tin' | 'ghost' | 'text';
  size?: '' | 'sm' | 'lg';
  block?: boolean;
  icon?: string;
  iconRight?: string;
  disabled?: boolean;
}

export function btn(label: Child, onClick: (e: MouseEvent) => void, o: BtnOpts = {}): HTMLButtonElement {
  const cls = ['btn', o.variant, o.size, o.block ? 'block' : ''].filter(Boolean).join(' ');
  const b = h('button', { class: cls, type: 'button', disabled: o.disabled }, o.icon ? icon(o.icon) : null, label, o.iconRight ? icon(o.iconRight) : null);
  b.addEventListener('click', (e) => onClick(e as MouseEvent));
  return b;
}

export function iconBtn(name: string, onClick: () => void, label: string): HTMLButtonElement {
  const b = h('button', { class: 'icon-btn', type: 'button', 'aria-label': label, title: label }, icon(name));
  b.addEventListener('click', onClick);
  return b;
}

// ---------------------------------------------------------------- layout

export function page(...children: Child[]): HTMLElement {
  return h('div', { class: 'page' }, ...children);
}

export function header(eyebrow: string | null, title: string, lead?: string | null): HTMLElement {
  return h('div', null, eyebrow ? h('p', { class: 'eyebrow' }, eyebrow) : null, h('h1', { class: 'title-xl' }, title), lead ? h('p', { class: 'lead' }, lead) : null);
}

export function card(cls: string | null, ...children: Child[]): HTMLElement {
  return h('section', { class: `card ${cls ?? ''}`.trim() }, ...children);
}

export function sectionH(title: string, right?: Child): HTMLElement {
  return h('div', { class: 'section-h' }, h('h3', null, title), right ?? null);
}

export function callout(text: Child, kind: 'info' | 'warn' | 'good' = 'info'): HTMLElement {
  return h('div', { class: `callout ${kind}` }, icon(kind === 'warn' ? 'alert' : kind === 'good' ? 'check' : 'info'), h('div', null, text));
}

export function chip(text: Child, kind = ''): HTMLElement {
  return h('span', { class: `chip ${kind}`.trim() }, text);
}

export function metric(k: string, v: Child, unit?: string): HTMLElement {
  const isText = typeof v === 'string' && /[a-zA-ZäöüÄÖÜ]{3,}/.test(v);
  return h('div', { class: 'metric' }, h('div', { class: 'k' }, k), h('div', { class: `v ${isText ? 'txt' : ''}` }, v, unit ? h('small', null, unit) : null));
}

/** Evidence level 1–4 → dots. */
export function evidence(level: 1 | 2 | 3 | 4, label?: string): HTMLElement {
  const names = { 1: 'Experimentell', 2: 'Schwach', 3: 'Mittel', 4: 'Stark' } as const;
  return h('span', { class: `evidence e${level}` },
    h('span', { class: 'dots' }, ...[1, 2, 3, 4].map((i) => h('i', { class: i <= level ? 'on' : '' }))),
    label ?? `Evidenz: ${names[level]}`);
}

export function progress(total: number, done: number): HTMLElement {
  return h('div', { class: 'progress' }, ...Array.from({ length: total }, (_, i) => h('i', { class: i < done ? 'on' : '' })));
}

// ---------------------------------------------------------------- inputs

export interface RangeOpts {
  label: string;
  min: number;
  max: number;
  step?: number;
  value: number;
  format?: (v: number) => string;
  onInput: (v: number) => void;
  onChange?: (v: number) => void;
  color?: string;
  big?: boolean;
  scale?: [string, string];
}

export function range(o: RangeOpts): { el: HTMLElement; input: HTMLInputElement; set(v: number): void } {
  const fmt = o.format ?? ((v: number) => String(v));
  const val = h('span', { class: 'val' }, fmt(o.value));
  const input = h('input', { type: 'range', class: `rng ${o.big ? 'big' : ''}`, min: o.min, max: o.max, step: o.step ?? 1, value: o.value }) as HTMLInputElement;
  if (o.color) input.style.setProperty('--c', o.color);
  const paint = () => {
    const p = ((Number(input.value) - o.min) / (o.max - o.min)) * 100;
    input.style.setProperty('--pct', `${p}%`);
  };
  paint();
  input.addEventListener('input', () => {
    const v = Number(input.value);
    val.textContent = fmt(v);
    paint();
    o.onInput(v);
  });
  input.addEventListener('change', () => o.onChange?.(Number(input.value)));
  const el = h('div', { class: 'field' },
    h('div', { class: 'field-head' }, h('span', { class: 'lbl' }, o.label), val),
    input,
    o.scale ? h('div', { class: 'rng-scale' }, h('span', null, o.scale[0]), h('span', null, o.scale[1])) : null);
  return {
    el,
    input,
    set(v: number) {
      input.value = String(v);
      val.textContent = fmt(v);
      paint();
    },
  };
}

export function seg<T extends string>(options: { value: T; label: string }[], value: T, onChange: (v: T) => void): { el: HTMLElement; set(v: T): void } {
  const map = new Map<T, HTMLButtonElement>();
  const el = h('div', { class: 'seg', role: 'tablist' });
  const set = (v: T) => map.forEach((b, k) => b.classList.toggle('on', k === v));
  for (const o of options) {
    const b = h('button', { type: 'button' }, o.label);
    b.addEventListener('click', () => {
      set(o.value);
      onChange(o.value);
    });
    map.set(o.value, b);
    el.appendChild(b);
  }
  set(value);
  return { el, set };
}

export function choices<T extends string>(options: { value: T; title: string; sub?: string; icon?: string }[], value: T | null, onChange: (v: T) => void): HTMLElement {
  const el = h('div', { class: 'choices' });
  const btns: HTMLButtonElement[] = [];
  options.forEach((o) => {
    const b = h('button', { type: 'button', class: `choice ${o.value === value ? 'on' : ''}` },
      h('span', { class: 'radio' }),
      h('span', { class: 'grow' }, h('div', { class: 'ttl' }, o.title), o.sub ? h('div', { class: 'sub' }, o.sub) : null),
      o.icon ? icon(o.icon) : null);
    b.addEventListener('click', () => {
      btns.forEach((x) => x.classList.remove('on'));
      b.classList.add('on');
      onChange(o.value);
    });
    btns.push(b);
    el.appendChild(b);
  });
  return el;
}

/** 0–10 rating scale with colour-coded buttons. */
export function scale10(value: number | null, onPick: (v: number) => void, legend: [string, string] = ['still', 'unerträglich']): HTMLElement {
  const row = h('div', { class: 'scale' });
  for (let i = 0; i <= 10; i++) {
    const b = h('button', { type: 'button', style: `--i:${i}`, class: value === i ? 'on' : '' }, String(i));
    b.addEventListener('click', () => {
      row.querySelectorAll('button').forEach((x) => x.classList.remove('on'));
      b.classList.add('on');
      onPick(i);
    });
    row.appendChild(b);
  }
  return h('div', null, row, h('div', { class: 'scale-legend' }, h('span', null, legend[0]), h('span', null, legend[1])));
}

export function toggle(label: string, checked: boolean, onChange: (v: boolean) => void): HTMLElement {
  const input = h('input', { type: 'checkbox', checked }) as HTMLInputElement;
  input.addEventListener('change', () => onChange(input.checked));
  return h('label', { class: 'toggle' }, h('span', null, label), input, h('span', { class: 'sw' }));
}

// ---------------------------------------------------------------- overlays

export function toast(msg: string, ico = 'check'): void {
  document.querySelectorAll('.toast').forEach((t) => t.remove());
  const t = h('div', { class: 'toast', role: 'status' }, icon(ico), msg);
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 2400);
}

export function sheet(build: (close: () => void) => Child): () => void {
  const scrim = h('div', { class: 'scrim' });
  const panel = h('div', { class: 'sheet', role: 'dialog' }, h('div', { class: 'grabber' }));
  const close = () => {
    scrim.remove();
    panel.remove();
  };
  scrim.addEventListener('click', close);
  append(panel, [build(close)]);
  document.body.append(scrim, panel);
  return close;
}

// ---------------------------------------------------------------- formatting

export function fmtDuration(s: number): string {
  const m = Math.floor(s / 60);
  const sec = Math.floor(s % 60);
  return `${m}:${String(sec).padStart(2, '0')}`;
}

export function fmtDate(iso: string, opts: Intl.DateTimeFormatOptions = { day: 'numeric', month: 'short' }): string {
  return new Date(iso).toLocaleDateString('de-DE', opts);
}

export function median(xs: number[]): number {
  if (!xs.length) return NaN;
  const s = xs.slice().sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

export function geoMedian(xs: number[]): number {
  return Math.pow(2, median(xs.map((x) => Math.log2(x))));
}

export function mean(xs: number[]): number {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN;
}

export function shuffle<T>(arr: T[]): T[] {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export function wait(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
