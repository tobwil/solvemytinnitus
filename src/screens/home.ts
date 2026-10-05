import { h, card, note, button } from '../ui/dom';
import { store, today } from '../data/store';
import { formatHz } from '../audio/engine';
import { sparkBars } from '../ui/chart';
import { navigate } from '../main';
import { bestRiStimulus, describeStimulus } from './ri';

export function renderHome(root: HTMLElement): void {
  const d = store.get();
  const match = store.latestMatch();
  const matchL = store.latestMatch('left');
  const matchR = store.latestMatch('right');
  const todayStr = today();
  const todaySessions = d.sessions.filter((s) => s.date.slice(0, 10) === todayStr);
  const minutesToday = Math.round(todaySessions.reduce((a, s) => a + s.durationS, 0) / 60);
  const goal = d.settings.dailyGoalMin;
  const journalToday = d.journal.find((j) => j.date === todayStr);
  const best = bestRiStimulus(d.riTrials);

  root.appendChild(h('h1', null, d.settings.name ? `Hallo ${d.settings.name}` : 'Dein Tinnitus-Labor'));

  // Status hero
  const hero = h('div', { class: 'hero' });
  if (!match) {
    hero.append(
      h('div', { class: 'big-number' }, '?', h('small', null, 'Tinnitus-Frequenz noch unbekannt')),
      h('p', null, 'Alles in dieser App baut auf deiner persönlichen Tinnitus-Frequenz auf. Starte mit dem Matching, es dauert etwa 5 Minuten.'),
      button('Tinnitus jetzt matchen →', () => navigate('/match'), 'btn big'),
    );
  } else {
    const parts: HTMLElement[] = [];
    if (matchL) parts.push(h('div', { class: 'stat' }, h('div', { class: 'label' }, 'Links'), h('div', { class: 'value' }, formatHz(matchL.freq))));
    if (matchR) parts.push(h('div', { class: 'stat' }, h('div', { class: 'label' }, 'Rechts'), h('div', { class: 'value' }, formatHz(matchR.freq))));
    const both = store.latestMatch('both');
    if (both && !matchL && !matchR) parts.push(h('div', { class: 'stat' }, h('div', { class: 'label' }, 'Beide Ohren'), h('div', { class: 'value' }, formatHz(both.freq))));
    hero.append(
      h('div', { class: 'row' }, ...parts, h('div', { class: 'stat' }, h('div', { class: 'label' }, 'Heute'), h('div', { class: 'value' }, `${minutesToday} / ${goal} min`))),
      h('p', { class: 'muted' }, `Letztes Matching: ${new Date(match.date).toLocaleDateString('de-DE')} · Streuung ${(match.spreadOctaves * 12).toFixed(1)} Halbtöne`),
    );
  }
  root.appendChild(hero);

  // Next step
  const steps = card('Dein nächster Schritt');
  if (!match) {
    steps.append(h('p', null, '1. Tinnitus-Frequenz und Lautheit bestimmen.'));
  } else if (d.riTrials.length < 3) {
    steps.append(
      h('p', null, 'Finde im Residual-Inhibition-Labor heraus, welcher Klang deinen Tinnitus am stärksten unterdrückt. Das ist der Schlüssel zu einer wirklich personalisierten Therapie.'),
      button('RI-Labor öffnen →', () => navigate('/ri'), 'btn'),
    );
  } else if (minutesToday < goal) {
    steps.append(
      h('p', null, best ? `Dein wirksamster Klang bisher: ${describeStimulus(best.stimulus)} (Unterdrückung ${best.depth.toFixed(1)} Punkte).` : 'Starte eine Therapie-Sitzung.'),
      h('p', { class: 'muted' }, `Noch ${goal - minutesToday} Minuten bis zum Tagesziel.`),
      button('Therapie starten →', () => navigate('/therapy'), 'btn'),
    );
  } else {
    steps.append(note('Tagesziel erreicht. Stark. Trag noch kurz dein Tagebuch ein, damit wir den Verlauf sehen.', 'ok'));
  }
  if (!journalToday) {
    steps.append(h('p', { style: 'margin-top:10px' }, button('Tagebuch für heute ausfüllen', () => navigate('/journal'), 'btn secondary')));
  }
  root.appendChild(steps);

  // Trend
  const last14 = d.journal.slice(-14);
  if (last14.length) {
    const trend = card('Lautheit der letzten 14 Tage');
    trend.append(sparkBars(last14.map((j) => j.loudness), 10, 'var(--accent)'));
    const first = last14.slice(0, Math.ceil(last14.length / 2));
    const second = last14.slice(Math.ceil(last14.length / 2));
    const avg = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / (xs.length || 1);
    const delta = avg(second.map((j) => j.loudness)) - avg(first.map((j) => j.loudness));
    trend.append(h('p', { class: 'muted' }, last14.length > 3 ? `Trend: ${delta <= -0.3 ? 'leiser werdend ▼' : delta >= 0.3 ? 'lauter werdend ▲' : 'stabil ▶'} (${delta >= 0 ? '+' : ''}${delta.toFixed(1)})` : 'Mehr Einträge nötig für einen Trend.'));
    root.appendChild(trend);
  }

  root.appendChild(
    card(
      'Wie diese App arbeitet',
      h('ol', { class: 'steps' },
        h('li', null, h('b', null, 'Messen:'), ' Frequenz, Lautheit und Maskierungsschwelle deines Tinnitus bestimmen, Hörprofil erfassen.'),
        h('li', null, h('b', null, 'Analysieren:'), ' Im RI-Labor systematisch testen, welcher Klang bei dir Residual Inhibition (Nachhall-Stille) auslöst, und wie lange.'),
        h('li', null, h('b', null, 'Therapieren:'), ' Täglich mit dem individuell wirksamsten Verfahren arbeiten: Notched Sound, CR-Neuromodulation, Reset-Sitzungen, Klanganreicherung.'),
        h('li', null, h('b', null, 'Verfolgen:'), ' Tagebuch und Wochen-Check zeigen, ob und was sich verändert. Alle Daten bleiben auf deinem Gerät.'),
      ),
      note('Hinweis: Diese App ersetzt keine HNO-ärztliche Abklärung. Nach 20 Jahren Tinnitus ist ein aktuelles Audiogramm beim HNO sinnvoll, weil Hochton-Hörverlust die Wahl der Therapie beeinflusst.', 'warn'),
    ),
  );
}
