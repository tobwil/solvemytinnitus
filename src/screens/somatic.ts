import { h, btn, page, header, card, swap, callout, progress, choices, wait } from '../ui/dom';
import { icon } from '../ui/icons';
import { store, uid } from '../data/store';
import { navigate } from '../router';
import { SomaticManeuver } from '../data/model';
import { chime } from '../audio/synth';
import { engine } from '../audio/engine';

const MANEUVERS: { id: SomaticManeuver; title: string; how: string; ico: string }[] = [
  { id: 'clench', title: 'Zähne fest zusammenbeißen', how: 'Beiße die Backenzähne kräftig aufeinander.', ico: 'jaw' },
  { id: 'jaw-forward', title: 'Unterkiefer nach vorn', how: 'Schieb den Unterkiefer so weit wie möglich nach vorn.', ico: 'jaw' },
  { id: 'jaw-open', title: 'Mund weit öffnen', how: 'Öffne den Mund so weit es angenehm geht.', ico: 'jaw' },
  { id: 'head-forward', title: 'Stirn gegen die Hand', how: 'Hand an die Stirn, Kopf kräftig nach vorn drücken, ohne dass er sich bewegt.', ico: 'hand' },
  { id: 'head-back', title: 'Hinterkopf gegen die Hand', how: 'Hand an den Hinterkopf, Kopf kräftig nach hinten drücken.', ico: 'hand' },
  { id: 'head-left', title: 'Kopf nach links gegen die Hand', how: 'Linke Hand an die linke Schläfe, Kopf dagegen drücken.', ico: 'hand' },
  { id: 'head-right', title: 'Kopf nach rechts gegen die Hand', how: 'Rechte Hand an die rechte Schläfe, Kopf dagegen drücken.', ico: 'hand' },
  { id: 'gaze', title: 'Blick ganz zur Seite', how: 'Schau ohne Kopfbewegung so weit wie möglich nach links, dann nach rechts.', ico: 'eye' },
];

/**
 * Somatic modulation screen (after Sanchez et al. 2002, Michiels et al. 2018 criteria):
 * ~65 % of people with tinnitus can change it via jaw/neck maneuvers.
 */
export function renderSomatic(root: HTMLElement): () => void {
  let alive = true;
  const wrap = h('div');
  root.appendChild(page(header('Labor · Schritt 5', 'Somatik-Check'), wrap));

  function intro() {
    swap(wrap,
      h('p', { class: 'lead' }, 'Bei rund zwei Dritteln der Betroffenen verändert sich der Tinnitus, wenn Kiefer- oder Nackenmuskeln angespannt werden. Das zeigt eine Verschaltung zwischen Hörbahn und Körperwahrnehmung, und genau dort setzen bimodale Therapien an.'),
      card(null, h('ul', { class: 'list' },
        ...[['jaw', '8 Bewegungen, je 5 Sekunden'], ['ear', 'Danach: lauter, leiser, gleich oder anders?'], ['clock', 'Dauer: ca. 3 Minuten']].map(([i, t]) =>
          h('li', null, h('span', { class: 'li-ico lab' }, icon(i)), h('div', { class: 'li-main li-title' }, t))))),
      callout('Nur mit mäßiger Kraft und nichts, was schmerzt. Bei Kiefergelenk- oder Nackenbeschwerden die entsprechenden Übungen überspringen.', 'warn'),
      btn('Starten', () => run(), { variant: 'lab', size: 'lg', block: true }));
  }

  async function run() {
    const results: { maneuver: SomaticManeuver; change: -1 | 0 | 1 | 2 }[] = [];
    for (let i = 0; i < MANEUVERS.length && alive; i++) {
      const m = MANEUVERS[i];
      // prepare
      await new Promise<void>((res) => {
        swap(wrap, progress(MANEUVERS.length, i),
          card('like-stage', h('div', { class: 'like-orb' }, h('div', { class: 'core' }, icon(m.ico))), h('p', { class: 'title-l' }, m.title), h('p', { class: 'body' }, m.how)),
          btn('Bereit, 5 Sekunden', () => res(), { variant: 'lab', size: 'lg', block: true }),
          h('div', { class: 'center' }, btn('Überspringen', () => { results.push({ maneuver: m.id, change: 0 }); res(); }, { variant: 'text' })));
      });
      if (results.find((r) => r.maneuver === m.id)) continue;
      await engine.ensure();
      chime(-34);
      for (let s = 5; s > 0 && alive; s--) {
        swap(wrap, progress(MANEUVERS.length, i), card('like-stage', h('div', { class: 'like-orb playing' }, h('div', { class: 'core num', style: 'font-size:28px;font-weight:700' }, String(s))), h('p', { class: 'title-m' }, m.title), h('p', { class: 'small' }, 'Halten und auf den Tinnitus achten …')));
        await wait(1000);
      }
      chime(-34);
      const change = await new Promise<-1 | 0 | 1 | 2>((res) => {
        swap(wrap, progress(MANEUVERS.length, i),
          h('p', { class: 'title-l' }, 'Was hat sich verändert?'),
          h('p', { class: 'body' }, 'Während der Bewegung, verglichen mit vorher.'),
          choices<string>([
            { value: '1', title: 'Lauter', icon: 'volume' },
            { value: '-1', title: 'Leiser', icon: 'wind' },
            { value: '2', title: 'Tonhöhe oder Klang anders', icon: 'wave' },
            { value: '0', title: 'Keine Veränderung', icon: 'close' },
          ], null, (v) => setTimeout(() => res(Number(v) as -1 | 0 | 1 | 2), 200)));
      });
      results.push({ maneuver: m.id, change });
    }
    if (!alive) return;
    const somatic = results.some((r) => r.change !== 0);
    store.update((d) => d.somatic.push({ id: uid(), date: new Date().toISOString(), results, somatic }));
    const changed = results.filter((r) => r.change !== 0).map((r) => MANEUVERS.find((m) => m.id === r.maneuver)!.title);
    swap(wrap,
      card(somatic ? 'glow-tin' : 'glow-lab',
        h('p', { class: 'eyebrow' }, 'Ergebnis'),
        h('p', { class: 'title-l' }, somatic ? 'Dein Tinnitus ist somatisch modulierbar' : 'Keine somatische Modulation'),
        somatic ? h('p', { class: 'body' }, `Verändert bei: ${changed.join(', ')}.`) : null),
      somatic
        ? callout(h('span', null, 'Das bedeutet: Kiefer- und Nackenspannung beeinflussen deinen Tinnitus. ', h('b', null, 'Sinnvoll: '), 'Physiotherapie oder Kiefer-Abklärung (Zahnarzt, CMD), Entspannungsübungen im Kopf-Bereich. Bimodale Verfahren wie die Michigan-Studie (Jones 2023) haben genau diese Gruppe untersucht; ob die Modulierbarkeit das Ansprechen vorhersagt, ist aber noch nicht belegt.'))
        : callout('Das ist bei etwa einem Drittel der Betroffenen so und ändert nichts an den anderen Therapien.'),
      btn('Weiter: RI-Labor', () => navigate('/ri'), { variant: 'lab', size: 'lg', block: true, iconRight: 'chevR' }));
  }

  intro();
  return () => { alive = false; };
}
