type Child = Node | string | number | null | undefined | false | Child[];

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

function append(el: Node, children: Child[]): void {
  for (const c of children) {
    if (c === null || c === undefined || c === false) continue;
    if (Array.isArray(c)) append(el, c);
    else if (c instanceof Node) el.appendChild(c);
    else el.appendChild(document.createTextNode(String(c)));
  }
}

export function clear(el: HTMLElement): void {
  while (el.firstChild) el.removeChild(el.firstChild);
}

export function button(label: string, onClick: (e: MouseEvent) => void, cls = 'btn'): HTMLButtonElement {
  return h('button', { class: cls, type: 'button', on: { click: onClick as EventListener } }, label);
}

export interface SliderOpts {
  min: number;
  max: number;
  step?: number;
  value: number;
  label: string;
  format?: (v: number) => string;
  onInput: (v: number) => void;
  onChange?: (v: number) => void;
}

export function slider(o: SliderOpts): { el: HTMLElement; set(v: number): void; get(): number } {
  const out = h('span', { class: 'slider-value' }, (o.format ?? String)(o.value));
  const input = h('input', {
    type: 'range',
    min: o.min,
    max: o.max,
    step: o.step ?? 1,
    value: o.value,
  }) as HTMLInputElement;
  input.addEventListener('input', () => {
    const v = Number(input.value);
    out.textContent = (o.format ?? String)(v);
    o.onInput(v);
  });
  input.addEventListener('change', () => o.onChange?.(Number(input.value)));
  const el = h('label', { class: 'slider' }, h('span', { class: 'slider-label' }, o.label, out), input);
  return {
    el,
    set(v: number) {
      input.value = String(v);
      out.textContent = (o.format ?? String)(v);
    },
    get: () => Number(input.value),
  };
}

export function segmented<T extends string>(options: { value: T; label: string }[], value: T, onChange: (v: T) => void): { el: HTMLElement; set(v: T): void } {
  const btns = new Map<T, HTMLButtonElement>();
  const el = h('div', { class: 'segmented' });
  const set = (v: T) => {
    for (const [k, b] of btns) b.classList.toggle('active', k === v);
  };
  for (const o of options) {
    const b = button(o.label, () => {
      set(o.value);
      onChange(o.value);
    }, 'seg');
    btns.set(o.value, b);
    el.appendChild(b);
  }
  set(value);
  return { el, set };
}

export function card(title: string | null, ...children: Child[]): HTMLElement {
  return h('section', { class: 'card' }, title ? h('h2', null, title) : null, ...children);
}

export function note(text: string, kind: 'info' | 'warn' | 'ok' = 'info'): HTMLElement {
  return h('p', { class: `note note-${kind}` }, text);
}

export function fmtDuration(s: number): string {
  const m = Math.floor(s / 60);
  const sec = Math.floor(s % 60);
  return `${m}:${String(sec).padStart(2, '0')}`;
}

export function fmtDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: '2-digit' });
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
