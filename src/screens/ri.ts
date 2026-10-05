import { h, card, note, button, segmented, slider, clear, fmtDuration } from '../ui/dom';
import { store, uid } from '../data/store';
import { engine, formatHz } from '../audio/engine';
import { playTone, playNarrowbandNoise, playNoise, playNotchedNoise, Voice } from '../audio/synth';
import { ResidualInhibitionTrial, StimulusKind } from '../data/model';
import { lineChart } from '../ui/chart';
import { navigate } from '../main';

export const STIMULI: { kind: StimulusKind; label: string; desc: string }[] = [
  { kind: 'nbn-third', label: 'Schmalband ⅓ Oktave', desc: 'Rauschen eng um deine Tinnitus-Frequenz. In Studien am häufigsten wirksam.' },
  { kind: 'nbn-octave', label: 'Schmalband 1 Oktave', desc: 'Breiteres Band um die Frequenz, meist angenehmer.' },
  { kind: 'tone', label: 'Reiner Ton', desc: 'Sinuston genau auf deiner Frequenz. Kann bei Ton-Tinnitus am stärksten wirken.' },
  { kind: 'bbn', label: 'Breitbandrauschen', desc: 'Weißes Rauschen ohne Formung, klassischer Masker.' },
  { kind: 'notched-bbn', label: 'Notched Rauschen', desc: 'Breitband mit Lücke um die Tinnitus-Frequenz. Kontrollbedingung: wirkt es trotzdem, ist die Frequenz-Spezifität gering.' },
];

export function describeStimulus(k: StimulusKind): string {
  return STIMULI.find((s) => s.kind === k)?.label ?? k;
}

export interface RiSummary {
  stimulus: StimulusKind;
  n: number;
  depth: number;
  duration: number;
  score: number;
}

export function summarizeRi(trials: ResidualInhibitionTrial[]): RiSummary[] {
  const map = new Map<StimulusKind, ResidualInhibitionTrial[]>();
  for (const t of trials) map.set(t.stimulus, [...(map.get(t.stimulus) ?? []), t]);
  const out: RiSummary[] = [];
  for (const [stimulus, ts] of map) {
    const depth = ts.reduce((a, t) => a + t.depth, 0) / ts.length;
    const duration = ts.reduce((a, t) => a + t.durationOfEffectS, 0) / ts.length;
    out.push({ stimulus, n: ts.length, depth, duration, score: depth * (1 + duration / 60) });
  }
  return out.sort((a, b) => b.score - a.score);
}

export function bestRiStimulus(trials: ResidualInhibitionTrial[]): RiSummary | null {
  const s = summarizeRi(trials);
  return s.length && s[0].depth > 0 ? s[0] : null;
}

export function startStimulus(kind: StimulusKind, freq: number, ear: 'left' | 'right' | 'both', levelDb: number, notchWidth: number): Voice {
  switch (kind) {
    case 'tone': return playTone(freq, ear, levelDb);
    case 'nbn-third': return playNarrowbandNoise(freq, 1 / 3, ear, levelDb);
    case 'nbn-octave': return playNarrowbandNoise(freq, 1, ear, levelDb);
    case 'bbn': return playNoise('white', ear, levelDb);
    case 'notched-bbn': return playNotchedNoise('white', freq, notchWidth, ear, levelDb);
  }
}

type Phase = 'idle' | 'baseline' | 'stim' | 'rate' | 'result';

export function renderRiLab(root: HTMLElement): () => void {
  const match = store.latestMatch();
  root.appendChild(h('h1', null, 'Residual-Inhibition-Labor'));
  if (!match) {
    root.appendChild(card(null, note('Zuerst brauchen wir deine Tinnitus-Frequenz.', 'warn'), h('p', null, button('Zum Matching →', () => navigate('/match'), 'btn'))));
    return () => {};
  }

  const d = store.get();
  let kind: StimulusKind = nextSuggested(d.riTrials);
  let durationS = 30;
  let levelDb = Math.min(-6, (match.mmlDb ?? match.loudnessDb) + 10);
  let phase: Phase = 'idle';
  let baseline = 5;
  let curve: number[] = [];
  let voice: Voice | null = null;
  let timer: number | null = null;
  let current = 5;
  let lastTrial: ResidualInhibitionTrial | null = null;

  const panel = h('div');
  root.appendChild(panel);
  const resultsHost = h('div');
  root.appendChild(resultsHost);

  function nextSuggested(trials: ResidualInhibitionTrial[]): StimulusKind {
    const counts = new Map<StimulusKind, number>();
    for (const s of STIMULI) counts.set(s.kind, 0);
    for (const t of trials) counts.set(t.stimulus, (counts.get(t.stimulus) ?? 0) + 1);
    let best: StimulusKind = 'nbn-third';
    let min = Infinity;
    for (const s of STIMULI) {
      const c = counts.get(s.kind)!;
      if (c < min) { min = c; best = s.kind; }
    }
    return best;
  }

  function stop() {
    voice?.stop(50);
    voice = null;
    if (timer !== null) window.clearInterval(timer);
    timer = null;
  }

  function render() {
    clear(panel);
    if (phase === 'idle') renderIdle();
    else if (phase === 'baseline') renderBaseline();
    else if (phase === 'stim') renderStim();
    else if (phase === 'rate') renderRate();
    else renderResult();
    renderResults();
  }

  function renderIdle() {
    const stimSeg = segmented(STIMULI.map((s) => ({ value: s.kind, label: s.label })), kind, (v) => { kind = v; descEl.textContent = STIMULI.find((s) => s.kind === v)!.desc; });
    const descEl = h('p', { class: 'muted' }, STIMULI.find((s) => s.kind === kind)!.desc);
    const lvl = slider({ min: -60, max: -6, step: 1, value: levelDb, label: 'Stimulus-Pegel', format: (v) => `${v} dB`, onInput: (v) => (levelDb = v) });
    const dur = segmented([{ value: '30', label: '30 s' }, { value: '60', label: '60 s' }, { value: '90', label: '90 s' }], String(durationS), (v) => (durationS = Number(v)));
    const preview = button('▶ 3 s Vorhören', async () => { await engine.ensure(); voice?.stop(); voice = startStimulus(kind, match!.freq, match!.ear, levelDb, store.get().settings.notchWidthOctaves); setTimeout(() => { voice?.stop(); voice = null; }, 3000); }, 'btn secondary small');
    panel.append(
      card('Was ist Residual Inhibition?',
        h('p', null, 'Bei vielen Betroffenen wird der Tinnitus nach einem passenden Klang für Sekunden bis Minuten leiser oder verschwindet kurz. Dieser Effekt heißt Residual Inhibition (RI). Welcher Klang ihn auslöst, ist individuell. Dieses Labor misst ihn systematisch, damit die Therapie auf deinen wirksamsten Klang gebaut wird.'),
        note('Protokoll: Jede Variante mindestens zweimal, an verschiedenen Tagen, mit 5 Minuten Pause dazwischen. Der Pegel sollte deutlich über der Maskierungsschwelle liegen, aber nie unangenehm laut sein.'),
      ),
      card('Durchgang vorbereiten',
        h('p', null, h('span', { class: 'pill accent' }, `Frequenz ${formatHz(match!.freq)} · ${match!.ear === 'both' ? 'beide Ohren' : match!.ear === 'left' ? 'links' : 'rechts'}`)),
        h('h3', null, 'Stimulus'), stimSeg.el, descEl,
        h('h3', null, 'Dauer'), dur.el,
        lvl.el, h('p', null, preview),
        h('p', null, button('Durchgang starten →', () => { stop(); phase = 'baseline'; render(); }, 'btn big')),
      ),
    );
  }

  function ratingSlider(onChange: (v: number) => void, value: number) {
    return slider({ min: 0, max: 10, step: 0.5, value, label: 'Tinnitus-Lautheit jetzt (0 = weg, 10 = so laut wie je)', format: (v) => v.toFixed(1), onInput: onChange });
  }

  function renderBaseline() {
    const sl = ratingSlider((v) => (baseline = v), baseline);
    panel.append(card('1 · Ausgangswert',
      h('p', null, 'Wie laut ist dein Tinnitus in diesem Moment, bevor der Klang startet?'),
      h('div', { class: 'ri-slider-wrap' }, sl.el),
      button('Klang starten →', async () => { await engine.ensure(); phase = 'stim'; render(); }, 'btn big'),
    ));
  }

  function renderStim() {
    let remaining = durationS;
    const clock = h('div', { class: 'timer pulse' }, fmtDuration(remaining));
    voice = startStimulus(kind, match!.freq, match!.ear, levelDb, store.get().settings.notchWidthOctaves);
    timer = window.setInterval(() => {
      remaining--;
      clock.textContent = fmtDuration(remaining);
      if (remaining <= 0) {
        stop();
        phase = 'rate';
        render();
      }
    }, 1000);
    panel.append(card('2 · Stimulation läuft', h('p', { class: 'muted' }, `${describeStimulus(kind)} · ${levelDb} dB`), clock,
      h('p', { class: 'muted' }, 'Entspann dich, hör einfach zu. Sobald der Klang stoppt, bewerte sofort und laufend die Lautheit deines Tinnitus.'),
      button('Abbrechen', () => { stop(); phase = 'idle'; render(); }, 'btn secondary small')));
  }

  function renderRate() {
    curve = [];
    current = baseline;
    const WINDOW = 60;
    let elapsed = 0;
    const clock = h('div', { class: 'timer' }, fmtDuration(WINDOW));
    const sl = ratingSlider((v) => (current = v), current);
    const live = h('p', { class: 'muted' }, 'Ausgangswert: ' + baseline.toFixed(1));
    timer = window.setInterval(() => {
      elapsed += 2;
      curve.push(current);
      clock.textContent = fmtDuration(Math.max(0, WINDOW - elapsed));
      live.textContent = `Ausgangswert ${baseline.toFixed(1)} · jetzt ${current.toFixed(1)} · Unterdrückung ${(baseline - current).toFixed(1)}`;
      if (elapsed >= WINDOW) {
        stop();
        finishTrial();
      }
    }, 2000);
    panel.append(card('3 · Jetzt bewerten (60 s)',
      h('p', null, 'Bewege den Regler laufend, sobald sich die Lautheit ändert. Falls der Tinnitus komplett weg ist, ganz nach links.'),
      clock, h('div', { class: 'ri-slider-wrap' }, sl.el), live,
      button('Vorzeitig beenden', () => { stop(); finishTrial(); }, 'btn secondary small')));
  }

  function finishTrial() {
    if (!curve.length) curve = [current];
    const min = Math.min(...curve);
    const depth = Math.max(0, baseline - min);
    let dur = curve.length * 2;
    for (let i = 0; i < curve.length; i++) {
      if (curve[i] >= baseline * 0.9) { dur = i * 2; break; }
    }
    if (depth === 0) dur = 0;
    const trial: ResidualInhibitionTrial = {
      id: uid(), date: new Date().toISOString(), stimulus: kind, centerFreq: match!.freq, levelDb, durationS, curve, baseline, depth, durationOfEffectS: dur,
    };
    store.update((s) => s.riTrials.push(trial));
    lastTrial = trial;
    phase = 'result';
    render();
  }

  function renderResult() {
    const t = lastTrial!;
    const verdict = t.depth >= 3 ? 'Starke Residual Inhibition.' : t.depth >= 1 ? 'Leichte Residual Inhibition.' : 'Keine messbare Unterdrückung mit diesem Klang.';
    panel.append(card('Ergebnis',
      h('div', { class: 'grid2' },
        h('div', { class: 'stat' }, h('div', { class: 'label' }, 'Unterdrückung (Tiefe)'), h('div', { class: 'value' }, `${t.depth.toFixed(1)} / ${t.baseline.toFixed(1)}`)),
        h('div', { class: 'stat' }, h('div', { class: 'label' }, 'Dauer des Effekts'), h('div', { class: 'value' }, `${t.durationOfEffectS} s`)),
      ),
      note(verdict, t.depth >= 1 ? 'ok' : 'info'),
      lineChart({ series: [{ name: 'Lautheit nach Stimulus', color: '#4fd1c5', points: t.curve.map((y, i) => ({ x: (i + 1) * 2, y })) }, { name: 'Ausgangswert', color: '#f6ad55', dashed: true, points: [{ x: 0, y: t.baseline }, { x: t.curve.length * 2, y: t.baseline }] }], yMin: 0, yMax: 10, xLabel: 'Sekunden nach Stimulus-Ende', height: 200 }),
      h('div', { class: 'row', style: 'margin-top:10px' },
        button('Nächste Variante testen', () => { kind = nextSuggested(store.get().riTrials); phase = 'idle'; render(); }, 'btn'),
        button('Zur Therapie', () => navigate('/therapy'), 'btn secondary'),
      ),
    ));
  }

  function renderResults() {
    clear(resultsHost);
    const trials = store.get().riTrials;
    if (!trials.length) return;
    const summary = summarizeRi(trials);
    const tbl = h('table', { class: 'tbl' },
      h('thead', null, h('tr', null, h('th', null, 'Stimulus'), h('th', null, 'n'), h('th', null, 'Ø Tiefe'), h('th', null, 'Ø Dauer'), h('th', null, 'Score'))),
      h('tbody', null, ...summary.map((s, i) => h('tr', null,
        h('td', null, i === 0 && s.depth > 0 ? h('b', null, '★ ' + describeStimulus(s.stimulus)) : describeStimulus(s.stimulus)),
        h('td', null, String(s.n)), h('td', null, s.depth.toFixed(1)), h('td', null, `${Math.round(s.duration)} s`), h('td', null, s.score.toFixed(1))))),
    );
    const untested = STIMULI.filter((s) => !summary.find((x) => x.stimulus === s.kind));
    resultsHost.append(card('Rangliste deiner Stimuli',
      tbl,
      untested.length ? h('p', { class: 'muted' }, `Noch nicht getestet: ${untested.map((u) => u.label).join(', ')}`) : note('Alle Varianten getestet. Der ★-Stimulus wird in den Reset-Sitzungen verwendet. Teste die Top-2 noch je einmal an einem anderen Tag, um Zufallstreffer auszuschließen.', 'ok'),
      h('details', null, h('summary', null, `Alle ${trials.length} Durchgänge`),
        h('ul', { class: 'list' }, ...trials.slice().reverse().map((t) => h('li', null,
          h('span', null, `${new Date(t.date).toLocaleDateString('de-DE')} · ${describeStimulus(t.stimulus)} · ${t.levelDb} dB · ${t.durationS} s`),
          h('span', { class: `pill ${t.depth >= 1 ? 'ok' : ''}` }, `−${t.depth.toFixed(1)} / ${t.durationOfEffectS} s`))))),
    ));
  }

  render();
  return () => stop();
}
