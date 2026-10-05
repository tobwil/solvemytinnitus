export interface GuidedStep { text: string; s: number; breath?: 'in' | 'out' | 'hold' }

export interface Tool {
  id: string;
  title: string;
  sub: string;
  icon: string;
  minutes: number;
  steps?: GuidedStep[];
}

export interface Lesson {
  id: string;
  n: number;
  title: string;
  sub: string;
  minutes: number;
  body: string; // tiny markup: paragraphs separated by blank lines, "- " bullets, **bold**
  tool?: string;
  reflect?: string[];
}

function breathSteps(cycles: number, inS = 4, outS = 6): GuidedStep[] {
  const out: GuidedStep[] = [{ text: 'Setz dich bequem hin. Atme ganz normal, ohne etwas zu verändern.', s: 8 }];
  for (let i = 0; i < cycles; i++) {
    out.push({ text: 'Einatmen durch die Nase', s: inS, breath: 'in' });
    out.push({ text: 'Langsam ausatmen', s: outS, breath: 'out' });
  }
  out.push({ text: 'Lass den Atem wieder frei fließen. Spür kurz nach, wie sich dein Körper jetzt anfühlt.', s: 12 });
  return out;
}

export const TOOLS: Tool[] = [
  { id: 'breath', title: 'Ruhiger Atem', sub: '6 Atemzüge pro Minute, 3 min', icon: 'wind', minutes: 3, steps: breathSteps(18) },
  {
    id: 'attention', title: 'Scheinwerfer', sub: 'Aufmerksamkeit bewusst lenken, 5 min', icon: 'target', minutes: 5,
    steps: [
      { text: 'Setz dich bequem hin und schließ die Augen, wenn das für dich angenehm ist.', s: 15 },
      { text: 'Stell dir deine Aufmerksamkeit als Scheinwerfer vor. Du bestimmst, wohin er leuchtet.', s: 15 },
      { text: 'Richte den Scheinwerfer auf das lauteste Geräusch um dich herum. Nur hinhören, nicht bewerten.', s: 40 },
      { text: 'Such jetzt ein leises Geräusch. Vielleicht ein Summen, Wind, deinen eigenen Atem.', s: 40 },
      { text: 'Wandere mit dem Scheinwerfer in deinen Körper: Spüre deine Füße auf dem Boden, das Gewicht auf dem Stuhl.', s: 40 },
      { text: 'Richte den Scheinwerfer jetzt bewusst auf deinen Tinnitus. Beschreibe ihn nur: Wie hoch? Wo genau? Gleichmäßig oder pulsierend?', s: 40 },
      { text: 'Lass ihn los und kehre zu einem Umgebungsgeräusch zurück. Merke: Du hast den Scheinwerfer bewegt, nicht der Tinnitus.', s: 40 },
      { text: 'Wechsle jetzt frei zwischen Körper, Umgebung und Tinnitus. Ein paar Sekunden hier, ein paar dort.', s: 60 },
      { text: 'Komm langsam zurück. Öffne die Augen.', s: 12 },
    ],
  },
  {
    id: 'mindful', title: 'Achtsam hören', sub: 'Zulassen statt bekämpfen, 5 min', icon: 'ear', minutes: 5,
    steps: [
      { text: 'Setz dich aufrecht und entspannt hin. Atme ein paar Mal etwas tiefer aus.', s: 20 },
      { text: 'Lenke deine Aufmerksamkeit zu deinem Tinnitus. Nicht, um ihn wegzumachen, sondern um ihn neugierig kennenzulernen.', s: 30 },
      { text: 'Wie klingt er genau? Ein Ton, mehrere, ein Rauschen? Ist er links, rechts, im Kopf?', s: 40 },
      { text: 'Bemerke Gedanken wie „der ist ja wieder laut“. Benenne sie still: „Ein Gedanke.“ Und lass ihn weiterziehen wie eine Wolke.', s: 45 },
      { text: 'Bemerke Gefühle im Körper, vielleicht Anspannung im Kiefer oder in den Schultern. Atme in diese Stelle hinein.', s: 45 },
      { text: 'Gib dem Tinnitus innerlich Platz: „Du darfst da sein.“ Du musst ihn nicht mögen, nur nicht bekämpfen.', s: 45 },
      { text: 'Erweitere jetzt die Aufmerksamkeit: der Tinnitus, dazu der Raum, dein Atem, alle Geräusche gleichzeitig.', s: 45 },
      { text: 'Zum Abschluss: Drei tiefe Atemzüge. Dann öffne langsam die Augen.', s: 20 },
    ],
  },
  {
    id: 'pmr', title: 'Muskeln lösen', sub: 'Progressive Muskelentspannung, 7 min', icon: 'hand', minutes: 7,
    steps: [
      { text: 'Setz oder leg dich bequem hin. Du spannst gleich Muskelgruppen kurz an, etwa mit halber Kraft, und lässt dann bewusst los.', s: 15 },
      ...([
        ['Hände und Unterarme: Fäuste machen.', 'Hände öffnen, Wärme und Schwere spüren.'],
        ['Oberarme: Ellbogen anwinkeln und an den Körper drücken.', 'Arme sinken lassen.'],
        ['Stirn: Augenbrauen hochziehen.', 'Stirn glätten.'],
        ['Kiefer: Zähne aufeinander, Mundwinkel nach hinten.', 'Kiefer locker, Zähne leicht auseinander, Zunge ruht.'],
        ['Nacken und Schultern: Schultern Richtung Ohren ziehen.', 'Schultern fallen lassen.'],
        ['Bauch: Bauchmuskeln anspannen.', 'Bauch weich werden lassen, ruhig atmen.'],
        ['Beine und Füße: Zehen anziehen, Beine strecken.', 'Beine schwer werden lassen.'],
      ] as const).flatMap(([t, r]) => [{ text: `Anspannen · ${t}`, s: 7 }, { text: `Loslassen · ${r}`, s: 30 }]),
      { text: 'Spür noch einmal durch den ganzen Körper. Wo ist es jetzt ruhiger als vorher?', s: 20 },
    ],
  },
  { id: 'thoughts', title: 'Gedanken-Check', sub: 'Belastende Gedanken prüfen', icon: 'pen', minutes: 5 },
  { id: 'plan', title: 'Notfallplan', sub: 'Für Tage, an denen er laut ist', icon: 'shield', minutes: 5 },
];

export const LESSONS: Lesson[] = [
  {
    id: 'l1', n: 1, title: 'Warum der Ton bleibt', sub: 'Der Teufelskreis aus Aufmerksamkeit und Stress', minutes: 6,
    body: `Nach einem Lärmtrauma fehlen dem Gehirn Signale aus dem geschädigten Hochtonbereich des Innenohrs. Es dreht die Verstärkung in diesem Bereich hoch, ähnlich wie ein Radio, das bei schlechtem Empfang lauter rauscht. Das Ergebnis hörst du als Ton.

Ob dieser Ton dich belastet, entscheidet aber nicht das Ohr, sondern das Gehirn. Unser Hörsystem filtert ständig unwichtige Geräusche heraus: den Kühlschrank, die Lüftung, das eigene Blut. Ein Geräusch kommt nur durch diesen Filter, wenn es als **bedeutsam oder bedrohlich** markiert ist.

Genau das passiert bei Tinnitus oft: Er taucht auf, wird als Gefahr bewertet („Was ist kaputt? Wird das schlimmer?“), Stress und Aufmerksamkeit steigen, und dadurch wird er noch deutlicher wahrgenommen. Ein Teufelskreis:

- Tinnitus wird bemerkt
- Gedanke: „Das ist schlimm, das hört nie auf“
- Gefühl: Angst, Ärger, Hilflosigkeit
- Körper: Anspannung, schlechter Schlaf
- Folge: mehr Aufmerksamkeit, der Ton wirkt lauter

**Die gute Nachricht:** An jeder Stelle dieses Kreises kannst du ansetzen. Das ist der Kern der kognitiven Verhaltenstherapie, und sie ist das am besten belegte Verfahren gegen Tinnitus-Belastung. In den nächsten Lektionen lernst du für jede Stelle ein Werkzeug.

Das Ziel ist **Habituation**: Dein Gehirn soll den Tinnitus wieder wie den Kühlschrank behandeln. Er darf da sein, aber er ist nicht mehr wichtig.`,
    reflect: ['In welchen Situationen bemerkst du deinen Tinnitus am stärksten?', 'Welcher Gedanke kommt dann meistens als Erstes?', 'Was tust du danach? Zum Beispiel Stille meiden, nachhorchen, grübeln?'],
  },
  {
    id: 'l2', n: 2, title: 'Atmung als Bremse', sub: 'Das Stresssystem gezielt herunterfahren', minutes: 5, tool: 'breath',
    body: `Stress macht Tinnitus nicht nur gefühlt lauter. Das Stresssystem und die Hörbahn sind eng verschaltet, und unter Anspannung wird der Filter für „wichtige“ Geräusche empfindlicher.

Langsames Atmen mit verlängerter Ausatmung ist die direkteste Bremse, die du hast. Bei etwa sechs Atemzügen pro Minute aktiviert sich der Parasympathikus, der Puls beruhigt sich, die Muskelspannung sinkt.

**So geht's:** 4 Sekunden durch die Nase einatmen, 6 Sekunden langsam ausatmen. Nicht pressen, nicht besonders tief, nur langsam.

Übe das am Anfang zweimal täglich drei Minuten, wenn es dir gut geht. Dann funktioniert es auch in Momenten, in denen der Tinnitus dich stresst.`,
  },
  {
    id: 'l3', n: 3, title: 'Der Scheinwerfer', sub: 'Aufmerksamkeit bewusst lenken', minutes: 6, tool: 'attention',
    body: `Aufmerksamkeit funktioniert wie ein Scheinwerfer: Was im Licht steht, wird deutlich; alles andere tritt zurück. Bei Tinnitus hat sich der Scheinwerfer oft auf den Ton „festgefressen“.

Das Gute ist: Aufmerksamkeit lässt sich trainieren. In der Übung lenkst du den Scheinwerfer bewusst zwischen Umgebungsgeräuschen, deinem Körper und dem Tinnitus hin und her. Dabei machst du eine wichtige Erfahrung: **Du** bewegst den Scheinwerfer, nicht der Tinnitus.

Es geht ausdrücklich nicht darum, den Tinnitus zu ignorieren oder wegzudrücken. Das klappt nicht und macht ihn eher stärker. Es geht um Flexibilität.

**Im Alltag:** Wenn du merkst, dass du nachhorchst, such dir bewusst ein anderes Geräusch oder eine Tätigkeit, die deine Sinne beschäftigt.`,
  },
  {
    id: 'l4', n: 4, title: 'Gedanken prüfen', sub: 'Was du denkst, bestimmt, wie es sich anfühlt', minutes: 7, tool: 'thoughts',
    body: `Zwei Menschen mit dem gleichen Tinnitus können völlig unterschiedlich belastet sein. Der Unterschied liegt oft in den Gedanken über den Tinnitus.

Typische belastende Gedanken sind:

- „Das wird immer schlimmer.“
- „Ich werde nie wieder Ruhe haben.“
- „Wegen des Tinnitus kann ich nicht schlafen, mich nicht konzentrieren, nichts genießen.“
- „Da muss etwas Ernstes dahinterstecken.“

Solche Gedanken laufen automatisch ab und fühlen sich wahr an. Sie sind aber Bewertungen, keine Tatsachen. Und sie lassen sich prüfen:

- Welche Belege sprechen dafür, welche dagegen?
- Was würde ich einem guten Freund in derselben Lage sagen?
- Wie war es an einem guten Tag?
- Was ist das Schlimmste, das Beste und das Realistischste, was passieren kann?

Mit dem Gedanken-Check übst du genau das: Situation, Gedanke, Gefühl aufschreiben und eine ausgewogenere Sichtweise finden. Ziel ist nicht positives Denken, sondern **realistisches** Denken.`,
  },
  {
    id: 'l5', n: 5, title: 'Muskeln lösen', sub: 'Körperliche Anspannung als Verstärker', minutes: 8, tool: 'pmr',
    body: `Bei vielen Betroffenen hängen Kiefer- und Nackenmuskulatur direkt mit dem Tinnitus zusammen. Dein Somatik-Check zeigt, ob das bei dir der Fall ist. Aber auch ohne direkte Verbindung verstärkt Daueranspannung Stress und damit die Wahrnehmung.

Die Progressive Muskelentspannung nach Jacobson ist eines der am besten untersuchten Entspannungsverfahren. Das Prinzip: Muskeln kurz anspannen und dann bewusst loslassen. Durch den Kontrast lernt der Körper, wie sich echte Entspannung anfühlt.

**Besonders wichtig bei Tinnitus:** Kiefer und Nacken. Prüfe tagsüber immer wieder: Liegen die Zähne aufeinander? Sind die Schultern hochgezogen? Viele pressen unbemerkt, besonders bei Konzentration oder nachts.`,
  },
  {
    id: 'l6', n: 6, title: 'Zulassen statt kämpfen', sub: 'Akzeptanz und Achtsamkeit', minutes: 6, tool: 'mindful',
    body: `Je mehr wir gegen etwas ankämpfen, das wir nicht abstellen können, desto mehr Raum nimmt es ein. Das ist die zentrale Einsicht der Akzeptanz- und Commitment-Therapie und achtsamkeitsbasierter Ansätze, die bei Tinnitus-Belastung ebenfalls wirksam sind.

Akzeptanz heißt nicht aufgeben oder den Tinnitus gut finden. Sie heißt: aufhören, Energie in einen Kampf zu stecken, der nicht zu gewinnen ist, und diese Energie in das zu stecken, was dir wichtig ist.

In der Übung „Achtsam hören“ begegnest du dem Tinnitus mit Neugier statt Abwehr. Du beobachtest Klang, Gedanken und Körpergefühle, ohne sie zu bewerten. Viele erleben dabei zum ersten Mal, dass der Tinnitus „einfach ein Geräusch“ sein kann.

**Frage für diese Woche:** Was würdest du tun, wenn der Tinnitus dich nicht mehr aufhalten würde? Fang mit einem kleinen Schritt davon an.`,
  },
  {
    id: 'l7', n: 7, title: 'Besser schlafen', sub: 'Regeln aus der Schlaf-Verhaltenstherapie', minutes: 7,
    body: `Schlechter Schlaf und Tinnitus verstärken sich gegenseitig. Studien mit vielen Messungen im Alltag zeigen, dass Tinnitus nachts und frühmorgens im Schnitt lauter und belastender erlebt wird. Das liegt auch an der Stille und an der Müdigkeit.

Die wirksamsten Regeln aus der kognitiven Verhaltenstherapie für Schlaf (CBT-I):

- **Feste Aufstehzeit**, auch am Wochenende. Das ist wichtiger als die Zubettgehzeit.
- **Bett nur zum Schlafen.** Kein Handy, keine Serien, kein Grübeln im Bett.
- **20-Minuten-Regel:** Kannst du nicht einschlafen, steh auf, geh in einen anderen Raum, mach etwas Ruhiges bei gedimmtem Licht, und komm erst müde zurück.
- **Keine Uhr anschauen** in der Nacht.
- **Klanganreicherung:** Ein leiser Klang im Schlafzimmer nimmt der Stille den Kontrast. Nutze dafür die Klanganreicherung mit Timer.
- Koffein nach 14 Uhr und Alkohol am Abend vermeiden.

Gib den Regeln zwei bis drei Wochen. Am Anfang kann der Schlaf sogar etwas schlechter werden, bevor er besser wird.`,
    reflect: ['Wann stehst du ab jetzt jeden Tag auf?', 'Was tust du, wenn du nach 20 Minuten noch wach bist?'],
  },
  {
    id: 'l8', n: 8, title: 'Rückschläge meistern', sub: 'Laute Tage gehören dazu', minutes: 6, tool: 'plan',
    body: `Tinnitus schwankt. Nach Lärm, Stress, einer Erkältung, wenig Schlaf oder manchmal ganz ohne erkennbaren Grund wird er lauter. Das ist normal und bedeutet nicht, dass alles umsonst war. Fast immer pendelt er sich in Stunden bis Tagen wieder ein.

Gefährlich ist nicht der laute Tag, sondern die Bewertung: „Jetzt geht alles von vorne los.“ Genau dieser Gedanke startet den Teufelskreis neu.

Darum lohnt sich ein **Notfallplan**, den du an einem guten Tag schreibst:

- Was hilft mir kurzfristig? Zum Beispiel Klanganreicherung, Atemübung, rausgehen.
- Welcher Satz hilft mir? Zum Beispiel „Das war schon öfter so und ist wieder vorbeigegangen.“
- Wen kann ich anrufen?
- Was lasse ich bleiben? Zum Beispiel stundenlang nachhorchen, im Internet nach Horrorgeschichten suchen.

**Gehörschutz bleibt Pflicht:** Gefilterte Ohrstöpsel bei Konzerten und in lauten Umgebungen, aber nicht in normaler Umgebung, sonst wird das Gehör empfindlicher.

**Ärztlich abklären lassen:** plötzliche deutliche Veränderung, pulsierender Tinnitus, Hörsturz, Schwindel.`,
  },
];
