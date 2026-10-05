import { h, btn, page, header, card, seg, swap, range, toggle, sectionH, callout, chip, mean, toast, fmtDate, metric } from '../ui/dom';
import { lineChart } from '../ui/chart';
import { store, uid, today, dayKey } from '../data/store';
import { JournalEntry } from '../data/model';
import { Params } from '../router';
import { MODES, modeTitle } from './therapy';

type Tab = 'overview' | 'journal' | 'weekly';

export function renderProgress(root: HTMLElement, params: Params): void {
  let tab: Tab = (params.tab as Tab) || 'overview';
  const body = h('div');
  const tabs = seg<Tab>([{ value: 'overview', label: 'Übersicht' }, { value: 'journal', label: 'Tag' }, { value: 'weekly', label: 'Woche' }], tab, (v) => { tab = v; draw(); });
  root.appendChild(page(header('Verlauf', 'Was sich verändert'), tabs.el, h('div', { class: 'mt16' }, body)));
  const draw = () => swap(body, tab === 'overview' ? overview() : tab === 'journal' ? journal(() => { tab = 'overview'; tabs.set('overview'); draw(); }) : weekly(draw));
  draw();
}

// ------------------------------------------------------------------------------------ overview

function daily(days: number) {
  const d = store.get();
  const out: { x: number; loud: number | null; dist: number | null }[] = [];
  for (let i = days - 1; i >= 0; i--) {
    const date = new Date(Date.now() - i * 86400e3);
    const k = dayKey(date);
    const cis = d.checkins.filter((c) => dayKey(new Date(c.ts)) === k);
    const j = d.journal.find((x) => x.date === k);
    const l = cis.map((c) => c.loudness).concat(j ? [j.loudness] : []);
    const ds = cis.map((c) => c.distress).concat(j ? [j.distress] : []);
    out.push({ x: date.setHours(12, 0, 0, 0), loud: l.length ? mean(l) : null, dist: ds.length ? mean(ds) : null });
  }
  return out;
}

/** Mean and approximate 95 % CI (t ≈ 2 for small n, 1.96 for large). */
function ci(xs: number[]): { m: number; lo: number; hi: number } {
  const m = mean(xs);
  if (xs.length < 2) return { m, lo: m, hi: m };
  const sd = Math.sqrt(xs.reduce((a, x) => a + (x - m) ** 2, 0) / (xs.length - 1));
  const t = xs.length < 10 ? 2.26 : 2;
  const se = (t * sd) / Math.sqrt(xs.length);
  return { m, lo: m - se, hi: m + se };
}

function overview(): HTMLElement {
  const d = store.get();
  const days = daily(30);
  const has = days.some((x) => x.loud !== null);
  const xFmt = (x: number) => new Date(x).toLocaleDateString('de-DE', { day: 'numeric', month: 'numeric' });
  const last7 = days.slice(-7).map((x) => x.loud).filter((v): v is number => v !== null);
  const prev7 = days.slice(-14, -7).map((x) => x.loud).filter((v): v is number => v !== null);

  const out = h('div');
  out.append(
    h('div', { class: 'grid-3' },
      metric('Ø 7 Tage', last7.length ? mean(last7).toFixed(1) : '–'),
      metric('Vorwoche', prev7.length ? mean(prev7).toFixed(1) : '–'),
      metric('Therapie', String(Math.round(d.sessions.filter((s) => Date.now() - new Date(s.date).getTime() < 7 * 86400e3).reduce((a, s) => a + s.durationS, 0) / 60)), 'min')),
    card('mt16',
      h('p', { class: 'title-m' }, 'Lautheit und Belastung, 30 Tage'),
      has ? lineChart({
        series: [
          { name: 'Lautheit', color: 'var(--tin)', area: true, points: days.filter((x) => x.loud !== null).map((x) => ({ x: x.x, y: x.loud! })) },
          { name: 'Belastung', color: 'var(--mind)', points: days.filter((x) => x.dist !== null).map((x) => ({ x: x.x, y: x.dist! })) },
        ], yMin: 0, yMax: 10, yTicks: [0, 5, 10], xFormat: xFmt, height: 200,
      }) : h('p', { class: 'small' }, 'Noch keine Daten. Mach Check-ins über den Tag und einen Tagesrückblick am Abend.')),
  );

  // MML over time: a more objective marker than self-rated loudness
  if (d.matches.filter((m) => m.mmlDb !== null).length >= 2) {
    out.append(card(null, h('p', { class: 'title-m' }, 'Maskierungsschwelle (MML)'), h('p', { class: 'small', style: 'margin:0 0 6px' }, 'Niedriger = Tinnitus lässt sich leichter verdecken. Wiederhole die Messung alle 2–4 Wochen.'),
      lineChart({ series: [{ name: 'MML', color: 'var(--lab)', points: d.matches.filter((m) => m.mmlDb !== null).map((m) => ({ x: new Date(m.date).getTime(), y: m.mmlDb! })) }], xFormat: xFmt, height: 160, legend: false })));
  }

  // What works for me
  out.append(sectionH('Was wirkt bei dir?'));
  const rows: HTMLElement[] = [];
  for (const m of MODES) {
    const ss = d.sessions.filter((s) => s.mode === m.mode && s.pre !== null && s.post !== null);
    if (!ss.length) continue;
    const c = ci(ss.map((s) => (s.post as number) - (s.pre as number)));
    const sure = ss.length >= 5 && c.hi < 0;
    rows.push(h('li', null,
      h('div', { class: 'li-main' }, h('div', { class: 'li-title' }, m.title), h('div', { class: 'li-sub' }, ss.length >= 3 ? `${ss.length} Sitzungen · 95 %-Bereich ${c.lo.toFixed(1)} bis ${c.hi.toFixed(1)}` : `${ss.length} ${ss.length === 1 ? 'Sitzung' : 'Sitzungen'} · noch zu wenig für eine Aussage`)),
      chip(`${c.m >= 0 ? '+' : ''}${c.m.toFixed(1)}`, sure ? 'good' : c.m > 0.5 ? 'warn' : '')));
  }
  out.append(rows.length
    ? card(null, h('p', { class: 'small', style: 'margin:0' }, 'Veränderung der Lautheit direkt nach der Sitzung (nachher − vorher). Grün = bei dir verlässlich wirksam (mindestens 5 Sitzungen, ganzer Bereich unter 0).'), h('ul', { class: 'list' }, ...rows))
    : callout('Sobald du Sitzungen mit Vorher-/Nachher-Bewertung machst, siehst du hier, welcher Klang bei dir kurzfristig wirkt.'));

  // Day-level: therapy days vs non-therapy days
  const k = (date: string) => dayKey(new Date(date));
  const therapyDays = new Set(d.sessions.filter((s) => s.durationS >= 600).map((s) => k(s.date)));
  const withT = days.filter((x) => x.loud !== null && therapyDays.has(dayKey(new Date(x.x)))).map((x) => x.loud!);
  const without = days.filter((x) => x.loud !== null && !therapyDays.has(dayKey(new Date(x.x)))).map((x) => x.loud!);
  if (withT.length >= 3 && without.length >= 3) {
    const diff = mean(withT) - mean(without);
    out.append(card(null, h('p', { class: 'title-m' }, 'Tage mit vs. ohne Therapie'),
      h('div', { class: 'grid-2' }, metric(`Mit (${withT.length} T.)`, mean(withT).toFixed(1)), metric(`Ohne (${without.length} T.)`, mean(without).toFixed(1))),
      h('p', { class: 'small mt8' }, `Unterschied ${diff >= 0 ? '+' : ''}${diff.toFixed(1)} Punkte. Achtung: Das ist eine Beobachtung, kein Experiment. Vielleicht machst du an guten Tagen einfach mehr Therapie.`)));
  }

  // Time of day (EMA)
  if (d.checkins.length >= 8) {
    const slots = [['Nacht', 0, 6], ['Morgen', 6, 11], ['Mittag', 11, 16], ['Abend', 16, 24]] as const;
    out.append(card(null, h('p', { class: 'title-m' }, 'Tageszeit'), h('p', { class: 'small', style: 'margin:0 0 8px' }, 'Studien mit Alltagsmessungen zeigen: Tinnitus wirkt nachts und frühmorgens meist lauter. Wie ist es bei dir?'),
      h('div', { class: 'grid-2' }, ...slots.map(([lbl, a, b]) => {
        const v = d.checkins.filter((c) => { const hr = new Date(c.ts).getHours(); return hr >= a && hr < b; }).map((c) => c.loudness);
        return metric(lbl, v.length ? mean(v).toFixed(1) : '–', v.length ? `n=${v.length}` : undefined);
      }))));
  }

  // Triggers
  const j = d.journal;
  if (j.length >= 7) out.append(triggers(j));

  return out;
}

function triggers(j: JournalEntry[]): HTMLElement {
  const items: HTMLElement[] = [];
  const flag = (label: string, key: 'noiseExposure' | 'caffeine' | 'alcohol') => {
    const w = j.filter((e) => e[key]).map((e) => e.loudness);
    const wo = j.filter((e) => !e[key]).map((e) => e.loudness);
    if (w.length >= 2 && wo.length >= 2) {
      const dlt = mean(w) - mean(wo);
      items.push(h('li', null, h('div', { class: 'li-main' }, h('div', { class: 'li-title' }, label), h('div', { class: 'li-sub' }, `${w.length} Tage mit, ${wo.length} ohne`)), chip(`${dlt >= 0 ? '+' : ''}${dlt.toFixed(1)}`, dlt > 0.7 ? 'warn' : dlt < -0.7 ? 'good' : '')));
    }
  };
  flag('Lärm', 'noiseExposure');
  flag('Koffein', 'caffeine');
  flag('Alkohol', 'alcohol');
  const pear = (xs: number[], ys: number[]) => {
    const mx = mean(xs), my = mean(ys);
    let n = 0, dx = 0, dy = 0;
    for (let i = 0; i < xs.length; i++) { n += (xs[i] - mx) * (ys[i] - my); dx += (xs[i] - mx) ** 2; dy += (ys[i] - my) ** 2; }
    return dx && dy ? n / Math.sqrt(dx * dy) : 0;
  };
  const rs = pear(j.map((e) => e.sleep), j.map((e) => e.loudness));
  const rt = pear(j.map((e) => e.stress), j.map((e) => e.loudness));
  const desc = (r: number) => (Math.abs(r) < 0.2 ? 'kein Zusammenhang' : Math.abs(r) < 0.4 ? 'schwach' : Math.abs(r) < 0.6 ? 'mittel' : 'stark');
  items.push(h('li', null, h('div', { class: 'li-main' }, h('div', { class: 'li-title' }, 'Guter Schlaf ↔ Lautheit'), h('div', { class: 'li-sub' }, desc(rs))), chip(`r = ${rs.toFixed(2)}`, rs < -0.3 ? 'good' : '')));
  items.push(h('li', null, h('div', { class: 'li-main' }, h('div', { class: 'li-title' }, 'Stress ↔ Lautheit'), h('div', { class: 'li-sub' }, desc(rt))), chip(`r = ${rt.toFixed(2)}`, rt > 0.3 ? 'warn' : '')));
  return h('div', null, sectionH('Auslöser'), card(null, h('p', { class: 'small', style: 'margin:0' }, 'Unterschied der Lautheit an Tagen mit gegenüber ohne Faktor. Auslöser sind sehr individuell; deshalb zählen hier nur deine Daten.'), h('ul', { class: 'list' }, ...items)));
}

// ------------------------------------------------------------------------------------ journal

function journal(onSaved: () => void): HTMLElement {
  const t = today();
  const d = store.get();
  const ex = d.journal.find((j) => j.date === t);
  const e: JournalEntry = ex ? { ...ex } : { id: uid(), date: t, loudness: 5, distress: 5, sleep: 5, stress: 5, noiseExposure: false, caffeine: false, alcohol: false, notes: '' };
  const r = (label: string, key: 'loudness' | 'distress' | 'sleep' | 'stress', scale: [string, string], color: string) =>
    range({ label, min: 0, max: 10, value: e[key], color, scale, onInput: (v) => (e[key] = v) }).el;
  const notes = h('textarea', { rows: 3, placeholder: 'Notizen: Besonderheiten, Auslöser, was gut war …' }) as HTMLTextAreaElement;
  notes.value = e.notes;
  notes.addEventListener('input', () => (e.notes = notes.value));
  const recent = d.journal.slice(-7).reverse();
  return h('div', null,
    h('p', { class: 'body' }, ex ? 'Heutiger Eintrag, du kannst ihn bearbeiten.' : 'Einmal am Abend, eine Minute. Daraus werden später deine Auslöser-Analysen.'),
    card(null,
      r('Lautheit heute im Schnitt', 'loudness', ['still', 'extrem'], 'var(--tin)'),
      r('Belastung heute', 'distress', ['gar nicht', 'extrem'], 'var(--mind)'),
      r('Schlaf letzte Nacht', 'sleep', ['sehr schlecht', 'sehr gut'], 'var(--lab)'),
      r('Stress heute', 'stress', ['entspannt', 'sehr gestresst'], 'var(--warn)')),
    card(null,
      toggle('Lärm ausgesetzt', e.noiseExposure, (v) => (e.noiseExposure = v)),
      toggle('Koffein', e.caffeine, (v) => (e.caffeine = v)),
      toggle('Alkohol', e.alcohol, (v) => (e.alcohol = v))),
    card(null, notes),
    btn('Speichern', () => {
      store.update((s) => {
        const i = s.journal.findIndex((x) => x.date === t);
        if (i >= 0) s.journal[i] = e; else s.journal.push(e);
        s.journal.sort((a, b) => a.date.localeCompare(b.date));
      });
      toast('Tagesrückblick gespeichert');
      onSaved();
    }, { size: 'lg', block: true }),
    recent.length ? sectionH('Letzte Tage') : null,
    recent.length ? card(null, h('ul', { class: 'list' }, ...recent.map((j) => h('li', null,
      h('div', { class: 'li-main' }, h('div', { class: 'li-title' }, fmtDate(j.date + 'T12:00:00', { weekday: 'short', day: 'numeric', month: 'short' })), h('div', { class: 'li-sub' }, [j.noiseExposure && 'Lärm', j.caffeine && 'Koffein', j.alcohol && 'Alkohol'].filter(Boolean).join(' · ') || j.notes.slice(0, 40) || '–')),
      chip(`${j.loudness}`, 'tin'), chip(`${j.distress}`, 'mind'))))) : null);
}

// ------------------------------------------------------------------------------------ weekly

const WEEKLY = [
  'Wie oft hast du den Tinnitus bewusst wahrgenommen?',
  'Wie stark hat er Ein- oder Durchschlafen gestört?',
  'Wie stark hat er deine Konzentration beeinträchtigt?',
  'Wie sehr hat er dich verärgert oder gestresst?',
  'Wie sehr hast du ruhige Situationen gemieden?',
  'Wie stark hat er Gespräche oder Hören gestört?',
  'Wie entmutigt hast du dich wegen des Tinnitus gefühlt?',
  'Wie stark hat er deine Lebensqualität beeinträchtigt?',
];
const SCALE = ['Gar nicht', 'Wenig', 'Mäßig', 'Stark', 'Extrem'];

function weekly(redraw: () => void): HTMLElement {
  const d = store.get();
  const last = d.weekly[d.weekly.length - 1];
  const due = !last || Date.now() - new Date(last.date).getTime() > 6 * 86400e3;
  const ans: number[] = new Array(WEEKLY.length).fill(-1);
  const out = h('div', null,
    h('p', { class: 'body' }, 'Acht Fragen zur Belastung der letzten 7 Tage, 0–100 Punkte, niedriger ist besser. Kein klinisch validierter Fragebogen, aber gut für deinen eigenen Verlauf. Für eine offizielle Einstufung frag beim HNO nach dem Mini-TQ oder THI.'),
    d.weekly.length > 1 ? card(null, lineChart({ series: [{ name: 'Score', color: 'var(--mind)', area: true, points: d.weekly.map((w) => ({ x: new Date(w.date).getTime(), y: w.score })) }], yMin: 0, yMax: 100, yTicks: [0, 50, 100], height: 170, legend: false, xFormat: (x) => new Date(x).toLocaleDateString('de-DE', { day: 'numeric', month: 'numeric' }) })) : null,
    last ? card('tight', h('div', { class: 'row between' }, h('span', null, `Letzter Check ${fmtDate(last.date)}`), chip(`${last.score} Punkte`, 'mind'))) : null);
  if (!due) {
    out.append(callout('Der nächste Wochen-Check ist in ein paar Tagen fällig.', 'good'));
    return out;
  }
  WEEKLY.forEach((q, i) => {
    const row = h('div', { class: 'seg', style: 'flex-wrap:wrap' });
    SCALE.forEach((lbl, v) => {
      const b = h('button', { type: 'button' }, lbl);
      b.addEventListener('click', () => { row.querySelectorAll('button').forEach((x) => x.classList.remove('on')); b.classList.add('on'); ans[i] = v; });
      row.appendChild(b);
    });
    out.append(card(null, h('p', { class: 'title-m' }, `${i + 1}. ${q}`), row));
  });
  out.append(btn('Wochen-Check speichern', () => {
    if (ans.some((a) => a < 0)) { toast('Bitte alle Fragen beantworten', 'info'); return; }
    const score = Math.round((ans.reduce((a, b) => a + b, 0) / (4 * WEEKLY.length)) * 100);
    store.update((s) => s.weekly.push({ id: uid(), date: new Date().toISOString(), answers: ans.slice(), score }));
    toast(`Gespeichert: ${score} Punkte`);
    redraw();
  }, { variant: 'mind', size: 'lg', block: true }));
  return out;
}

void modeTitle;
