import { h, card, note, button, slider, segmented } from '../ui/dom';
import { store } from '../data/store';
import { toast } from '../main';
import { Ear } from '../data/model';

export function renderSettings(root: HTMLElement): void {
  const s = store.get().settings;
  root.appendChild(h('h1', null, 'Einstellungen & Daten'));
  const name = h('input', { type: 'text', value: s.name, placeholder: 'Dein Name (optional)' }) as HTMLInputElement;
  name.addEventListener('change', () => store.update((d) => (d.settings.name = name.value.trim())));
  root.append(
    card('Profil',
      name,
      h('h3', null, 'Bevorzugtes Ohr'),
      segmented<Ear>([{ value: 'left', label: 'Links' }, { value: 'right', label: 'Rechts' }, { value: 'both', label: 'Beide' }], s.preferredEar, (v) => store.update((d) => (d.settings.preferredEar = v))).el,
      slider({ min: 0.5, max: 2, step: 0.25, value: s.notchWidthOctaves, label: 'Standard-Notch-Breite (Oktaven)', format: (v) => `${v}`, onInput: () => {}, onChange: (v) => store.update((d) => (d.settings.notchWidthOctaves = v)) }).el,
      slider({ min: 10, max: 240, step: 10, value: s.dailyGoalMin, label: 'Tagesziel Therapie', format: (v) => `${v} min`, onInput: () => {}, onChange: (v) => store.update((d) => (d.settings.dailyGoalMin = v)) }).el,
    ),
    card('Daten',
      h('p', { class: 'muted' }, 'Alle Daten liegen ausschließlich lokal in diesem Browser. Exportiere regelmäßig, um nichts zu verlieren oder auf ein anderes Gerät zu wechseln.'),
      h('div', { class: 'row' },
        button('Export (JSON)', () => {
          const blob = new Blob([store.exportJson()], { type: 'application/json' });
          const a = h('a', { href: URL.createObjectURL(blob), download: `tinnitus-lab-${new Date().toISOString().slice(0, 10)}.json` });
          a.click();
        }, 'btn secondary'),
        button('Import', () => {
          const inp = h('input', { type: 'file', accept: 'application/json' }) as HTMLInputElement;
          inp.addEventListener('change', async () => {
            const f = inp.files?.[0];
            if (!f) return;
            try { store.importJson(await f.text()); toast('Daten importiert'); location.reload(); } catch (e) { toast('Import fehlgeschlagen: ' + (e as Error).message); }
          });
          inp.click();
        }, 'btn secondary'),
        button('Alles löschen', () => { if (confirm('Wirklich alle Daten löschen?')) { store.reset(); location.reload(); } }, 'btn danger'),
      ),
    ),
    card('Als App installieren',
      h('p', null, h('b', null, 'iPhone/iPad:'), ' In Safari öffnen → Teilen-Symbol → „Zum Home-Bildschirm“. Danach läuft die App im Vollbild und offline.'),
      h('p', null, h('b', null, 'Mac (Safari 17+):'), ' Ablage → „Zum Dock hinzufügen“. ', h('b', null, 'Chrome/Edge:'), ' Installieren-Symbol in der Adressleiste.'),
      note('Hinweis für iOS: Im Hintergrund stoppt Safari die Audiowiedergabe nach einiger Zeit. Für lange Sitzungen Bildschirm anlassen oder die App im Vordergrund halten.'),
    ),
  );
}
