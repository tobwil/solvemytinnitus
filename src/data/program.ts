import { store, today, dayKey } from './store';

export interface LabStep {
  id: string;
  title: string;
  sub: string;
  path: string;
  done: boolean;
  meta?: string;
}

export const RI_TARGET = 12; // 6 stimuli × 2 repetitions

export function labSteps(): LabStep[] {
  const d = store.get();
  const spec = store.latestSpectrum();
  const m = store.latestMatch();
  const hear = store.latestHearing();
  const som = store.latestSomatic();
  return [
    { id: 'phones', title: 'Kopfhörer-Check', sub: 'Links/rechts korrekt, Lautstärke eingestellt', path: '/onboarding?step=2', done: d.settings.headphonesOk },
    { id: 'spectrum', title: 'Tinnitus-Spektrum', sub: 'Ähnlichkeit von 11 Tönen bewerten – robuster als reines Pitch-Matching', path: '/spectrum', done: !!spec, meta: spec ? `Peak ${fmtK(spec.peak)}` : undefined },
    { id: 'match', title: 'Tonhöhe, Lautheit, Maskierung', sub: 'Feinabstimmung auf dem Frequenz-Pad, Oktaven-Check, MML', path: '/match', done: !!m, meta: m ? `${fmtK(m.freq)} · MML ${m.mmlDb ?? '–'} dB` : undefined },
    { id: 'hearing', title: 'Hörprofil', sub: 'Schwellen 0,5–16 kHz pro Ohr', path: '/hearing', done: !!hear },
    { id: 'somatic', title: 'Somatik-Check', sub: 'Lässt sich dein Tinnitus über Kiefer oder Nacken verändern?', path: '/somatic', done: !!som, meta: som ? (som.somatic ? 'somatisch modulierbar' : 'nicht modulierbar') : undefined },
    { id: 'ri', title: 'Residual-Inhibition-Labor', sub: '6 Stimuli × 2 Durchgänge, verblindet', path: '/ri', done: d.riTrials.length >= RI_TARGET, meta: d.riTrials.length ? `${Math.min(d.riTrials.length, RI_TARGET)}/${RI_TARGET} Durchgänge` : undefined },
  ];
}

export function nextLabStep(): LabStep | null {
  return labSteps().find((s) => !s.done) ?? null;
}

export function programWeek(): number {
  const start = store.get().settings.programStart;
  if (!start) return 1;
  const days = Math.floor((Date.now() - new Date(start).getTime()) / 86400e3);
  return Math.max(1, Math.floor(days / 7) + 1);
}

export function programDay(): number {
  const start = store.get().settings.programStart;
  if (!start) return 1;
  return Math.max(1, Math.floor((Date.now() - new Date(start).getTime()) / 86400e3) + 1);
}

export interface Task {
  id: string;
  title: string;
  sub: string;
  path: string;
  done: boolean;
  kind: 'lab' | 'sound' | 'mind' | 'tin';
  icon: string;
}

export function todayTasks(): Task[] {
  const d = store.get();
  const t = today();
  const ci = d.checkins.filter((c) => dayKey(new Date(c.ts)) === t).length;
  const sessionsToday = d.sessions.filter((s) => dayKey(new Date(s.date)) === t);
  const resetCount = sessionsToday.filter((s) => s.mode === 'reset').length;
  const soundMin = Math.round(sessionsToday.filter((s) => s.mode !== 'reset').reduce((a, s) => a + s.durationS, 0) / 60);
  const lab = nextLabStep();
  const tasks: Task[] = [];

  tasks.push({ id: 'checkin', title: 'Kurz-Check-in', sub: `${Math.min(ci, 3)} von 3 heute · morgens, mittags, abends`, path: '/checkin', done: ci >= 3, kind: 'tin', icon: 'pulse' });

  if (lab) tasks.push({ id: 'lab', title: lab.title, sub: 'Nächster Mess-Schritt', path: lab.path, done: false, kind: 'lab', icon: 'lab' });

  const therapyReady = !!store.latestMatch();
  if (therapyReady) {
    tasks.push({ id: 'reset', title: 'Reset-Sitzung', sub: `${Math.min(resetCount, 2)} von 2 · je 10–15 min mit deinem RI-Klang`, path: '/therapy?mode=reset', done: resetCount >= 2, kind: 'sound', icon: 'wave' });
    tasks.push({ id: 'sound', title: 'Klangtherapie', sub: `${soundMin} von ${d.settings.dailyGoalMin} min · Notched oder Anreicherung`, path: '/therapy', done: soundMin >= d.settings.dailyGoalMin, kind: 'sound', icon: 'note' });
  }

  const mindToday = d.mind.exercises.some((e) => dayKey(new Date(e.date)) === t);
  tasks.push({ id: 'mind', title: 'Kopf-Training', sub: 'Eine Lektion oder Übung, 5–10 min', path: '/mind', done: mindToday, kind: 'mind', icon: 'mind' });

  const journalDone = d.journal.some((j) => j.date === t);
  tasks.push({ id: 'journal', title: 'Tagesrückblick', sub: 'Schlaf, Stress, Auslöser', path: '/progress?tab=journal', done: journalDone, kind: 'tin', icon: 'pen' });
  return tasks;
}

function fmtK(f: number): string {
  return f >= 1000 ? `${(f / 1000).toFixed(f >= 10000 ? 1 : 2)} kHz` : `${Math.round(f)} Hz`;
}
