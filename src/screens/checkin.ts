import { h, btn, page, header, card, scale10, toast } from '../ui/dom';
import { store, uid } from '../data/store';
import { navigate } from '../router';

export function renderCheckin(root: HTMLElement): void {
  let loud: number | null = null;
  let dist: number | null = null;
  const save = btn('Speichern', () => {
    store.update((d) => d.checkins.push({ id: uid(), ts: new Date().toISOString(), loudness: loud!, distress: dist! }));
    toast('Check-in gespeichert');
    navigate('/');
  }, { size: 'lg', block: true, disabled: true });
  const upd = () => (save.disabled = loud === null || dist === null);
  root.appendChild(page(
    header('Kurz-Check-in', 'Wie ist es gerade?', 'Zwei Fragen, zehn Sekunden. Mehrere Messungen am Tag zeigen Schwankungen und Auslöser viel genauer als ein Tageswert.'),
    card(null, h('p', { class: 'title-m' }, 'Wie laut ist dein Tinnitus jetzt?'), scale10(null, (v) => { loud = v; upd(); }, ['nicht hörbar', 'extrem laut'])),
    card(null, h('p', { class: 'title-m' }, 'Wie sehr belastet er dich gerade?'), scale10(null, (v) => { dist = v; upd(); }, ['gar nicht', 'extrem'])),
    save,
  ));
}
