import { h, card, note, button, segmented } from '../ui/dom';
import { store, uid } from '../data/store';
import { engine, formatHz } from '../audio/engine';
import { playToneBursts, Voice } from '../audio/synth';
import { lineChart } from '../ui/chart';
import { HearingPoint } from '../data/model';

const FREQS = [500, 1000, 2000, 3000, 4000, 6000, 8000, 10000, 12000, 14000, 16000];
const START_LEVEL = -40;
const MIN_LEVEL = -90;
const MAX_LEVEL = -6;

/**
 * Simplified Hughson-Westlake: level rises in 5 dB steps until heard, then drops 10 dB and rises again;
 * threshold = lowest level heard twice on ascending runs.
 */
export function renderHearing(root: HTMLElement): () => void {
  let ear: 'left' | 'right' = 'left';
  let voice: Voice | null = null;
  const results: { left: HearingPoint[]; right: HearingPoint[] } = { left: [], right: [] };
  let fi = 0;
  let level = START_LEVEL;
  let heardAt: number[] = [];
  let running = false;
  let playing = false;

  root.appendChild(h('h1', null, 'Hörprofil'));
  root.appendChild(note('Ergebnisse sind relativ (0 dB = Referenzpegel der App), nicht als klinisches Audiogramm zu lesen. Sie zeigen die Form deines Hörprofils: ein Abfall im Hochtonbereich ist nach Konzert-Lärm typisch und liegt meist in der Nähe der Tinnitus-Frequenz.'));

  const earSeg = segmented([{ value: 'left', label: 'Linkes Ohr' }, { value: 'right', label: 'Rechtes Ohr' }], ear, (v) => { ear = v; reset(); });
  const status = h('div', { class: 'big-number' }, '—');
  const sub = h('p', { class: 'muted' }, 'Drücke Start. Es erklingen drei kurze Pieptöne. Drücke „Gehört“, sobald du sie hörst, sonst „Nicht gehört“.');
  const btnStart = button('Start', () => start(), 'btn');
  const btnHeard = button('✓ Gehört', () => answer(true), 'btn big');
  const btnNot = button('✗ Nicht gehört', () => answer(false), 'btn big secondary');
  const btnReplay = button('↻ Wiederholen', () => play(), 'btn small secondary');
  btnHeard.disabled = btnNot.disabled = btnReplay.disabled = true;

  const panel = card(null, earSeg.el, status, sub, h('div', { class: 'row' }, btnStart, btnReplay), h('div', { class: 'row', style: 'margin-top:10px' }, btnHeard, btnNot));
  root.appendChild(panel);

  const chartHost = h('div');
  root.appendChild(card('Dein Hörprofil', chartHost));
  drawChart();

  function reset() {
    fi = 0;
    level = START_LEVEL;
    heardAt = [];
    running = false;
    btnHeard.disabled = btnNot.disabled = btnReplay.disabled = true;
    btnStart.disabled = false;
    status.textContent = '—';
  }

  async function start() {
    await engine.ensure();
    running = true;
    btnStart.disabled = true;
    btnHeard.disabled = btnNot.disabled = btnReplay.disabled = false;
    fi = 0;
    level = START_LEVEL;
    heardAt = [];
    results[ear] = [];
    play();
  }

  function play() {
    if (!running) return;
    voice?.stop(10);
    status.textContent = formatHz(FREQS[fi]);
    status.appendChild(h('small', null, `${level} dB`));
    playing = true;
    voice = playToneBursts(FREQS[fi], ear, level);
    setTimeout(() => (playing = false), 1100);
  }

  function answer(heard: boolean) {
    if (!running) return;
    if (heard) {
      heardAt.push(level);
      const count = heardAt.filter((l) => l === level).length;
      if (count >= 2 || level <= MIN_LEVEL) {
        results[ear].push({ freq: FREQS[fi], level });
        nextFreq();
        return;
      }
      level = Math.max(MIN_LEVEL, level - 10);
    } else {
      level = Math.min(MAX_LEVEL, level + 5);
      if (level >= MAX_LEVEL) {
        results[ear].push({ freq: FREQS[fi], level: MAX_LEVEL });
        nextFreq();
        return;
      }
    }
    setTimeout(play, playing ? 400 : 150);
  }

  function nextFreq() {
    fi++;
    heardAt = [];
    level = START_LEVEL;
    drawChart();
    if (fi >= FREQS.length) {
      running = false;
      btnHeard.disabled = btnNot.disabled = btnReplay.disabled = true;
      btnStart.disabled = false;
      status.textContent = 'Fertig';
      save();
      return;
    }
    setTimeout(play, 300);
  }

  function save() {
    const prev = store.latestHearing();
    const left = results.left.length ? results.left : prev?.left ?? [];
    const right = results.right.length ? results.right : prev?.right ?? [];
    store.update((d) => {
      d.hearingTests.push({ id: uid(), date: new Date().toISOString(), left, right });
    });
    drawChart();
    sub.textContent = `Ohr ${ear === 'left' ? 'links' : 'rechts'} gespeichert. Wechsle oben das Ohr, um das andere zu testen.`;
  }

  function drawChart() {
    chartHost.innerHTML = '';
    const prev = store.latestHearing();
    const left = results.left.length ? results.left : prev?.left ?? [];
    const right = results.right.length ? results.right : prev?.right ?? [];
    const match = store.latestMatch();
    const series = [
      { name: 'Links', color: '#4fd1c5', points: left.map((p) => ({ x: p.freq, y: p.level })) },
      { name: 'Rechts', color: '#fc8181', points: right.map((p) => ({ x: p.freq, y: p.level })) },
    ];
    if (match) {
      series.push({ name: `Tinnitus ${formatHz(match.freq)}`, color: '#f6ad55', points: [{ x: match.freq, y: MAX_LEVEL }, { x: match.freq, y: MIN_LEVEL }], dashed: true } as never);
    }
    chartHost.appendChild(
      lineChart({
        series,
        xLog: true,
        yInvert: true,
        yMin: MIN_LEVEL,
        yMax: MAX_LEVEL,
        xTicks: [500, 1000, 2000, 4000, 8000, 16000],
        xFormat: (x) => (x >= 1000 ? `${x / 1000}k` : String(x)),
        yFormat: (y) => `${Math.round(y)}`,
        xLabel: 'Frequenz (Hz)',
        yLabel: 'Schwelle (dB rel.)',
      }),
    );
    if (left.length && right.length) {
      const hf = (pts: HearingPoint[]) => pts.filter((p) => p.freq >= 6000).map((p) => p.level);
      const lf = (pts: HearingPoint[]) => pts.filter((p) => p.freq <= 2000).map((p) => p.level);
      const avg = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN);
      const dropL = avg(hf(left)) - avg(lf(left));
      const dropR = avg(hf(right)) - avg(lf(right));
      chartHost.appendChild(h('p', { class: 'muted' }, `Hochton-Abfall (≥6 kHz vs. ≤2 kHz): links ${dropL.toFixed(0)} dB, rechts ${dropR.toFixed(0)} dB. ${Math.max(dropL, dropR) > 25 ? 'Deutlicher Hochton-Abfall: eine Versorgung mit Hörgeräten/Hochton-Verstärkung kann Tinnitus messbar reduzieren, sprich das beim HNO an.' : ''}`));
    }
  }

  return () => voice?.stop(10);
}
