import { h, page, header, card, btn, chip, callout } from '../ui/dom';
import { icon } from '../ui/icons';
import { spectrumBars } from '../ui/chart';
import { store } from '../data/store';
import { labSteps } from '../data/program';
import { navigate } from '../router';

export function renderLab(root: HTMLElement): void {
  const steps = labSteps();
  const doneN = steps.filter((s) => s.done).length;
  const nextIdx = steps.findIndex((s) => !s.done);
  const spec = store.latestSpectrum();

  const list = h('div', { class: 'steps' }, ...steps.map((s, i) => {
    const el = h('div', { class: `step ${s.done ? 'done' : i === nextIdx ? 'next' : ''}` },
      h('div', { class: 'dot' }, s.done ? icon('check') : String(i + 1)),
      h('div', { class: 's-body' },
        h('div', { class: 's-title' }, s.title),
        h('div', { class: 's-sub' }, s.sub),
        s.meta ? h('div', { class: 's-meta' }, chip(s.meta, s.done ? 'good' : 'lab')) : null),
      icon('chevR', 'chev'));
    el.addEventListener('click', () => navigate(s.path));
    return el;
  }));

  root.appendChild(page(
    header('Labor', 'Deinen Tinnitus vermessen', doneN === steps.length
      ? 'Alle Messungen abgeschlossen. Wiederhole Spektrum und RI-Labor alle 4 Wochen, um Veränderungen zu sehen.'
      : `${doneN} von ${steps.length} Schritten erledigt. Jede Messung macht die Therapie präziser.`),
    nextIdx >= 0 ? btn(`Weiter: ${steps[nextIdx].title}`, () => navigate(steps[nextIdx].path), { variant: 'lab', size: 'lg', block: true, iconRight: 'chevR' }) : null,
    card('mt16', list),
    spec ? card(null, h('p', { class: 'title-m' }, 'Dein Tinnitus-Spektrum'), h('p', { class: 'small', style: 'margin:0 0 8px' }, 'Wie ähnlich jeder Testton deinem Tinnitus war (0–10). Gelb: höchste Ähnlichkeit.'), spectrumBars(spec.points, { max: 10, peak: spec.peak })) : null,
    callout('Ruhige Umgebung, gute Kopfhörer, und nicht direkt nach lauter Musik oder Lärm messen. Hochfrequenter Tinnitus schwankt; mehrere Messungen an verschiedenen Tagen machen das Ergebnis robust.'),
  ));
}
