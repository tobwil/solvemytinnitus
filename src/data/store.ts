import { AppData, emptyData } from './model';

const KEY = 'solvemytinnitus.v1';

type Listener = (data: AppData) => void;

class Store {
  private data: AppData;
  private listeners = new Set<Listener>();

  constructor() {
    this.data = this.load();
  }

  private load(): AppData {
    try {
      const raw = localStorage.getItem(KEY);
      if (!raw) return emptyData();
      const parsed = JSON.parse(raw) as Partial<AppData>;
      const base = emptyData();
      return {
        ...base,
        ...parsed,
        settings: { ...base.settings, ...(parsed.settings ?? {}) },
      } as AppData;
    } catch {
      return emptyData();
    }
  }

  get(): AppData {
    return this.data;
  }

  update(fn: (d: AppData) => void): void {
    fn(this.data);
    this.persist();
  }

  replace(data: AppData): void {
    this.data = data;
    this.persist();
  }

  reset(): void {
    this.data = emptyData();
    this.persist();
  }

  private persist(): void {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.data));
    } catch (e) {
      console.warn('Konnte Daten nicht speichern', e);
    }
    for (const l of this.listeners) l(this.data);
  }

  subscribe(l: Listener): () => void {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  }

  exportJson(): string {
    return JSON.stringify(this.data, null, 2);
  }

  importJson(json: string): void {
    const parsed = JSON.parse(json) as AppData;
    if (parsed.version !== 1) throw new Error('Unbekanntes Datenformat');
    this.replace({ ...emptyData(), ...parsed });
  }

  /** Latest tinnitus match, optionally for a specific ear. */
  latestMatch(ear?: 'left' | 'right' | 'both') {
    const list = ear ? this.data.matches.filter((m) => m.ear === ear) : this.data.matches;
    return list.length ? list[list.length - 1] : null;
  }

  latestHearing() {
    const h = this.data.hearingTests;
    return h.length ? h[h.length - 1] : null;
  }
}

export const store = new Store();

export function uid(): string {
  return Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
}

export function today(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
