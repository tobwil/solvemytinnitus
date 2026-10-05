import { h, page, header, card, evidence, sectionH, callout, btn } from '../ui/dom';
import { icon } from '../ui/icons';
import { navigate } from '../router';

interface Item { title: string; level: 1 | 2 | 3 | 4; verdict: string; text: string; refs: string; inApp?: string }

const ITEMS: { group: string; items: Item[] }[] = [
  {
    group: 'Nachweislich wirksam',
    items: [
      { title: 'Kognitive Verhaltenstherapie', level: 4, verdict: 'senkt die Belastung, nicht die Lautheit',
        text: 'Am besten belegtes Verfahren. In der großen europäischen UNITI-Studie hatten CBT allein und Hörgeräte allein die größten Effekte; Kombinationen waren nur etwas besser. Internetbasierte Programme wirken ähnlich.',
        refs: 'Fuller et al. 2020, Cochrane; Schoisswohl et al. 2025, Nat Commun (UNITI, n=461); Sattel et al. 2025', inApp: 'Kopf-Training' },
      { title: 'Hörgeräte bei Hörverlust', level: 4, verdict: 'empfohlen in der deutschen S3-Leitlinie',
        text: 'Ersetzen den fehlenden Input, an dem der Tinnitus hängt. Konventionell angepasst; eine zusätzliche „Notch“ im Hörgerät brachte in Studien keinen Vorteil. Auch bei normalem Standard-Audiogramm sind die Schwellen über 10 kHz bei Tinnitus oft erhöht.',
        refs: 'Mazurek et al. 2022, S3-Leitlinie; Schiele et al. 2025, Ear Hear; Waechter et al. 2026; Jafari et al. 2022', inApp: 'Hörprofil bis 16 kHz' },
    ],
  },
  {
    group: 'Vielversprechend, noch nicht gesichert',
    items: [
      { title: 'Bimodale Neuromodulation', level: 3, verdict: 'konsistenteste Gerätedaten',
        text: 'Lenire (Klang plus Zungenstimulation) ist seit 2023 in den USA zugelassen und in Deutschland privat erhältlich. Große Verbesserungen in den Studien, aber ohne echte Placebo-Gruppe; der Vorteil gegenüber Klang allein zeigte sich nur bei mittel- bis schwergradigem Tinnitus. Das Michigan-Gerät (Klang plus Wange/Nacken) half in einer kontrollierten Studie bei somatischem Tinnitus, ist aber nicht auf dem Markt.',
        refs: 'Conlon et al. 2020/2022; Boedts et al. 2024, Nat Commun (TENT-A3); Jones et al. 2023, JAMA Netw Open; Kitsis et al. 2026, Laryngoscope', inApp: 'Somatik-Check' },
      { title: 'Personalisierte AM-Klanganreicherung', level: 2, verdict: 'eine Studie, nicht randomisiert',
        text: '10-Hz-amplitudenmoduliertes Rauschen senkte über 6 Monate die Maskierungsschwelle stärker als unmoduliertes. Wer Residual Inhibition zeigt, sprach besser auf Klanganreicherung an.',
        refs: 'Sendesen et al. 2026, Hear Res (n=71); Sendesen et al. 2024', inApp: 'Klanganreicherung · AM 10 Hz' },
      { title: 'Dekorrelierender Klang', level: 1, verdict: 'neu, sehr kleine Studie',
        text: 'Ein Klang, der die Kopplung zwischen Frequenzbereichen stört, senkte in einer verblindeten Online-Studie die Lautheit, Placebo-Klang nicht. Erste Daten, noch nicht repliziert.',
        refs: 'Yukhnovich, Sedley et al. 2025, Hear Res (n=53)' },
      { title: 'Vagusnerv-Stimulation (auch am Ohr)', level: 2, verdict: 'bescheidene Effekte',
        text: 'Gepaart mit Tönen; Meta-Analysen finden kleine Verbesserungen der Belastung, aber keinen Effekt auf die Lautheit. Neuere Studien mit Ohr-Stimulatoren ohne Gruppenunterschied.',
        refs: 'Tyler et al. 2017; Fernández-Hernando et al. 2023; Deng et al. 2026' },
    ],
  },
  {
    group: 'Kurzfristig wirksam, langfristig offen',
    items: [
      { title: 'Residual Inhibition', level: 2, verdict: 'zuverlässiger Kurzzeiteffekt',
        text: 'Schmalband-Rauschen im Bereich von Hörverlust und Tinnitus unterdrückt am häufigsten, aber sehr individuell. Dass wiederholte Unterdrückung dauerhaft wirkt, zeigt bisher keine kontrollierte Studie.',
        refs: 'Roberts et al. 2008, JARO; Neff et al. 2017/2019; Schoisswohl et al. 2025, JARO', inApp: 'RI-Labor, Reset-Sitzung' },
      { title: 'Klanganreicherung allgemein', level: 2, verdict: 'hilft vielen subjektiv',
        text: 'Nimmt der Stille den Kontrast, hilft beim Einschlafen. Als alleinige Therapie schwach belegt. Im Alltag reduzieren Umgebungsgeräusche den Tinnitus bei etwa jedem Fünften und verstärken ihn bei wenigen.',
        refs: 'Kraft et al. 2025, npj Digit Med (67 442 Messungen)', inApp: 'Klanganreicherung' },
    ],
  },
  {
    group: 'Nicht besser als Placebo',
    items: [
      { title: 'Notched Music', level: 2, verdict: 'widersprüchlich',
        text: 'Frühe Studien positiv, neuere Meta-Analysen finden keinen Vorteil gegenüber unveränderter Musik.',
        refs: 'Okamoto et al. 2010; Alfonso et al. 2024; Tavanai et al. 2024; Jiang et al. 2025', inApp: 'Notched Sound' },
      { title: 'Akustische CR-Neuromodulation', level: 1, verdict: 'große Studie negativ',
        text: 'Die doppelblinde RESET2-Studie fand keinen Unterschied zur Placebo-Stimulation.',
        refs: 'Hall et al. 2022, Brain Sci (n=100)', inApp: 'CR-Neuromodulation' },
      { title: 'Medikamente und Regeneration', level: 1, verdict: 'nichts zugelassen',
        text: 'OTO-313 und FX-322 scheiterten in Phase 2; Medikamenten-Kombinationen waren nicht besser als Placebo. Für Lärm-Tinnitus oder Synaptopathie gibt es keine zugelassene Medikamenten- oder Gentherapie. Vorsicht bei Nahrungsergänzungsmitteln mit Heilsversprechen.',
        refs: 'Searchfield et al. 2023; Abouzari et al. 2025' },
      { title: 'rTMS und tDCS', level: 1, verdict: 'gepoolt nicht signifikant',
        text: 'Hirnstimulation von außen zeigt in der Zusammenschau keine verlässliche Wirkung.',
        refs: 'Kitsis et al. 2026, Laryngoscope (26 RCTs)' },
    ],
  },
];

export function renderLearn(root: HTMLElement): void {
  root.appendChild(page(
    header('Wissen · Stand Oktober 2026', 'Was die Forschung sagt'),
    card('glow-tin',
      h('p', { class: 'title-m' }, 'Das Wichtigste in drei Sätzen'),
      h('div', { class: 'prose' },
        h('p', null, 'Eine Heilung für chronischen Lärm-Tinnitus gibt es derzeit nicht, auch kein zugelassenes Medikament.'),
        h('p', null, h('b', null, 'Am besten belegt sind kognitive Verhaltenstherapie und Hörgeräte bei Hörverlust.'), ' Sie senken die Belastung deutlich, oft mehr als jede Klangtherapie.'),
        h('p', null, 'Die meisten Klangverfahren wirken im Einzelfall, aber nicht im Durchschnitt. Darum misst diese App, was bei dir wirkt, statt es zu versprechen.'))),
    sectionH('Was du in Deutschland konkret tun kannst'),
    card(null, h('ul', { class: 'list' },
      step('ear', 'HNO-Termin mit Hochton-Audiogramm', 'Tonaudiogramm bis 16 kHz, Abklärung anderer Ursachen. Bei Hörverlust: Hörgeräte-Versorgung, die Kasse zahlt bei Indikation.'),
      step('mind', 'Kognitive Therapie auf Rezept', 'Tinnitus-Apps als DiGA (z. B. Kalmeda) kann dein Arzt kostenlos verordnen. Aktuelle Liste: diga.bfarm.de. Alternativ tinnitusspezifische Psychotherapie.'),
      step('pulse', 'Bimodale Therapie prüfen', 'Bei mittel- bis schwergradiger Belastung trotz CBT: Lenire als Selbstzahler-Option mit einem HNO besprechen. Wirkung bei leichtem Tinnitus kaum nachweisbar.'),
      step('shield', 'Gehörschutz', 'Gefilterte Ohrstöpsel bei Konzerten und Lärm. Nicht im Alltag, sonst wird das Gehör empfindlicher.'))),
    ...ITEMS.flatMap((g) => [sectionH(g.group), ...g.items.map(itemCard)]),
    sectionH('Wie diese App die Forschung nutzt'),
    card(null, h('div', { class: 'prose' },
      h('ul', null,
        h('li', null, h('b', null, 'Likeness-Spektrum statt Regler: '), 'Bei hohem Tinnitus deutlich reproduzierbarer (84 % vs. 23 % der Patienten, Hébert 2018).'),
        h('li', null, h('b', null, 'Verblindete Tests: '), 'Die Erwartung beeinflusst Tinnitus-Bewertungen stark; Medikamentenstudien scheiterten oft am Placebo-Effekt. Darum testet das RI-Labor verblindet.'),
        h('li', null, h('b', null, 'Mehrfach-Check-ins: '), 'Tinnitus schwankt im Tagesverlauf, Auslöser sind individuell (TrackYourTinnitus-Studien). Mehrere Messungen pro Tag sind aussagekräftiger als eine.'),
        h('li', null, h('b', null, 'Ehrliche Kennzeichnung: '), 'Jedes Verfahren zeigt seine Evidenz. Schwach belegte Verfahren sind enthalten, weil sie einzelnen Menschen helfen können, aber nicht als Versprechen.')))),
    callout('Warnzeichen für eine zeitnahe ärztliche Abklärung: plötzliche Veränderung, neu einseitig, pulsierend im Herzschlag, Hörsturz, Schwindel.', 'warn'),
    btn('Einstellungen & Daten', () => navigate('/settings'), { variant: 'ghost', block: true, icon: 'gear' }),
  ));
}

function step(ico: string, title: string, text: string): HTMLElement {
  return h('li', { style: 'align-items:flex-start' }, h('span', { class: 'li-ico sound' }, icon(ico)), h('div', { class: 'li-main' }, h('div', { class: 'li-title' }, title), h('div', { class: 'li-sub', style: 'line-height:1.45' }, text)));
}

function itemCard(it: Item): HTMLElement {
  return card(null,
    h('div', { class: 'row between', style: 'align-items:flex-start' }, h('p', { class: 'title-m', style: 'margin:0' }, it.title), evidence(it.level, '')),
    h('p', { class: 'small', style: 'margin:2px 0 6px;color:var(--text-2);font-weight:600' }, it.verdict),
    h('p', { class: 'body', style: 'margin:0' }, it.text),
    h('p', { class: 'ref' }, it.refs),
    it.inApp ? h('span', { class: 'chip sound mt8' }, icon('sparkle'), `In der App: ${it.inApp}`) : null);
}
