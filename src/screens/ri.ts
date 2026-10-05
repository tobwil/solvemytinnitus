import { h, btn, page, header, card, range, swap, callout, scale10, toggle, chip, fmtDuration, shuffle, sectionH, fmtDate } from '../ui/dom';
import { icon } from '../ui/icons';
import { lineChart, ring } from '../ui/chart';
import { spectrumViz } from '../ui/viz';
import { store, uid } from '../data/store';
import { engine, formatHz } from '../audio/engine';
import { playTone, playAmTone, playNarrowbandNoise, playNoise, playNotchedNoise, Voice } from '../audio/synth';
import { ResidualInhibitionTrial, StimulusKind, Ear } from '../data/model';
import { navigate } from '../router';
import { RI_TARGET } from '../data/program';

export const STIMULI: { kind: StimulusKind; label: string; desc: string }[] = [
  { kind: 'nbn-third', label: 'Schmalband ⅓ Okt.', desc: 'Rauschen eng um deine Tinnitus-Frequenz. Bei Roberts 2008 am wirksamsten, wenn es im Hörverlust-Bereich liegt.' },
  { kind: 'nbn-octave', label: 'Schmalband 1 Okt.', desc: 'Breiteres Band um die Frequenz, meist angenehmer.' },
  { kind: 'am-tone', label: 'AM-Ton 10 Hz', desc: 'Ton auf deiner Frequenz, 10× pro Sekunde in der Lautstärke moduliert. Unterdrückt bei manchen stärker als ein reiner Ton.' },
  { kind: 'tone', label: 'Reiner Ton', desc: 'Sinuston genau auf deiner Frequenz.' },
  { kind: 'bbn', label: 'Breitband', desc: 'Weißes Rauschen über alle Frequenzen, der klassische Masker.' },
  { kind: 'notched-bbn', label: 'Breitband mit Lücke', desc: 'Kontrollbedingung: Rauschen mit Lücke um deine Frequenz. Wirkt es genauso, ist der Effekt nicht frequenzspezifisch.' },
];

export function describeStimulus(k: StimulusKind): string {
  return STIMULI.find((s) => s.kind === k)?.label ?? k;
}

export interface RiSummary { stimulus: StimulusKind; n: number; depth: number; duration: number; score: number }

export function summarizeRi(trials: ResidualInhibitionTrial[]): RiSummary[] {
  const map = new Map<StimulusKind, ResidualInhibitionTrial[]>();
  for (const t of trials) map.set(t.stimulus, [...(map.get(t.stimulus) ?? []), t]);
  return [...map].map(([stimulus, ts]) => {
    const depth = ts.reduce((a, t) => a + t.depth, 0) / ts.length;
    const duration = ts.reduce((a, t) => a + t.durationOfEffectS, 0) / ts.length;
    return { stimulus, n: ts.length, depth, duration, score: depth * (1 + duration / 60) };
  }).sort((a, b) => b.score - a.score);
}

export function bestRiStimulus(trials: ResidualInhibitionTrial[]): RiSummary | null {
  const s = summarizeRi(trials);
  return s.length && s[0].depth > 0 ? s[0] : null;
}

export function startStimulus(kind: StimulusKind, freq: number, ear: Ear, levelDb: number, notchWidth: number): Voice {
  switch (kind) {
    case 'tone': return playTone(freq, ear, levelDb);
    case 'am-tone': return playAmTone(freq, ear, levelDb);
    case 'nbn-third': return playNarrowbandNoise(freq, 1 / 3, ear, levelDb);
    case 'nbn-octave': return playNarrowbandNoise(freq, 1, ear, levelDb);
    case 'bbn': return playNoise('white', ear, levelDb);
    case 'notched-bbn': return playNotchedNoise('white', freq, notchWidth, ear, levelDb);
  }
}

function leastTested(trials: ResidualInhibitionTrial[]): StimulusKind {
  const counts = new Map(STIMULI.map((s) => [s.kind, 0]));
  for (const t of trials) counts.set(t.stimulus, (counts.get(t.stimulus) ?? 0) + 1);
  const min = Math.min(...counts.values());
  return shuffle([...counts].filter(([, c]) => c === min).map(([k]) => k))[0];
}

export function renderRiLab(root: HTMLElement): () => void {
  const match = store.latestMatch();
  const wrap = h('div');
  root.appendChild(page(header('Labor · Schritt 6', 'Residual Inhibition'), wrap));
  if (!match) {
    swap(wrap, callout('Für das RI-Labor brauchen wir zuerst deine Tinnitus-Frequenz und Maskierungsschwelle.', 'warn'), btn('Zur Feinabstimmung', () => navigate('/match'), { variant: 'lab', block: true }));
    return () => {};
  }
  let blind = store.get().settings.blindRi;
  let kind: StimulusKind = leastTested(store.get().riTrials);
  let durationS = 60;
  let levelDb = Math.min(-8, (match.mmlDb ?? match.loudnessDb) + 10);
  let voice: Voice | null = null;
  let timer: number | null = null;
  const stopAll = () => { voice?.stop(80); voice = null; if (timer !== null) clearInterval(timer); timer = null; };

  function setup() {
    stopAll();
    kind = blind ? leastTested(store.get().riTrials) : kind;
    const stimSel = h('div', { class: blind ? 'hide' : '' },
      h('div', { class: 'choices' }, ...STIMULI.map((s) => {
        const b = h('button', { type: 'button', class: `choice ${s.kind === kind ? 'on' : ''}` }, h('span', { class: 'radio' }), h('span', { class: 'grow' }, h('div', { class: 'ttl' }, s.label), h('div', { class: 'sub' }, s.desc)));
        b.addEventListener('click', () => { kind = s.kind; stimSel.querySelectorAll('.choice').forEach((x) => x.classList.remove('on')); b.classList.add('on'); });
        return b;
      })));
    const lvl = range({ label: 'Stimulus-Pegel', min: -60, max: -8, value: levelDb, format: (v) => `${v} dB`, onInput: (v) => (levelDb = v) });
    swap(wrap,
      h('p', { class: 'lead' }, 'Nach manchen Klängen ist der Tinnitus für Sekunden bis Minuten leiser. Welcher Klang das bei dir auslöst, ist individuell. Hier testen wir es systematisch.'),
      card(null,
        toggle('Verblindet testen (empfohlen)', blind, (v) => { blind = v; store.update((d) => (d.settings.blindRi = v)); stimSel.classList.toggle('hide', v); }),
        h('p', { class: 'small', style: 'margin:0' }, 'Die App wählt den Klang zufällig und zeigt ihn erst nach der Bewertung. So beeinflusst deine Erwartung das Ergebnis nicht.')),
      stimSel,
      card(null,
        h('p', { class: 'title-m' }, 'Dauer'),
        h('div', { class: 'seg' }, ...[30, 60, 90].map((s) => { const b = h('button', { type: 'button', class: s === durationS ? 'on' : '' }, `${s} s`); b.addEventListener('click', () => { durationS = s; b.parentElement!.querySelectorAll('button').forEach((x) => x.classList.remove('on')); b.classList.add('on'); }); return b; })),
        lvl.el,
        h('p', { class: 'small', style: 'margin:0' }, `Vorschlag: MML + 10 dB. Deine MML: ${match!.mmlDb ?? '–'} dB. Nie unangenehm laut.`)),
      btn('Durchgang starten', () => baseline(), { variant: 'lab', size: 'lg', block: true }),
      results());
  }

  function baseline() {
    swap(wrap,
      h('p', { class: 'eyebrow' }, '1 / 3 · Ausgangswert'),
      h('p', { class: 'title-l' }, 'Wie laut ist dein Tinnitus gerade?'),
      card(null, scale10(null, (v) => setTimeout(() => stimulate(v), 200), ['nicht hörbar', 'extrem laut'])));
  }

  async function stimulate(base: number) {
    await engine.ensure();
    const rg = ring('var(--lab)', 8);
    const time = h('div', { class: 'time' }, fmtDuration(durationS));
    const viz = blind ? null : spectrumViz({ tinnitusHz: match!.freq, color: getComputedStyle(document.documentElement).getPropertyValue('--lab').trim() });
    swap(wrap,
      h('p', { class: 'eyebrow' }, '2 / 3 · Stimulation'),
      h('div', { class: 'player' },
        h('div', { class: 'ring-wrap' }, rg.el, h('div', { class: 'ring-center' }, time, h('div', { class: 'phase' }, blind ? 'Klang verblindet' : describeStimulus(kind)))),
        viz?.el ?? null,
        h('p', { class: 'body' }, 'Einfach zuhören. Wenn der Klang endet, bewertest du sofort, wie laut dein Tinnitus ist.'),
        btn('Abbrechen', () => setup(), { variant: 'text' })));
    voice = startStimulus(kind, match!.freq, match!.ear, levelDb, store.get().settings.notchWidthOctaves);
    let left = durationS;
    timer = window.setInterval(() => {
      left--;
      time.textContent = fmtDuration(left);
      rg.set(1 - left / durationS);
      if (left <= 0) { stopAll(); rate(base); }
    }, 1000);
  }

  function rate(base: number) {
    const WINDOW = 90;
    let cur = base;
    const curve: number[] = [];
    let el = 0;
    const time = h('span', { class: 'num', style: 'font-size:15px;font-weight:700' }, fmtDuration(WINDOW));
    const chartHost = h('div');
    const draw = () => swap(chartHost, lineChart({ series: [{ name: 'jetzt', color: 'var(--lab)', area: true, dots: false, points: curve.map((y, i) => ({ x: (i + 1) * 2, y })) }, { name: 'Ausgangswert', color: 'var(--tin)', dashed: true, dots: false, points: [{ x: 0, y: base }, { x: WINDOW, y: base }] }], yMin: 0, yMax: 10, xMin: 0, xMax: WINDOW, height: 150, legend: false, yTicks: [0, 5, 10], xTicks: [0, 30, 60, 90], xFormat: (x) => `${x}s` }));
    const r = range({ label: 'Lautheit jetzt', min: 0, max: 10, step: 0.5, value: base, big: true, color: 'var(--lab)', format: (v) => v.toFixed(1), onInput: (v) => (cur = v), scale: ['weg', 'extrem'] });
    swap(wrap,
      h('div', { class: 'row between' }, h('p', { class: 'eyebrow', style: 'margin:0' }, '3 / 3 · Bewerten'), time),
      h('p', { class: 'title-l' }, 'Wie laut ist er jetzt?'),
      h('p', { class: 'body' }, 'Halte den Regler die ganze Zeit aktuell. Wird er leiser, nach links; kommt er zurück, nach rechts.'),
      card(null, r.el, chartHost),
      btn('Tinnitus ist wieder voll da, beenden', () => { stopAll(); finish(base, curve); }, { variant: 'ghost', block: true }));
    draw();
    timer = window.setInterval(() => {
      el += 2;
      curve.push(cur);
      time.textContent = fmtDuration(Math.max(0, WINDOW - el));
      draw();
      if (el >= WINDOW) { stopAll(); finish(base, curve); }
    }, 2000);
  }

  function finish(base: number, curve: number[]) {
    if (!curve.length) curve = [base];
    const depth = Math.max(0, base - Math.min(...curve));
    let dur = depth > 0 ? curve.length * 2 : 0;
    if (depth > 0) for (let i = 0; i < curve.length; i++) if (curve[i] >= base * 0.9 && i > 0) { dur = i * 2; break; }
    const t: ResidualInhibitionTrial = { id: uid(), date: new Date().toISOString(), stimulus: kind, blind, centerFreq: match!.freq, levelDb, durationS, curve, baseline: base, depth, durationOfEffectS: dur };
    store.update((d) => d.riTrials.push(t));
    const n = store.get().riTrials.length;
    swap(wrap,
      card(depth >= 1 ? 'glow-lab' : '',
        h('p', { class: 'eyebrow' }, blind ? 'Aufgedeckt' : 'Ergebnis'),
        h('p', { class: 'title-l' }, describeStimulus(kind)),
        h('div', { class: 'grid-2 mt8' },
          h('div', { class: 'metric' }, h('div', { class: 'k' }, 'Unterdrückung'), h('div', { class: 'v' }, `−${depth.toFixed(1)}`, h('small', null, 'Punkte'))),
          h('div', { class: 'metric' }, h('div', { class: 'k' }, 'Dauer'), h('div', { class: 'v' }, String(dur), h('small', null, 's')))),
        h('p', { class: 'body' }, depth >= 3 ? 'Starke Residual Inhibition.' : depth >= 1 ? 'Leichte Residual Inhibition.' : 'Keine messbare Unterdrückung mit diesem Klang.')),
      n < RI_TARGET ? callout(`${n} von ${RI_TARGET} Durchgängen. Mach 3 bis 5 Minuten Pause, bis der Tinnitus wieder auf Ausgangsniveau ist, bevor du weitermachst.`) : callout('Labor komplett. Dein bester Klang wird jetzt automatisch in der Reset-Sitzung verwendet.', 'good'),
      btn('Nächster Durchgang', () => setup(), { variant: 'lab', size: 'lg', block: true }),
      h('div', { class: 'center mt8' }, btn('Zur Klangtherapie', () => navigate('/therapy'), { variant: 'text' })),
      results());
  }

  function results(): HTMLElement | null {
    const trials = store.get().riTrials;
    if (!trials.length) return null;
    const sum = summarizeRi(trials);
    const maxScore = Math.max(...sum.map((s) => s.score), 1);
    const untested = STIMULI.filter((s) => !sum.find((x) => x.stimulus === s.kind));
    return h('div', null,
      sectionH('Deine Rangliste', chip(`${trials.length} Durchgänge`, 'lab')),
      card(null,
        h('table', { class: 'tbl' },
          h('thead', null, h('tr', null, h('th', null, 'Klang'), h('th', null, 'n'), h('th', null, 'Tiefe'), h('th', null, 'Dauer'), h('th', null, ''))),
          h('tbody', null, ...sum.map((s, i) => h('tr', null,
            h('td', null, i === 0 && s.depth > 0 ? h('b', { class: 'c-tin' }, '★ ', describeStimulus(s.stimulus)) : describeStimulus(s.stimulus)),
            h('td', null, String(s.n)), h('td', null, s.depth.toFixed(1)), h('td', null, `${Math.round(s.duration)}s`),
            h('td', { style: 'width:22%' }, h('div', { class: 'bar' }, h('i', { style: `width:${(s.score / maxScore) * 100}%` }))))))),
        untested.length ? h('p', { class: 'small mt8' }, `Noch offen: ${untested.map((u) => u.label).join(', ')}`) : null,
        h('details', { class: 'acc mt8' }, h('summary', null, 'Alle Durchgänge', icon('chevR', 'chev')),
          h('ul', { class: 'list acc-body' }, ...trials.slice().reverse().map((t) => h('li', null,
            h('div', { class: 'li-main' }, h('div', { class: 'li-title' }, describeStimulus(t.stimulus)), h('div', { class: 'li-sub' }, `${fmtDate(t.date)} · ${t.levelDb} dB · ${t.durationS}s${t.blind ? ' · verblindet' : ''}`)),
            chip(`−${t.depth.toFixed(1)} · ${t.durationOfEffectS}s`, t.depth >= 1 ? 'good' : '')))))),
      callout(h('span', null, h('b', null, 'Einordnung: '), 'RI ist gut belegt als kurzfristiger Effekt. Dass wiederholte RI den Tinnitus dauerhaft senkt, ist bisher in keiner kontrollierten Studie gezeigt. Wir nutzen sie hier als persönliches Messinstrument und als Erholungspause.')),
      h('p', { class: 'small' }, `Frequenz ${formatHz(match!.freq)}`));
  }

  setup();
  return stopAll;
}
