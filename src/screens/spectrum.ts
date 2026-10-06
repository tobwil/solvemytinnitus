import { h, btn, page, header, card, seg, range, scale10, swap, callout, shuffle, mean, progress, toast } from '../ui/dom';
import { icon } from '../ui/icons';
import { spectrumBars } from '../ui/chart';
import { store, uid } from '../data/store';
import { engine, formatHz } from '../audio/engine';
import { playTone, playNarrowbandNoise, Voice } from '../audio/synth';
import { navigate } from '../router';
import { Ear } from '../data/model';

export const SPECTRUM_FREQS = [1000, 2000, 3000, 4000, 5000, 6000, 8000, 10000, 12000, 14000, 16000];
const REPS = 2;

/**
 * Tinnitus likeness spectrum (Noreña et al. 2002): each test frequency is rated for similarity to the
 * tinnitus, in random order with repetitions. Far more reliable for high-pitched tinnitus than a single
 * pitch match, and it shows whether the tinnitus is tonal (sharp peak) or broad.
 */
export function renderSpectrum(root: HTMLElement): () => void {
  let ear: Ear = store.get().settings.preferredEar;
  let timbre: 'tone' | 'hiss' = store.latestMatch()?.timbre ?? 'tone';
  let level = store.latestMatch()?.loudnessDb ?? -32;
  let voice: Voice | null = null;
  const stop = () => { voice?.stop(80); voice = null; };
  const wrap = h('div');
  root.appendChild(page(header('Labor · Schritt 2', 'Tinnitus-Spektrum'), wrap));

  const play = async (f: number, boost = 0) => {
    await engine.ensure();
    stop();
    voice = timbre === 'tone' ? playTone(f, ear, level + boost) : playNarrowbandNoise(f, 1 / 3, ear, level + boost);
    const v = voice;
    setTimeout(() => { if (voice === v) stop(); }, 2000);
  };

  function intro() {
    const lvl = range({ label: 'Pegel der Testtöne', min: -60, max: -10, value: level, format: (v) => `${v} dB`, onInput: (v) => (level = v) });
    swap(wrap,
      h('p', { class: 'lead' }, `Du hörst ${SPECTRUM_FREQS.length} Töne je ${REPS}× in zufälliger Reihenfolge und bewertest, wie ähnlich jeder deinem Tinnitus ist. Das dauert etwa 4 Minuten und ist bei hohem Tinnitus deutlich verlässlicher als nur einen Regler zu schieben.`),
      card(null,
        h('p', { class: 'title-m' }, 'Ohr'),
        seg<Ear>([{ value: 'both', label: 'Beide' }, { value: 'left', label: 'Links' }, { value: 'right', label: 'Rechts' }], ear, (v) => (ear = v)).el,
        h('p', { class: 'title-m mt16' }, 'Klingt dein Tinnitus eher wie …'),
        seg<'tone' | 'hiss'>([{ value: 'tone', label: 'Pfeifton' }, { value: 'hiss', label: 'Zischen' }], timbre, (v) => (timbre = v)).el,
        lvl.el,
        btn('Probeton 4 kHz', () => play(4000), { variant: 'ghost', size: 'sm', icon: 'play' }),
        h('p', { class: 'small mt8' }, 'Stelle den Pegel so ein, dass der Probeton etwa so laut ist wie dein Tinnitus.')),
      btn('Test starten', () => run(), { variant: 'lab', size: 'lg', block: true }));
  }

  function run() {
    const order = shuffle(SPECTRUM_FREQS.flatMap((f) => Array(REPS).fill(f) as number[]));
    const ratings = new Map<number, number[]>();
    let i = 0;
    const show = () => {
      if (i >= order.length) return finish(ratings);
      const f = order[i];
      const orb = h('div', { class: 'like-orb playing' }, h('div', { class: 'core' }, icon('wave')));
      setTimeout(() => orb.classList.remove('playing'), 2000);
      const replay = () => { orb.classList.add('playing'); setTimeout(() => orb.classList.remove('playing'), 2000); play(f); };
      const record = (v: number) => {
        ratings.set(f, [...(ratings.get(f) ?? []), v]);
        i++;
        setTimeout(show, 280);
      };
      swap(wrap,
        progress(order.length, i),
        card('like-stage', orb,
          h('p', { class: 'title-m' }, `Ton ${i + 1} von ${order.length}`),
          h('p', { class: 'small' }, 'Wie ähnlich ist dieser Ton deinem Tinnitus, in Tonhöhe und Klang?'),
          h('div', { class: 'row', style: 'justify-content:center;gap:8px;margin:6px 0 16px' },
            btn('Nochmal', replay, { variant: 'ghost', size: 'sm', icon: 'play' }),
            btn('Lauter', () => { orb.classList.add('playing'); setTimeout(() => orb.classList.remove('playing'), 2000); play(f, 10); }, { variant: 'ghost', size: 'sm', icon: 'volume' })),
          scale10(null, record, ['gar nicht', 'genau so'])),
        h('div', { class: 'center' }, btn('Nicht hörbar', () => record(0), { variant: 'text' })));
      play(f);
    };
    show();
  }

  function finish(ratings: Map<number, number[]>) {
    stop();
    const points = SPECTRUM_FREQS.map((f) => ({ freq: f, value: mean(ratings.get(f) ?? [0]) }));
    const top = points.reduce((a, b) => (b.value > a.value ? b : a));
    // consistency: mean abs difference between repetitions
    const diffs = SPECTRUM_FREQS.map((f) => { const r = ratings.get(f) ?? []; return r.length > 1 ? Math.abs(r[0] - r[1]) : 0; });
    const consistency = mean(diffs);
    const sorted = points.slice().sort((a, b) => b.value - a.value);
    const sharp = sorted[0].value - mean(sorted.slice(3).map((p) => p.value));
    store.update((d) => d.spectra.push({ id: uid(), date: new Date().toISOString(), ear, timbre, points, peak: top.freq }));
    swap(wrap,
      card('glow-lab',
        h('p', { class: 'eyebrow c-lab' }, 'Ergebnis'),
        h('div', { class: 'display-num' }, formatHz(top.freq).split(' ')[0], h('span', { class: 'unit' }, formatHz(top.freq).split(' ')[1])),
        h('p', { class: 'body' }, 'Höchste Ähnlichkeit'),
        spectrumBars(points, { max: 10, peak: top.freq }),
        h('div', { class: 'row wrap mt8' },
          h('span', { class: `chip ${consistency <= 1.5 ? 'good' : 'warn'}` }, `Wiederholgenauigkeit ±${consistency.toFixed(1)}`),
          h('span', { class: 'chip lab' }, sharp > 4 ? 'tonal, schmalbandig' : sharp > 2 ? 'mittelbreit' : 'breitbandig'))),
      consistency > 2 ? callout('Deine Bewertungen der gleichen Töne weichen stark voneinander ab. Das ist bei hohem Tinnitus häufig. Wiederhole den Test an einem anderen Tag, das Profil wird mit jeder Messung schärfer.', 'warn') : null,
      top.freq >= 14000 ? callout('Dein Tinnitus liegt sehr hoch. Prüfe im Hörprofil, ob du den Bereich überhaupt noch hörst; Notched-Therapien brauchen hörbares Material um die Frequenz.') : null,
      btn('Weiter: Feinabstimmung', () => navigate(`/match?start=${top.freq}`), { variant: 'lab', size: 'lg', block: true, iconRight: 'chevR' }),
      h('div', { class: 'center mt8' }, btn('Nochmal messen', () => { toast('Neue Messung'); intro(); }, { variant: 'text' })));
  }

  intro();
  return stop;
}
