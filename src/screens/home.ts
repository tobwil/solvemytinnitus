import { h, page, card, btn, chip, sectionH, metric, mean, fmtDate } from '../ui/dom';
import { icon } from '../ui/icons';
import { sparkline, ring } from '../ui/chart';
import { store, dayKey } from '../data/store';
import { formatHz } from '../audio/engine';
import { navigate } from '../router';
import { todayTasks, programWeek, programDay, nextLabStep } from '../data/program';
import { bestRiStimulus, describeStimulus } from './ri';

export function renderHome(root: HTMLElement): void {
  const d = store.get();
  const hour = new Date().getHours();
  const greet = hour < 11 ? 'Guten Morgen' : hour < 18 ? 'Hallo' : 'Guten Abend';
  const tasks = todayTasks();
  const done = tasks.filter((t) => t.done).length;
  const week = programWeek();
  const m = store.latestMatch();
  const best = bestRiStimulus(d.riTrials);
  const som = store.latestSomatic();

  // ---- hero: greeting + ring
  const rg = ring('var(--sound)', 14);
  rg.set(done / tasks.length);
  const hero = h('div', { class: 'row', style: 'align-items:center;gap:18px;margin:6px 0 18px' },
    h('div', { class: 'grow' },
      h('p', { class: 'eyebrow' }, `Woche ${Math.min(week, 8)} von 8 · Tag ${programDay()}`),
      h('h1', { class: 'title-xl', style: 'margin:0' }, `${greet}${d.settings.name ? `, ${d.settings.name}` : ''}`),
      h('p', { class: 'body', style: 'margin:6px 0 0' }, weekFocus(week))),
    h('div', { class: 'ring-wrap', style: 'width:92px;margin:0' }, rg.el,
      h('div', { class: 'ring-center' }, h('div', { class: 'num', style: 'font-size:24px;font-weight:700' }, `${done}/${tasks.length}`))));

  // ---- tasks
  const taskCard = card(null, ...tasks.map((t) => {
    const el = h('div', { class: `task ${t.done ? 'done' : ''}` },
      h('span', { class: 'check' }, t.done ? icon('check') : null),
      h('span', { class: `li-ico ${t.kind}` }, icon(t.icon)),
      h('div', { class: 'grow' }, h('div', { class: 't-title' }, t.title), h('div', { class: 't-sub' }, t.sub)),
      icon('chevR', 'chev'));
    el.addEventListener('click', () => navigate(t.path));
    return el;
  }));

  // ---- quick check-in
  const t = dayKey();
  const todays = d.checkins.filter((c) => dayKey(new Date(c.ts)) === t);
  const quick = card('glow-tin tap',
    h('div', { class: 'row between' },
      h('div', null, h('p', { class: 'title-m' }, 'Wie laut ist er gerade?'), h('p', { class: 'small', style: 'margin:0' }, todays.length ? `Heute ${todays.length}× erfasst · zuletzt ${todays[todays.length - 1].loudness}/10` : 'Tippen für einen 10-Sekunden-Check-in')),
      h('span', { class: 'li-ico tin' }, icon('pulse'))));
  quick.addEventListener('click', () => navigate('/checkin'));

  // ---- profile
  const profile = m
    ? card('tap',
        h('div', { class: 'row between' }, h('p', { class: 'title-m' }, 'Dein Tinnitus-Profil'), icon('chevR', 'chev')),
        h('div', { class: 'grid-2 mt8' },
          metric('Frequenz', formatHz(m.freq).split(' ')[0], formatHz(m.freq).split(' ')[1]),
          metric('Maskierung (MML)', m.mmlDb === null ? '–' : String(m.mmlDb), 'dB'),
          metric('Bester RI-Klang', best ? describeStimulus(best.stimulus) : 'offen'),
          metric('Somatisch', som ? (som.somatic ? 'ja' : 'nein') : 'offen')))
    : null;
  profile?.addEventListener('click', () => navigate('/lab'));

  // ---- trend
  const series = dailyLoudness(14);
  const trend = series.filter((v) => v !== null).length >= 2
    ? card(null,
        h('div', { class: 'row between' }, h('p', { class: 'title-m' }, 'Lautheit, 14 Tage'), trendChip(series)),
        sparkline(series.filter((v): v is number => v !== null), { min: 0, max: 10, color: 'var(--tin)' }),
        h('p', { class: 'small', style: 'margin:4px 0 0' }, 'Tagesmittel aus Check-ins und Tagesrückblick'))
    : null;

  // ---- next lab step teaser
  const nl = nextLabStep();
  const labTeaser = nl
    ? card('glow-lab tap',
        h('p', { class: 'eyebrow c-lab', style: 'margin:0 0 4px' }, 'Labor'),
        h('p', { class: 'title-m' }, nl.title),
        h('p', { class: 'body', style: 'margin:4px 0 12px' }, nl.sub),
        btn('Starten', () => navigate(nl.path), { variant: 'lab', size: 'sm', iconRight: 'chevR' }))
    : null;
  labTeaser?.addEventListener('click', (e) => { if ((e.target as HTMLElement).closest('button')) return; navigate(nl!.path); });

  root.appendChild(page(
    hero,
    quick,
    sectionH('Heute'),
    taskCard,
    labTeaser,
    profile ? sectionH('Profil') : null,
    profile,
    trend ? sectionH('Verlauf') : null,
    trend,
    h('p', { class: 'small center mt24' }, 'Kein Medizinprodukt. Ersetzt keine HNO-Abklärung. ', h('a', { href: '#/learn', style: 'text-decoration:underline' }, 'Was die Forschung sagt')),
  ));
}

function weekFocus(w: number): string {
  if (w <= 1) return 'Messwoche: Wir lernen deinen Tinnitus genau kennen.';
  if (w <= 5) return 'Trainingsphase: Täglich dein wirksamster Klang plus Kopf-Training.';
  if (w === 6) return 'Auswertung: Was wirkt bei dir, was fliegt raus?';
  if (w <= 8) return 'Feinschliff: Neu messen und das Protokoll anpassen.';
  return 'Erhaltungsphase: Weiter mit dem, was nachweislich wirkt.';
}

export function dailyLoudness(days: number): (number | null)[] {
  const d = store.get();
  const out: (number | null)[] = [];
  for (let i = days - 1; i >= 0; i--) {
    const day = dayKey(new Date(Date.now() - i * 86400e3));
    const vals = d.checkins.filter((c) => dayKey(new Date(c.ts)) === day).map((c) => c.loudness);
    const j = d.journal.find((x) => x.date === day);
    if (j) vals.push(j.loudness);
    out.push(vals.length ? mean(vals) : null);
  }
  return out;
}

function trendChip(series: (number | null)[]): HTMLElement {
  const v = series.filter((x): x is number => x !== null);
  if (v.length < 4) return chip('zu wenig Daten');
  const half = Math.floor(v.length / 2);
  const delta = mean(v.slice(half)) - mean(v.slice(0, half));
  if (delta <= -0.4) return chip(`▼ ${delta.toFixed(1)}`, 'good');
  if (delta >= 0.4) return chip(`▲ +${delta.toFixed(1)}`, 'warn');
  return chip('stabil');
}

void fmtDate;
