import { AppData, emptyData } from './model';

const KEY = 'solvemytinnitus.v1';

type Listener = (data: AppData) => void;

function migrate(parsed: Omit<Partial<AppData>, 'version'> & { version?: number }): AppData {
  const base = emptyData();
  const merged = {
    ...base,
    ...parsed,
    version: 2,
    settings: { ...base.settings, ...(parsed.settings ?? {}) },
    mind: { ...base.mind, ...(parsed.mind ?? {}) },
  } as AppData;
  // v1 had a 'bimodal' therapy mode that was removed
  merged.sessions = merged.sessions.filter((s) => ['reset', 'notched', 'enrichment', 'cr'].includes(s.mode));
  merged.riTrials = merged.riTrials.map((t) => ({ ...t, blind: t.blind ?? false }));
  // users who already measured something on v1 don't need onboarding again
  if (parsed.version === 1 && (merged.matches.length || merged.journal.length)) merged.settings.onboarded = true;
  return merged;
}

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
      return migrate(JSON.parse(raw));
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
    const parsed = JSON.parse(json);
    if (parsed.version !== 1 && parsed.version !== 2) throw new Error('Unbekanntes Datenformat');
    this.data = migrate(parsed);
    this.persist();
  }

  latestMatch(ear?: 'left' | 'right' | 'both') {
    const list = ear ? this.data.matches.filter((m) => m.ear === ear) : this.data.matches;
    return list.length ? list[list.length - 1] : null;
  }

  latestSpectrum() {
    const s = this.data.spectra;
    return s.length ? s[s.length - 1] : null;
  }

  latestHearing() {
    const h = this.data.hearingTests;
    return h.length ? h[h.length - 1] : null;
  }

  latestSomatic() {
    const s = this.data.somatic;
    return s.length ? s[s.length - 1] : null;
  }
}

export const store = new Store();

export function uid(): string {
  return Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
}

export function dayKey(d: Date = new Date()): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export const today = () => dayKey();
