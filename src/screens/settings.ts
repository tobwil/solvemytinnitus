import { h, page, header, card, btn, range, seg, toggle, callout, sectionH, toast } from '../ui/dom';
import { store } from '../data/store';
import { navigate } from '../router';
import { Ear } from '../data/model';

export function renderSettings(root: HTMLElement): void {
  const s = store.get().settings;
  const name = h('input', { type: 'text', value: s.name, placeholder: 'Name (optional)' }) as HTMLInputElement;
  name.addEventListener('change', () => store.update((d) => (d.settings.name = name.value.trim())));
  const counts = store.get();
  root.appendChild(page(
    header('Einstellungen', 'Einstellungen & Daten'),
    card(null,
      h('p', { class: 'title-m' }, 'Profil'), name,
      h('p', { class: 'title-m mt16' }, 'Bevorzugtes Ohr'),
      seg<Ear>([{ value: 'both', label: 'Beide' }, { value: 'left', label: 'Links' }, { value: 'right', label: 'Rechts' }], s.preferredEar, (v) => store.update((d) => (d.settings.preferredEar = v))).el,
      range({ label: 'Standard-Breite der Notch', min: 0.5, max: 2, step: 0.25, value: s.notchWidthOctaves, format: (v) => `${v} Okt.`, onInput: () => {}, onChange: (v) => store.update((d) => (d.settings.notchWidthOctaves = v)) }).el,
      range({ label: 'Tagesziel Klangtherapie', min: 10, max: 180, step: 10, value: s.dailyGoalMin, format: (v) => `${v} min`, onInput: () => {}, onChange: (v) => store.update((d) => (d.settings.dailyGoalMin = v)) }).el,
      toggle('RI-Labor verblindet', s.blindRi, (v) => store.update((d) => (d.settings.blindRi = v)))),
    btn('Kopfhörer und Lautstärke neu einrichten', () => navigate('/onboarding?step=2'), { variant: 'ghost', block: true, icon: 'headphones' }),
    sectionH('Daten'),
    card(null,
      h('p', { class: 'body', style: 'margin-top:0' }, `Alles liegt nur lokal in diesem Browser: ${counts.checkins.length} Check-ins, ${counts.sessions.length} Sitzungen, ${counts.riTrials.length} RI-Durchgänge, ${counts.journal.length} Tagebucheinträge. Exportiere regelmäßig, um nichts zu verlieren oder das Gerät zu wechseln.`),
      h('div', { class: 'grid-2' },
        btn('Export', () => {
          const blob = new Blob([store.exportJson()], { type: 'application/json' });
          const a = h('a', { href: URL.createObjectURL(blob), download: `tinnitus-lab-${new Date().toISOString().slice(0, 10)}.json` });
          document.body.appendChild(a);
          a.click();
          a.remove();
        }, { variant: 'ghost', icon: 'download' }),
        btn('Import', () => {
          const inp = h('input', { type: 'file', accept: 'application/json' }) as HTMLInputElement;
          inp.addEventListener('change', async () => {
            const f = inp.files?.[0];
            if (!f) return;
            try { store.importJson(await f.text()); toast('Daten importiert'); navigate('/'); } catch (e) { toast(`Import fehlgeschlagen: ${(e as Error).message}`, 'alert'); }
          });
          inp.click();
        }, { variant: 'ghost', icon: 'upload' })),
      h('div', { class: 'mt8' }, btn('Alle Daten löschen', () => { if (confirm('Wirklich alle Daten unwiderruflich löschen?')) { store.reset(); navigate('/onboarding'); } }, { variant: 'text', icon: 'trash' }))),
    sectionH('Als App installieren'),
    card(null, h('div', { class: 'prose' },
      h('p', null, h('b', null, 'iPhone / iPad: '), 'In Safari öffnen, Teilen-Symbol, „Zum Home-Bildschirm“.'),
      h('p', null, h('b', null, 'Mac: '), 'Safari, Ablage, „Zum Dock hinzufügen“. Oder in Chrome/Edge das Installieren-Symbol in der Adressleiste.'))),
    callout('iOS pausiert Audio, wenn der Bildschirm gesperrt wird und die App nicht im Vordergrund ist. Für lange Sitzungen die App geöffnet lassen.'),
    h('p', { class: 'small center mt24' }, 'Tinnitus Lab · kein Medizinprodukt · ersetzt keine ärztliche Behandlung'),
  ));
}
