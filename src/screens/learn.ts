import { h, card, note, button } from '../ui/dom';
import { navigate } from '../main';

export function renderLearn(root: HTMLElement): void {
  root.appendChild(h('h1', null, 'Wissen'));
  root.append(
    h('p', null, button('⚙ Einstellungen & Daten', () => navigate('/settings'), 'btn secondary')),
    card('Ehrliche Einordnung',
      h('p', null, 'Chronischer, lärmbedingter Tinnitus ist nach heutigem Wissen Folge einer Umorganisation im Hörsystem: Die Haarzellen im Innenohr, die hohe Frequenzen abbilden, wurden geschädigt. Das Gehirn kompensiert den fehlenden Input mit erhöhter Spontanaktivität und Synchronisation genau in diesem Frequenzbereich, und das hören wir als Ton.'),
      h('p', null, h('b', null, 'Eine Heilung im Sinne von „weg für immer“ gibt es derzeit für niemanden.'), ' Was es gibt: Verfahren, die die Lautheit bei einem Teil der Betroffenen messbar senken, und Verfahren, die die Belastung deutlich reduzieren, auch wenn der Ton bleibt. Beides ist in dieser App kombiniert.'),
      h('p', null, 'Diese App ist ein Werkzeug für ein strukturiertes Selbst-Experiment: Statt pauschal „irgendein Rauschen“ zu hören, misst du, welcher Klang bei dir nachweislich wirkt, und wendest genau den konsequent an. Dokumentiere ehrlich, gib jedem Verfahren mindestens 4 bis 6 Wochen, und erwarte eher schrittweise Veränderungen als einen Schalter.'),
    ),
    card('Was die Forschung sagt',
      h('ul', { class: 'list' },
        li('Residual Inhibition', 'Bei ca. 60–80 % der Betroffenen lässt sich der Tinnitus durch einen passenden Klang für Sekunden bis Minuten unterdrücken. Am wirksamsten sind Klänge nahe der Tinnitus-Frequenz, ausreichend laut und lang (Roberts et al. 2008; Fournier et al. 2018). Ob wiederholte RI langfristig wirkt, ist Gegenstand aktueller Forschung.'),
        li('Notched Music (TMNMT)', 'Musik mit einer Oktave Lücke um die Tinnitus-Frequenz reduzierte in Studien die Lautheit nach 12 Monaten moderat (Okamoto et al. 2010). Spätere Studien fanden kleinere Effekte; am besten belegt für Tinnitus unter 8 kHz und bei täglicher Anwendung über Monate.'),
        li('Acoustic CR Neuromodulation', 'Die erste Studie (Tass et al. 2012) war vielversprechend, die größere Folgestudie (RESET2) zeigte keinen Unterschied zur Kontrollgruppe. Harmlos, aber die Evidenz ist schwach.'),
        li('Bimodale Stimulation', 'Klang gekoppelt mit elektrischer Stimulation von Zunge (Lenire) oder Nacken/Wange (Shore et al. 2023) zeigte in randomisierten Studien deutliche Reduktionen. Benötigt spezielle Geräte; der experimentelle Modus hier ist nur eine grobe Annäherung.'),
        li('Hörgeräte', 'Bei nachgewiesenem Hochton-Hörverlust reduziert Verstärkung den Tinnitus bei vielen Betroffenen spürbar, weil der fehlende Input ersetzt wird. Nach 20 Jahren Konzert-Tinnitus lohnt sich ein aktuelles Audiogramm beim HNO unbedingt.'),
        li('Kognitive Verhaltenstherapie', 'Am besten belegt für die Reduktion der Belastung. Senkt zwar nicht die Lautheit, aber oft das Leiden, und das ist für die Lebensqualität am Ende der wichtigste Faktor.'),
        li('Klanganreicherung / TRT', 'Dauerhafter leiser Hintergrundklang reduziert den Kontrast zur Stille und unterstützt Habituation. Besonders hilfreich beim Einschlafen.'),
      ),
    ),
    card('Dein 8-Wochen-Protokoll',
      h('ol', { class: 'steps' },
        h('li', null, h('b', null, 'Woche 1:'), ' Matching an 3 verschiedenen Tagen, Hörprofil, alle 5 RI-Stimuli je 2× testen. Tagebuch täglich.'),
        h('li', null, h('b', null, 'Woche 2–5:'), ' Täglich 2× Reset-Sitzung mit dem besten RI-Klang (je 10–15 min) plus 60 min Notched Sound (Musik oder Rauschen) z. B. beim Arbeiten. Klanganreicherung nachts.'),
        h('li', null, h('b', null, 'Woche 6:'), ' Auswertung: Lautheits-Trend, Wochen-Check-Scores, Sofort-Effekte je Modus. Was wirkt, wird verstärkt, was nicht wirkt, fliegt raus.'),
        h('li', null, h('b', null, 'Woche 7–8:'), ' Erneutes Matching (hat sich die Frequenz verschoben?), RI-Labor wiederholen, Protokoll anpassen.'),
      ),
    ),
    card('Gehörschutz ab jetzt',
      h('p', null, 'Jeder weitere Lärmschaden kann den Tinnitus lauter machen. Bei Konzerten gefilterte Gehörschutzstöpsel (−15 bis −20 dB, linear), bei lauten Arbeiten Kapselgehörschutz. Kopfhörer-Lautstärke: wenn du dich nicht mehr normal unterhalten kannst, ist es zu laut.'),
      note('Auch in dieser App gilt: Alle Pegel so leise wie möglich. Kein Verfahren wird wirksamer, wenn es lauter ist, aber jedes kann bei zu hohem Pegel schaden.', 'warn'),
    ),
    card('Warnzeichen für den HNO',
      h('p', null, 'Plötzliche Veränderung des Tinnitus, einseitig neu, pulsierend im Takt des Herzschlags, Schwindel, plötzlicher Hörverlust oder Ohrdruck: zeitnah ärztlich abklären lassen.'),
    ),
  );
}

function li(title: string, text: string): HTMLElement {
  return h('li', { style: 'flex-direction:column; align-items:flex-start; gap:2px' }, h('b', null, title), h('span', { class: 'muted', style: 'line-height:1.45' }, text));
}
