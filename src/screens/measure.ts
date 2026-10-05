import { h, card, button } from '../ui/dom';
import { store } from '../data/store';
import { formatHz } from '../audio/engine';
import { navigate } from '../main';

export function renderMeasure(root: HTMLElement): void {
  const d = store.get();
  const match = store.latestMatch();
  const hearing = store.latestHearing();
  root.appendChild(h('h1', null, 'Messen & Analysieren'));
  root.appendChild(h('p', { class: 'muted' }, 'Benutze Kopfhörer (am besten Over-Ear oder In-Ear mit guter Abdichtung) in einer ruhigen Umgebung. Stelle die Lautstärke oben so ein, dass Töne angenehm leise, aber klar hörbar sind.'));

  const mk = (title: string, desc: string, status: string, path: string, cta: string) =>
    card(null,
      h('div', { class: 'mode-card', on: { click: () => navigate(path) } },
        h('div', { class: 'title' }, title),
        h('div', { class: 'desc' }, desc),
        h('p', null, h('span', { class: 'pill accent' }, status)),
        button(cta, () => navigate(path), 'btn small'),
      ));

  root.append(
    mk('1 · Tinnitus-Matching', 'Frequenz, Klangfarbe, Lautheit und minimale Maskierungsschwelle (MML) deines Tinnitus bestimmen. Grundlage für alle Therapien.',
      match ? `Zuletzt: ${formatHz(match.freq)} (${match.ear === 'both' ? 'beide' : match.ear === 'left' ? 'links' : 'rechts'})` : 'Noch nicht gemessen', '/match', match ? 'Erneut matchen' : 'Starten'),
    mk('2 · Hörprofil', 'Relativer Hörtest von 500 Hz bis 16 kHz pro Ohr. Zeigt den typischen Hochton-Abfall nach Lärmtrauma und wo dein Tinnitus im Hörprofil liegt.',
      hearing ? `Zuletzt: ${new Date(hearing.date).toLocaleDateString('de-DE')}` : 'Noch nicht gemessen', '/hearing', hearing ? 'Erneut testen' : 'Starten'),
    mk('3 · Residual-Inhibition-Labor', 'Experimentell bestimmen, welcher Klang (Ton, Schmalbandrauschen, Breitband, Notched) deinen Tinnitus nach dem Abschalten am stärksten und längsten unterdrückt.',
      d.riTrials.length ? `${d.riTrials.length} Durchgänge` : 'Noch keine Durchgänge', '/ri', 'Öffnen'),
  );
}
