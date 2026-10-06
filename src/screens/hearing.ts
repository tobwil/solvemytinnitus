import { h, btn, page, header, card, seg, swap, callout, progress, mean } from '../ui/dom';
import { icon } from '../ui/icons';
import { lineChart } from '../ui/chart';
import { store, uid } from '../data/store';
import { engine, formatHz } from '../audio/engine';
import { playToneBursts, Voice } from '../audio/synth';
import { navigate } from '../router';
import { HearingPoint } from '../data/model';

const FREQS = [500, 1000, 2000, 3000, 4000, 6000, 8000, 10000, 12000, 14000, 16000];
const START = -40, MIN = -95, MAX = -6;

/** Simplified Hughson-Westlake (down 10 / up 5); threshold = level heard twice on ascending runs. */
export function renderHearing(root: HTMLElement): () => void {
  let ear: 'left' | 'right' = 'left';
  const res: { left: HearingPoint[]; right: HearingPoint[] } = { left: [], right: [] };
  let voice: Voice | null = null;
  const stop = () => { voice?.stop(10); voice = null; };
  const wrap = h('div');
  root.appendChild(page(header('Labor · Schritt 4', 'Hörprofil'), wrap));

  function intro() {
    swap(wrap,
      h('p', { class: 'lead' }, 'Wir suchen pro Ohr die leiseste hörbare Lautstärke von 0,5 bis 16 kHz. Nach Konzert-Lärm zeigt sich meist ein Abfall im Hochtonbereich, und der Tinnitus sitzt typischerweise genau dort.'),
      card(null,
        h('p', { class: 'title-m' }, 'Mit welchem Ohr beginnen?'),
        seg([{ value: 'left', label: 'Links' }, { value: 'right', label: 'Rechts' }], ear, (v) => (ear = v as 'left' | 'right')).el,
        h('p', { class: 'small mt8' }, 'Dauer: ca. 3 Minuten pro Ohr. Ganz ruhige Umgebung nötig.')),
      callout('Die Werte sind relativ zu deinem Kopfhörer, nicht in dB HL wie beim HNO. Sie zeigen die Form deines Hörprofils und eignen sich für Verlaufsvergleiche mit denselben Kopfhörern.'),
      btn('Test starten', () => run(), { variant: 'lab', size: 'lg', block: true }),
      chartCard());
  }

  function run() {
    let fi = 0, level = START;
    let heard: number[] = [];
    let presentations = 0;
    res[ear] = [];
    const orb = h('div', { class: 'like-orb' }, h('div', { class: 'core' }, icon('ear')));
    const fLbl = h('p', { class: 'title-m' });
    const prog = h('div');
    const yes = btn('Gehört', () => answer(true), { variant: 'lab', size: 'lg', block: true });
    const no = btn('Nichts gehört', () => answer(false), { variant: 'ghost', size: 'lg', block: true });
    swap(wrap, prog, card('like-stage', orb, fLbl, h('p', { class: 'small' }, 'Drei kurze Pieptöne. Antworte, sobald du sie hörst, auch wenn sie sehr leise sind.'),
      btn('Wiederholen', () => play(), { variant: 'text', icon: 'play' })), h('div', { class: 'btn-col' }, yes, no));

    let pending: number | null = null;
    const schedule = (ms: number) => { if (pending !== null) clearTimeout(pending); pending = window.setTimeout(() => { pending = null; play(); }, ms); };
    const play = async () => {
      if (fi >= FREQS.length) return;
      await engine.ensure();
      stop();
      swap(prog, progress(FREQS.length, fi));
      fLbl.textContent = `${ear === 'left' ? 'Links' : 'Rechts'} · ${formatHz(FREQS[fi])}`;
      orb.classList.add('playing');
      setTimeout(() => orb.classList.remove('playing'), 1100);
      voice = playToneBursts(FREQS[fi], ear, level);
    };
    const nextF = (thr: number) => {
      res[ear].push({ freq: FREQS[fi], level: thr });
      fi++;
      heard = [];
      presentations = 0;
      level = START;
      if (fi >= FREQS.length) { if (pending !== null) clearTimeout(pending); return finishEar(); }
      schedule(350);
    };
    const answer = (ok: boolean) => {
      if (fi >= FREQS.length) return;
      presentations++;
      // safety net for inconsistent answers: take the lowest level heard so far
      if (presentations >= 14) return nextF(heard.length ? Math.min(...heard) : MAX);
      if (ok) {
        heard.push(level);
        if (heard.filter((l) => l === level).length >= 2 || level <= MIN) return nextF(level);
        level = Math.max(MIN, level - 10);
      } else {
        level += 5;
        if (level >= MAX) return nextF(MAX);
      }
      schedule(250);
    };
    play();
  }

  function finishEar() {
    stop();
    const prev = store.latestHearing();
    const other: 'left' | 'right' = ear === 'left' ? 'right' : 'left';
    store.update((d) => d.hearingTests.push({ id: uid(), date: new Date().toISOString(), left: res.left.length ? res.left : prev?.left ?? [], right: res.right.length ? res.right : prev?.right ?? [] }));
    const needOther = !res[other].length;
    swap(wrap,
      card('glow-lab', h('p', { class: 'eyebrow c-lab' }, 'Gespeichert'), h('p', { class: 'title-m' }, `${ear === 'left' ? 'Linkes' : 'Rechtes'} Ohr fertig`)),
      needOther ? btn(`Jetzt ${other === 'left' ? 'linkes' : 'rechtes'} Ohr`, () => { ear = other; run(); }, { variant: 'lab', size: 'lg', block: true }) : btn('Weiter: Somatik-Check', () => navigate('/somatic'), { variant: 'lab', size: 'lg', block: true, iconRight: 'chevR' }),
      chartCard());
  }

  function chartCard(): HTMLElement | null {
    const hr = store.latestHearing();
    const left = res.left.length ? res.left : hr?.left ?? [];
    const right = res.right.length ? res.right : hr?.right ?? [];
    if (!left.length && !right.length) return null;
    const m = store.latestMatch();
    const out = card(null, h('p', { class: 'title-m' }, 'Dein Hörprofil'), h('p', { class: 'small', style: 'margin:0 0 6px' }, 'Weiter unten = schlechter gehört'),
      lineChart({
        series: [
          { name: 'Links', color: 'var(--lab)', points: left.map((p) => ({ x: p.freq, y: p.level })) },
          { name: 'Rechts', color: 'var(--mind)', points: right.map((p) => ({ x: p.freq, y: p.level })) },
        ],
        xLog: true, yInvert: true, yMin: MIN, yMax: MAX, xMin: 500, xMax: 16000,
        xTicks: [500, 1000, 2000, 4000, 8000, 16000], xFormat: (x) => (x >= 1000 ? `${x / 1000}k` : String(x)),
        yTicks: [-90, -70, -50, -30, -10], yFormat: (y) => `${Math.round(y)}`,
        markers: m ? [{ x: m.freq, color: 'var(--tin)', label: 'Tinnitus' }] : [],
      }));
    const drop = (pts: HearingPoint[]) => mean(pts.filter((p) => p.freq >= 8000).map((p) => p.level)) - mean(pts.filter((p) => p.freq <= 2000).map((p) => p.level));
    if (left.length && right.length) {
      const dl = drop(left), dr = drop(right);
      const worst = Math.max(dl, dr);
      out.append(h('div', { class: 'grid-2 mt8' },
        h('div', { class: 'metric' }, h('div', { class: 'k' }, 'Hochton-Abfall links'), h('div', { class: 'v' }, `${dl.toFixed(0)}`, h('small', null, 'dB'))),
        h('div', { class: 'metric' }, h('div', { class: 'k' }, 'Hochton-Abfall rechts'), h('div', { class: 'v' }, `${dr.toFixed(0)}`, h('small', null, 'dB')))));
      if (worst > 20) out.append(callout(h('span', null, h('b', null, 'Deutlicher Hochton-Abfall. '), 'Hörgeräte gehören zu den am besten belegten Tinnitus-Maßnahmen, wenn ein Hörverlust vorliegt (UNITI-Studie 2025, S3-Leitlinie). Lass beim HNO ein Tonaudiogramm inklusive Hochtonbereich bis 16 kHz machen.'), 'warn'));
    }
    return out;
  }

  intro();
  return stop;
}
