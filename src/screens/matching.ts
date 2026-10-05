import { h, btn, page, header, card, seg, range, swap, callout, progress, geoMedian, chip } from '../ui/dom';
import { freqPad } from '../ui/pad';
import { store, uid } from '../data/store';
import { engine, formatHz, octaveDistance } from '../audio/engine';
import { playTone, playNarrowbandNoise, playNoise, Voice } from '../audio/synth';
import { navigate, Params } from '../router';
import { Ear } from '../data/model';

const F_MIN = 500;
const F_MAX = 18000;
const STEPS = 5; // 3 pitch trials, loudness, MML

export function renderMatching(root: HTMLElement, params: Params): () => void {
  const spec = store.latestSpectrum();
  const prev = store.latestMatch();
  let ear: Ear = spec?.ear ?? store.get().settings.preferredEar;
  let timbre: 'tone' | 'hiss' = spec?.timbre ?? prev?.timbre ?? 'tone';
  const start = Number(params.start) || spec?.peak || prev?.freq || 6000;
  let freq = start;
  const trials: number[] = [];
  let loudnessDb = prev?.loudnessDb ?? -32;
  let voice: (Voice & { setFreq?(f: number): void }) | null = null;
  const stop = () => { voice?.stop(60); voice = null; };
  const startVoice = async (f: number, db = loudnessDb) => {
    await engine.ensure();
    stop();
    voice = timbre === 'tone' ? playTone(f, ear, db) : playNarrowbandNoise(f, 1 / 3, ear, db);
  };
  const wrap = h('div');
  root.appendChild(page(header('Labor · Schritt 3', 'Feinabstimmung'), wrap));

  function setup() {
    swap(wrap,
      h('p', { class: 'lead' }, spec
        ? `Dein Spektrum zeigt den Schwerpunkt bei ${formatHz(spec.peak)}. Jetzt stimmen wir das genau ab: drei unabhängige Durchgänge auf dem Frequenz-Pad, dann Lautheit und Maskierungsschwelle.`
        : 'Drei unabhängige Durchgänge auf dem Frequenz-Pad, dann Lautheit und Maskierungsschwelle. Tipp: Das Tinnitus-Spektrum vorher macht das Ergebnis deutlich verlässlicher.'),
      card(null,
        h('p', { class: 'title-m' }, 'Ohr'),
        seg<Ear>([{ value: 'both', label: 'Beide' }, { value: 'left', label: 'Links' }, { value: 'right', label: 'Rechts' }], ear, (v) => (ear = v)).el,
        h('p', { class: 'title-m mt16' }, 'Vergleichsklang'),
        seg<'tone' | 'hiss'>([{ value: 'tone', label: 'Reiner Ton' }, { value: 'hiss', label: 'Schmalband-Rauschen' }], timbre, (v) => (timbre = v)).el),
      !spec ? h('div', { class: 'center' }, btn('Erst Spektrum messen', () => navigate('/spectrum'), { variant: 'text' })) : null,
      btn('Los', () => pitch(), { variant: 'lab', size: 'lg', block: true }));
  }

  function pitch() {
    const n = trials.length;
    // independent start point for each trial: random offset up to ±0.75 octave
    if (n > 0) freq = Math.min(F_MAX, Math.max(F_MIN, start * Math.pow(2, (Math.random() - 0.5) * 1.5)));
    const pad = freqPad({
      fMin: F_MIN, fMax: F_MAX, value: freq, overlay: spec?.points,
      onStart: (f) => { freq = f; startVoice(f); },
      onMove: (f) => { freq = f; voice?.setFreq?.(f); },
      onEnd: () => stop(),
    });
    const nudge = (semi: number) => {
      freq = Math.min(F_MAX, Math.max(F_MIN, freq * Math.pow(2, semi / 12)));
      pad.set(freq);
      startVoice(freq);
      setTimeout(stop, 1200);
    };
    const nb = (lbl: string, s: number) => { const b = h('button', { type: 'button' }, lbl); b.addEventListener('click', () => nudge(s)); return b; };
    swap(wrap,
      progress(STEPS, n),
      h('p', { class: 'title-m' }, `Durchgang ${n + 1} von 3`),
      h('p', { class: 'body' }, 'Halte den Finger auf dem Feld und zieh ihn nach links oder rechts, bis der Ton wie dein Tinnitus klingt. Lass los und vergleiche. Mit den Tasten feinjustieren.'),
      pad.el,
      h('div', { class: 'nudge' }, nb('−1 HT', -1), nb('−¼', -0.25), nb('+¼', 0.25), nb('+1 HT', 1)),
      h('div', { class: 'btn-col' }, btn('Klingt wie mein Tinnitus', () => { freq = pad.get(); stop(); octave(); }, { variant: 'lab', size: 'lg', block: true })));
  }

  function octave() {
    // octave confusions are the most common pitch-matching error
    const cands = [freq / 2, freq, freq * 2].filter((f) => f >= F_MIN && f <= F_MAX);
    swap(wrap,
      progress(STEPS, trials.length),
      h('p', { class: 'title-m' }, 'Oktaven-Check'),
      h('p', { class: 'body' }, 'Die häufigste Verwechslung beim Matching ist die Oktave. Hör dir die Varianten an und wähle die, die wirklich passt.'),
      h('div', { class: 'choices mt16' }, ...cands.map((f) => {
        const cur = Math.abs(f - freq) < 1;
        const play = btn('', async () => { await startVoice(f); setTimeout(stop, 1500); }, { variant: 'ghost', size: 'sm', icon: 'play' });
        const pick = btn('Passt', () => { stop(); trials.push(f); if (trials.length < 3) pitch(); else loudness(); }, { variant: cur ? 'lab' : 'ghost', size: 'sm' });
        return h('div', { class: 'choice', style: 'cursor:default' },
          h('div', { class: 'grow' }, h('div', { class: 'ttl num', style: 'font-size:20px' }, formatHz(f)), h('div', { class: 'sub' }, cur ? 'deine Einstellung' : f < freq ? 'eine Oktave tiefer' : 'eine Oktave höher')),
          play, pick);
      })));
  }

  function loudness() {
    freq = geoMedian(trials);
    const spread = Math.max(...trials.map((t) => octaveDistance(t, freq)));
    let playing = false;
    const r = range({ label: 'Pegel des Vergleichstons', min: -75, max: -8, value: loudnessDb, format: (v) => `${v} dB`, onInput: (v) => { loudnessDb = v; voice?.setLevel(v); } });
    const play = btn('Abspielen', async () => {
      if (playing) { stop(); playing = false; play.lastChild!.textContent = 'Abspielen'; return; }
      await startVoice(freq, loudnessDb); playing = true; play.lastChild!.textContent = 'Stopp';
    }, { variant: 'ghost', block: true, icon: 'play' });
    swap(wrap,
      progress(STEPS, 3),
      card('glow-lab',
        h('p', { class: 'eyebrow c-lab' }, 'Median aus 3 Durchgängen'),
        h('div', { class: 'display-num' }, formatHz(freq).split(' ')[0], h('span', { class: 'unit' }, formatHz(freq).split(' ')[1])),
        h('div', { class: 'row wrap mt8' }, ...trials.map((t) => chip(formatHz(t))), chip(`Streuung ${(spread * 12).toFixed(1)} HT`, spread > 0.5 ? 'warn' : 'good'))),
      spread > 0.5 ? callout('Die Durchgänge liegen mehr als eine halbe Oktave auseinander. Das ist bei hohem Tinnitus normal. Wiederhole die Messung an einem anderen Tag.', 'warn') : null,
      h('p', { class: 'title-m mt16' }, 'Wie laut ist dein Tinnitus?'),
      h('p', { class: 'body' }, 'Spiel den Ton ab und stell den Pegel so ein, dass er genau so laut wirkt wie dein Tinnitus.'),
      card(null, play, r.el),
      btn('Gleich laut', () => { stop(); mml(spread); }, { variant: 'lab', size: 'lg', block: true }));
  }

  function mml(spread: number) {
    let db = -50;
    let noise: Voice | null = null;
    const r = range({ label: 'Pegel Breitbandrauschen', min: -80, max: -8, value: db, format: (v) => `${v} dB`, onInput: (v) => { db = v; noise?.setLevel(v); } });
    const play = btn('Rauschen starten', async () => {
      await engine.ensure();
      if (noise) { noise.stop(); noise = null; play.lastChild!.textContent = 'Rauschen starten'; return; }
      noise = playNoise('white', ear, db); play.lastChild!.textContent = 'Stopp';
    }, { variant: 'ghost', block: true, icon: 'play' });
    const save = (v: number | null) => {
      noise?.stop();
      store.update((d) => {
        d.matches.push({ id: uid(), date: new Date().toISOString(), ear, freq: Math.round(freq), trials: trials.map(Math.round), spreadOctaves: spread, loudnessDb, timbre, mmlDb: v });
        d.settings.preferredEar = ear;
      });
      done();
    };
    swap(wrap,
      progress(STEPS, 4),
      h('p', { class: 'title-m' }, 'Minimale Maskierungsschwelle'),
      h('p', { class: 'body' }, 'Starte das Rauschen leise und erhöhe es langsam, bis du deinen Tinnitus gerade nicht mehr hörst. Die Schwelle (MML) ist ein objektiverer Verlaufswert als die Lautheit und legt die Pegel für Labor und Therapie fest.'),
      card(null, play, r.el),
      btn('Tinnitus ist gerade verdeckt', () => save(db), { variant: 'lab', size: 'lg', block: true }),
      h('div', { class: 'center' }, btn('Lässt sich nicht verdecken', () => save(null), { variant: 'text' })),
      cleanupHook(() => noise?.stop()));
  }

  function done() {
    const m = store.latestMatch()!;
    swap(wrap,
      progress(STEPS, STEPS),
      card('glow-lab center',
        h('p', { class: 'eyebrow c-lab' }, 'Gespeichert'),
        h('div', { class: 'display-num' }, formatHz(m.freq).split(' ')[0], h('span', { class: 'unit' }, formatHz(m.freq).split(' ')[1])),
        h('div', { class: 'grid-3 mt16' },
          h('div', { class: 'metric' }, h('div', { class: 'k' }, 'Ohr'), h('div', { class: 'v' }, m.ear === 'both' ? 'beide' : m.ear === 'left' ? 'links' : 'rechts')),
          h('div', { class: 'metric' }, h('div', { class: 'k' }, 'Lautheit'), h('div', { class: 'v' }, String(m.loudnessDb), h('small', null, 'dB'))),
          h('div', { class: 'metric' }, h('div', { class: 'k' }, 'MML'), h('div', { class: 'v' }, m.mmlDb === null ? '–' : String(m.mmlDb), h('small', null, 'dB'))))),
      btn('Weiter: Hörprofil', () => navigate('/hearing'), { variant: 'lab', size: 'lg', block: true, iconRight: 'chevR' }),
      h('div', { class: 'center mt8' }, btn('Anderes Ohr messen', () => { trials.length = 0; setup(); }, { variant: 'text' })));
  }

  let extraCleanup: (() => void) | null = null;
  function cleanupHook(fn: () => void): null { extraCleanup = fn; return null; }

  setup();
  return () => { stop(); extraCleanup?.(); };
}
