import { h, card, note, button, slider, clear, fmtDate } from '../ui/dom';
import { store, uid, today } from '../data/store';
import { lineChart } from '../ui/chart';
import { toast } from '../main';
import { JournalEntry } from '../data/model';

const WEEKLY_ITEMS = [
  'Wie oft hast du den Tinnitus diese Woche bewusst wahrgenommen?',
  'Wie stark hat er dich beim Einschlafen oder Durchschlafen gestört?',
  'Wie stark hat er deine Konzentration beeinträchtigt?',
  'Wie sehr hat er dich verärgert, gereizt oder gestresst?',
  'Wie sehr hast du ruhige Situationen vermieden?',
  'Wie stark hat er das Hören oder Verstehen von Gesprächen gestört?',
  'Wie hoffnungslos oder entmutigt hast du dich wegen des Tinnitus gefühlt?',
  'Wie stark hat er deine Lebensqualität insgesamt beeinträchtigt?',
];
const WEEKLY_SCALE = ['Gar nicht', 'Wenig', 'Mäßig', 'Stark', 'Extrem'];

export function renderJournal(root: HTMLElement): void {
  root.appendChild(h('h1', null, 'Tagebuch & Verlauf'));
  const host = h('div');
  root.appendChild(host);
  draw();

  function draw() {
    clear(host);
    const d = store.get();
    const t = today();
    const existing = d.journal.find((j) => j.date === t);
    const entry: JournalEntry = existing ? { ...existing } : { id: uid(), date: t, loudness: 5, distress: 5, sleep: 5, stress: 5, noiseExposure: false, caffeine: false, alcohol: false, notes: '' };
    const cb = (label: string, key: 'noiseExposure' | 'caffeine' | 'alcohol') => {
      const input = h('input', { type: 'checkbox', checked: entry[key] }) as HTMLInputElement;
      input.addEventListener('change', () => (entry[key] = input.checked));
      return h('label', { class: 'checkbox' }, input, label);
    };
    const notes = h('textarea', { rows: 2, placeholder: 'Notizen (z. B. Auslöser, Besonderheiten)' }) as HTMLTextAreaElement;
    notes.value = entry.notes;
    notes.addEventListener('input', () => (entry.notes = notes.value));

    host.append(card(existing ? 'Heutiger Eintrag (bearbeiten)' : 'Heutiger Eintrag',
      slider({ min: 0, max: 10, step: 1, value: entry.loudness, label: 'Lautheit des Tinnitus heute', onInput: (v) => (entry.loudness = v) }).el,
      slider({ min: 0, max: 10, step: 1, value: entry.distress, label: 'Belastung / Störung durch den Tinnitus', onInput: (v) => (entry.distress = v) }).el,
      slider({ min: 0, max: 10, step: 1, value: entry.sleep, label: 'Schlafqualität letzte Nacht (10 = sehr gut)', onInput: (v) => (entry.sleep = v) }).el,
      slider({ min: 0, max: 10, step: 1, value: entry.stress, label: 'Stresslevel heute', onInput: (v) => (entry.stress = v) }).el,
      h('div', { class: 'row' }, cb('Lärm ausgesetzt', 'noiseExposure'), cb('Koffein', 'caffeine'), cb('Alkohol', 'alcohol')),
      notes,
      h('p', { style: 'margin-top:10px' }, button('Speichern', () => {
        store.update((s) => {
          const i = s.journal.findIndex((j) => j.date === t);
          if (i >= 0) s.journal[i] = entry; else s.journal.push(entry);
          s.journal.sort((a, b) => a.date.localeCompare(b.date));
        });
        toast('Eintrag gespeichert');
        draw();
      }, 'btn big')),
    ));

    // Charts
    const j = d.journal;
    const toX = (date: string) => new Date(date + 'T12:00:00').getTime();
    host.append(card('Verlauf',
      lineChart({
        series: [
          { name: 'Lautheit', color: '#4fd1c5', points: j.map((e) => ({ x: toX(e.date), y: e.loudness })) },
          { name: 'Belastung', color: '#fc8181', points: j.map((e) => ({ x: toX(e.date), y: e.distress })) },
          { name: 'Schlaf', color: '#7f9cf5', points: j.map((e) => ({ x: toX(e.date), y: e.sleep })), dashed: true },
        ],
        yMin: 0, yMax: 10, xFormat: (x) => new Date(x).toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit' }), height: 240,
      }),
      j.length >= 7 ? correlations(j) : h('p', { class: 'muted' }, 'Ab 7 Einträgen zeigen wir Zusammenhänge zwischen Auslösern und Lautheit.'),
    ));

    // Session effect
    const sessions = d.sessions.filter((s) => s.pre !== null && s.post !== null);
    if (sessions.length) {
      const byMode = new Map<string, number[]>();
      for (const s of sessions) byMode.set(s.mode, [...(byMode.get(s.mode) ?? []), (s.post as number) - (s.pre as number)]);
      const rows = [...byMode.entries()].map(([mode, deltas]) => {
        const avg = deltas.reduce((a, b) => a + b, 0) / deltas.length;
        return h('li', null, h('span', null, modeLabel(mode), ' ', h('span', { class: 'pill' }, `${deltas.length}×`)), h('span', { class: `pill ${avg < -0.5 ? 'ok' : avg > 0.5 ? 'warn' : ''}` }, `Ø ${avg >= 0 ? '+' : ''}${avg.toFixed(1)}`));
      });
      host.append(card('Sofort-Effekt der Sitzungen (nachher − vorher)', h('ul', { class: 'list' }, ...rows), h('p', { class: 'muted' }, 'Negative Werte = leiser nach der Sitzung. Das misst den kurzfristigen Effekt, nicht die langfristige Veränderung.')));
    }

    // Weekly check
    const lastWeekly = d.weekly[d.weekly.length - 1];
    const due = !lastWeekly || Date.now() - new Date(lastWeekly.date).getTime() > 6 * 86400e3;
    const answers: number[] = new Array(WEEKLY_ITEMS.length).fill(-1);
    const weeklyCard = card('Wochen-Check',
      h('p', { class: 'muted' }, 'Acht Fragen zur Belastung in der letzten Woche (0–100 Punkte, niedriger ist besser). Kein validiertes klinisches Instrument, aber über Wochen gut vergleichbar.'),
      lastWeekly ? h('p', null, `Letzter Check: ${fmtDate(lastWeekly.date)} · ${lastWeekly.score} Punkte`) : null,
    );
    if (due) {
      WEEKLY_ITEMS.forEach((q, i) => {
        const row = h('div', { class: 'rating' });
        WEEKLY_SCALE.forEach((lab, v) => {
          const b = button(lab, () => { row.querySelectorAll('button').forEach((x) => x.classList.remove('active')); b.classList.add('active'); answers[i] = v; }, '');
          row.appendChild(b);
        });
        weeklyCard.append(h('p', { style: 'margin-bottom:4px' }, `${i + 1}. ${q}`), row);
      });
      weeklyCard.append(h('p', { style: 'margin-top:12px' }, button('Wochen-Check speichern', () => {
        if (answers.some((a) => a < 0)) { toast('Bitte alle Fragen beantworten'); return; }
        const score = Math.round((answers.reduce((a, b) => a + b, 0) / (4 * WEEKLY_ITEMS.length)) * 100);
        store.update((s) => s.weekly.push({ id: uid(), date: new Date().toISOString(), answers: answers.slice(), score }));
        toast(`Gespeichert: ${score} Punkte`);
        draw();
      }, 'btn')));
    } else {
      weeklyCard.append(note('Der nächste Wochen-Check ist in ein paar Tagen fällig.', 'ok'));
    }
    if (d.weekly.length > 1) {
      weeklyCard.append(lineChart({ series: [{ name: 'Belastungs-Score', color: '#f6ad55', points: d.weekly.map((w) => ({ x: new Date(w.date).getTime(), y: w.score })) }], yMin: 0, yMax: 100, height: 180, xFormat: (x) => new Date(x).toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit' }) }));
    }
    host.append(weeklyCard);
  }
}

function modeLabel(mode: string): string {
  return ({ notched: 'Notched Sound', cr: 'CR-Neuromodulation', enrichment: 'Klanganreicherung', reset: 'Reset-Sitzung', bimodal: 'Bimodal' } as Record<string, string>)[mode] ?? mode;
}

function correlations(j: JournalEntry[]): HTMLElement {
  const avg = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN);
  const items: HTMLElement[] = [];
  const flag = (label: string, key: 'noiseExposure' | 'caffeine' | 'alcohol') => {
    const w = j.filter((e) => e[key]).map((e) => e.loudness);
    const wo = j.filter((e) => !e[key]).map((e) => e.loudness);
    if (w.length >= 2 && wo.length >= 2) {
      const dlt = avg(w) - avg(wo);
      items.push(h('li', null, h('span', null, `${label} (${w.length} Tage)`), h('span', { class: `pill ${dlt > 0.7 ? 'warn' : dlt < -0.7 ? 'ok' : ''}` }, `Lautheit ${dlt >= 0 ? '+' : ''}${dlt.toFixed(1)}`)));
    }
  };
  flag('Lärm', 'noiseExposure');
  flag('Koffein', 'caffeine');
  flag('Alkohol', 'alcohol');
  // sleep/stress correlation (Pearson)
  const pear = (xs: number[], ys: number[]) => {
    const mx = avg(xs), my = avg(ys);
    let num = 0, dx = 0, dy = 0;
    for (let i = 0; i < xs.length; i++) { num += (xs[i] - mx) * (ys[i] - my); dx += (xs[i] - mx) ** 2; dy += (ys[i] - my) ** 2; }
    return dx && dy ? num / Math.sqrt(dx * dy) : 0;
  };
  const rSleep = pear(j.map((e) => e.sleep), j.map((e) => e.loudness));
  const rStress = pear(j.map((e) => e.stress), j.map((e) => e.loudness));
  items.push(h('li', null, h('span', null, 'Schlaf ↔ Lautheit'), h('span', { class: `pill ${rSleep < -0.3 ? 'accent' : ''}` }, `r = ${rSleep.toFixed(2)}`)));
  items.push(h('li', null, h('span', null, 'Stress ↔ Lautheit'), h('span', { class: `pill ${rStress > 0.3 ? 'warn' : ''}` }, `r = ${rStress.toFixed(2)}`)));
  return h('div', null, h('h3', null, 'Zusammenhänge'), h('ul', { class: 'list' }, ...items));
}
