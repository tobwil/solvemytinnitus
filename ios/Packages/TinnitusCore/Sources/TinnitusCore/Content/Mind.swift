import Foundation

public struct GuidedStep: Sendable, Hashable {
    public enum Breath: Sendable, Hashable { case inhale, exhale, hold }
    public var text: String
    public var seconds: Double
    public var breath: Breath?
    public init(_ text: String, _ seconds: Double, breath: Breath? = nil) {
        self.text = text
        self.seconds = seconds
        self.breath = breath
    }
}

public struct MindTool: Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var sub: String
    public var symbol: String
    public var minutes: Int
    public var steps: [GuidedStep]?
}

public struct Lesson: Sendable, Identifiable, Hashable {
    public var id: String
    public var n: Int
    public var title: String
    public var sub: String
    public var minutes: Int
    /// Tiny markup: blank-line paragraphs, "- " bullets, **bold**.
    public var body: String
    public var tool: String?
    public var reflect: [String]
    /// Body program the lesson links to (lesson 5 → jaw program).
    public var bodyProgram: BodyProgramID?
}

public enum MindContent {
    public static func breathSteps(cycles: Int, inhale: Double = 4, exhale: Double = 6) -> [GuidedStep] {
        var out = [GuidedStep("Setz dich bequem hin. Atme ganz normal, ohne etwas zu verändern.", 8)]
        for _ in 0..<cycles {
            out.append(GuidedStep("Einatmen durch die Nase", inhale, breath: .inhale))
            out.append(GuidedStep("Langsam ausatmen", exhale, breath: .exhale))
        }
        out.append(GuidedStep("Lass den Atem wieder frei fließen. Spür kurz nach, wie sich dein Körper jetzt anfühlt.", 12))
        return out
    }

    /// Breath exercise with 1/3/5 minutes (watch and quick access).
    public static func breath(minutes: Int) -> [GuidedStep] {
        breathSteps(cycles: max(1, minutes * 6 - 2))
    }

    public static let tools: [MindTool] = [
        MindTool(id: "breath", title: "Ruhiger Atem", sub: "6 Atemzüge pro Minute, 3 min", symbol: "wind", minutes: 3, steps: breathSteps(cycles: 18)),
        MindTool(id: "attention", title: "Scheinwerfer", sub: "Aufmerksamkeit bewusst lenken, 5 min", symbol: "scope", minutes: 5, steps: [
            GuidedStep("Setz dich bequem hin und schließ die Augen, wenn das für dich angenehm ist.", 15),
            GuidedStep("Stell dir deine Aufmerksamkeit als Scheinwerfer vor. Du bestimmst, wohin er leuchtet.", 15),
            GuidedStep("Richte den Scheinwerfer auf das lauteste Geräusch um dich herum. Nur hinhören, nicht bewerten.", 40),
            GuidedStep("Such jetzt ein leises Geräusch. Vielleicht ein Summen, Wind, deinen eigenen Atem.", 40),
            GuidedStep("Wandere mit dem Scheinwerfer in deinen Körper: Spüre deine Füße auf dem Boden, das Gewicht auf dem Stuhl.", 40),
            GuidedStep("Richte den Scheinwerfer jetzt bewusst auf deinen Tinnitus. Beschreibe ihn nur: Wie hoch? Wo genau? Gleichmäßig oder pulsierend?", 40),
            GuidedStep("Lass ihn los und kehre zu einem Umgebungsgeräusch zurück. Merke: Du hast den Scheinwerfer bewegt, nicht der Tinnitus.", 40),
            GuidedStep("Wechsle jetzt frei zwischen Körper, Umgebung und Tinnitus. Ein paar Sekunden hier, ein paar dort.", 60),
            GuidedStep("Komm langsam zurück. Öffne die Augen.", 12),
        ]),
        MindTool(id: "mindful", title: "Achtsam hören", sub: "Zulassen statt bekämpfen, 5 min", symbol: "ear", minutes: 5, steps: [
            GuidedStep("Setz dich aufrecht und entspannt hin. Atme ein paar Mal etwas tiefer aus.", 20),
            GuidedStep("Lenke deine Aufmerksamkeit zu deinem Tinnitus. Nicht, um ihn wegzumachen, sondern um ihn neugierig kennenzulernen.", 30),
            GuidedStep("Wie klingt er genau? Ein Ton, mehrere, ein Rauschen? Ist er links, rechts, im Kopf?", 40),
            GuidedStep("Bemerke Gedanken wie „der ist ja wieder laut“. Benenne sie still: „Ein Gedanke.“ Und lass ihn weiterziehen wie eine Wolke.", 45),
            GuidedStep("Bemerke Gefühle im Körper, vielleicht Anspannung im Kiefer oder in den Schultern. Atme in diese Stelle hinein.", 45),
            GuidedStep("Gib dem Tinnitus innerlich Platz: „Du darfst da sein.“ Du musst ihn nicht mögen, nur nicht bekämpfen.", 45),
            GuidedStep("Erweitere jetzt die Aufmerksamkeit: der Tinnitus, dazu der Raum, dein Atem, alle Geräusche gleichzeitig.", 45),
            GuidedStep("Zum Abschluss: Drei tiefe Atemzüge. Dann öffne langsam die Augen.", 20),
        ]),
        MindTool(id: "pmr", title: "Muskeln lösen", sub: "Progressive Muskelentspannung, 7 min", symbol: "hand.raised", minutes: 7, steps: pmrSteps),
        MindTool(id: "thoughts", title: "Gedanken-Check", sub: "Belastende Gedanken prüfen", symbol: "pencil.line", minutes: 5, steps: nil),
        MindTool(id: "plan", title: "Notfallplan", sub: "Für Tage, an denen er laut ist", symbol: "shield", minutes: 5, steps: nil),
    ]

    private static let pmrSteps: [GuidedStep] = {
        var s = [GuidedStep("Setz oder leg dich bequem hin. Du spannst gleich Muskelgruppen kurz an, etwa mit halber Kraft, und lässt dann bewusst los.", 15)]
        let pairs: [(String, String)] = [
            ("Hände und Unterarme: Fäuste machen.", "Hände öffnen, Wärme und Schwere spüren."),
            ("Oberarme: Ellbogen anwinkeln und an den Körper drücken.", "Arme sinken lassen."),
            ("Stirn: Augenbrauen hochziehen.", "Stirn glätten."),
            ("Kiefer: Zähne aufeinander, Mundwinkel nach hinten.", "Kiefer locker, Zähne leicht auseinander, Zunge ruht."),
            ("Nacken und Schultern: Schultern Richtung Ohren ziehen.", "Schultern fallen lassen."),
            ("Bauch: Bauchmuskeln anspannen.", "Bauch weich werden lassen, ruhig atmen."),
            ("Beine und Füße: Zehen anziehen, Beine strecken.", "Beine schwer werden lassen."),
        ]
        for (t, r) in pairs {
            s.append(GuidedStep("Anspannen · \(t)", 7))
            s.append(GuidedStep("Loslassen · \(r)", 30))
        }
        s.append(GuidedStep("Spür noch einmal durch den ganzen Körper. Wo ist es jetzt ruhiger als vorher?", 20))
        return s
    }()

    public static func tool(_ id: String) -> MindTool? { tools.first { $0.id == id } }

    public static let spikePlanTemplate = """
    Was mir kurzfristig hilft:
    -

    Ein Satz, der mir hilft:
    - „Das war schon öfter so und ist wieder vorbeigegangen.“

    Wen ich anrufen kann:
    -

    Was ich an solchen Tagen bleiben lasse:
    -
    """

    public static let thoughtPrompts = [
        "Welche Belege sprechen dafür, welche dagegen?",
        "Was würde ich einem guten Freund sagen?",
        "Wie ist es an einem guten Tag?",
        "Was ist realistisch, nicht das Schlimmste?",
    ]

    public static let lessons: [Lesson] = [
        Lesson(id: "l1", n: 1, title: "Warum der Ton bleibt", sub: "Der Teufelskreis aus Aufmerksamkeit und Stress", minutes: 6, body: """
        Nach einem Lärmtrauma fehlen dem Gehirn Signale aus dem geschädigten Hochtonbereich des Innenohrs. Es dreht die Verstärkung in diesem Bereich hoch, ähnlich wie ein Radio, das bei schlechtem Empfang lauter rauscht. Das Ergebnis hörst du als Ton.

        Ob dieser Ton dich belastet, entscheidet aber nicht das Ohr, sondern das Gehirn. Unser Hörsystem filtert ständig unwichtige Geräusche heraus: den Kühlschrank, die Lüftung, das eigene Blut. Ein Geräusch kommt nur durch diesen Filter, wenn es als **bedeutsam oder bedrohlich** markiert ist.

        Genau das passiert bei Tinnitus oft: Er taucht auf, wird als Gefahr bewertet („Was ist kaputt? Wird das schlimmer?“), Stress und Aufmerksamkeit steigen, und dadurch wird er noch deutlicher wahrgenommen. Ein Teufelskreis:

        - Tinnitus wird bemerkt
        - Gedanke: „Das ist schlimm, das hört nie auf“
        - Gefühl: Angst, Ärger, Hilflosigkeit
        - Körper: Anspannung, schlechter Schlaf
        - Folge: mehr Aufmerksamkeit, der Ton wirkt lauter

        **Die gute Nachricht:** An jeder Stelle dieses Kreises kannst du ansetzen. Das ist der Kern der kognitiven Verhaltenstherapie, und sie ist das am besten belegte Verfahren gegen Tinnitus-Belastung. In den nächsten Lektionen lernst du für jede Stelle ein Werkzeug.

        Das Ziel ist **Habituation**: Dein Gehirn soll den Tinnitus wieder wie den Kühlschrank behandeln. Er darf da sein, aber er ist nicht mehr wichtig.
        """, tool: nil, reflect: [
            "In welchen Situationen bemerkst du deinen Tinnitus am stärksten?",
            "Welcher Gedanke kommt dann meistens als Erstes?",
            "Was tust du danach? Zum Beispiel Stille meiden, nachhorchen, grübeln?",
        ]),
        Lesson(id: "l2", n: 2, title: "Atmung als Bremse", sub: "Das Stresssystem gezielt herunterfahren", minutes: 5, body: """
        Stress macht Tinnitus nicht nur gefühlt lauter. Das Stresssystem und die Hörbahn sind eng verschaltet, und unter Anspannung wird der Filter für „wichtige“ Geräusche empfindlicher.

        Langsames Atmen mit verlängerter Ausatmung ist die direkteste Bremse, die du hast. Bei etwa sechs Atemzügen pro Minute aktiviert sich der Parasympathikus, der Puls beruhigt sich, die Muskelspannung sinkt.

        **So geht's:** 4 Sekunden durch die Nase einatmen, 6 Sekunden langsam ausatmen. Nicht pressen, nicht besonders tief, nur langsam.

        Übe das am Anfang zweimal täglich drei Minuten, wenn es dir gut geht. Dann funktioniert es auch in Momenten, in denen der Tinnitus dich stresst.
        """, tool: "breath", reflect: []),
        Lesson(id: "l3", n: 3, title: "Der Scheinwerfer", sub: "Aufmerksamkeit bewusst lenken", minutes: 6, body: """
        Aufmerksamkeit funktioniert wie ein Scheinwerfer: Was im Licht steht, wird deutlich; alles andere tritt zurück. Bei Tinnitus hat sich der Scheinwerfer oft auf den Ton „festgefressen“.

        Das Gute ist: Aufmerksamkeit lässt sich trainieren. In der Übung lenkst du den Scheinwerfer bewusst zwischen Umgebungsgeräuschen, deinem Körper und dem Tinnitus hin und her. Dabei machst du eine wichtige Erfahrung: **Du** bewegst den Scheinwerfer, nicht der Tinnitus.

        Es geht ausdrücklich nicht darum, den Tinnitus zu ignorieren oder wegzudrücken. Das klappt nicht und macht ihn eher stärker. Es geht um Flexibilität.

        **Im Alltag:** Wenn du merkst, dass du nachhorchst, such dir bewusst ein anderes Geräusch oder eine Tätigkeit, die deine Sinne beschäftigt.
        """, tool: "attention", reflect: []),
        Lesson(id: "l4", n: 4, title: "Gedanken prüfen", sub: "Was du denkst, bestimmt, wie es sich anfühlt", minutes: 7, body: """
        Zwei Menschen mit dem gleichen Tinnitus können völlig unterschiedlich belastet sein. Der Unterschied liegt oft in den Gedanken über den Tinnitus.

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

        Mit dem Gedanken-Check übst du genau das: Situation, Gedanke, Gefühl aufschreiben und eine ausgewogenere Sichtweise finden. Ziel ist nicht positives Denken, sondern **realistisches** Denken.
        """, tool: "thoughts", reflect: []),
        Lesson(id: "l5", n: 5, title: "Muskeln lösen", sub: "Körperliche Anspannung als Verstärker", minutes: 8, body: """
        Bei vielen Betroffenen hängen Kiefer- und Nackenmuskulatur direkt mit dem Tinnitus zusammen. Dein Somatik-Check zeigt, ob das bei dir der Fall ist. Aber auch ohne direkte Verbindung verstärkt Daueranspannung Stress und damit die Wahrnehmung.

        Die Progressive Muskelentspannung nach Jacobson ist eines der am besten untersuchten Entspannungsverfahren. Das Prinzip: Muskeln kurz anspannen und dann bewusst loslassen. Durch den Kontrast lernt der Körper, wie sich echte Entspannung anfühlt.

        **Besonders wichtig bei Tinnitus:** Kiefer und Nacken. Prüfe tagsüber immer wieder: Liegen die Zähne aufeinander? Sind die Schultern hochgezogen? Viele pressen unbemerkt, besonders bei Konzentration oder nachts.

        Für den Kiefer gibt es im Bereich **Körper** ein eigenes Programm mit Ruheposition, geführter Öffnung und Selbstmassage.
        """, tool: "pmr", reflect: [], bodyProgram: .jaw),
        Lesson(id: "l6", n: 6, title: "Zulassen statt kämpfen", sub: "Akzeptanz und Achtsamkeit", minutes: 6, body: """
        Je mehr wir gegen etwas ankämpfen, das wir nicht abstellen können, desto mehr Raum nimmt es ein. Das ist die zentrale Einsicht der Akzeptanz- und Commitment-Therapie und achtsamkeitsbasierter Ansätze, die bei Tinnitus-Belastung ebenfalls wirksam sind.

        Akzeptanz heißt nicht aufgeben oder den Tinnitus gut finden. Sie heißt: aufhören, Energie in einen Kampf zu stecken, der nicht zu gewinnen ist, und diese Energie in das zu stecken, was dir wichtig ist.

        In der Übung „Achtsam hören“ begegnest du dem Tinnitus mit Neugier statt Abwehr. Du beobachtest Klang, Gedanken und Körpergefühle, ohne sie zu bewerten. Viele erleben dabei zum ersten Mal, dass der Tinnitus „einfach ein Geräusch“ sein kann.

        **Frage für diese Woche:** Was würdest du tun, wenn der Tinnitus dich nicht mehr aufhalten würde? Fang mit einem kleinen Schritt davon an.
        """, tool: "mindful", reflect: []),
        Lesson(id: "l7", n: 7, title: "Besser schlafen", sub: "Regeln aus der Schlaf-Verhaltenstherapie", minutes: 7, body: """
        Schlechter Schlaf und Tinnitus verstärken sich gegenseitig. Studien mit vielen Messungen im Alltag zeigen, dass Tinnitus nachts und frühmorgens im Schnitt lauter und belastender erlebt wird. Das liegt auch an der Stille und an der Müdigkeit.

        Die wirksamsten Regeln aus der kognitiven Verhaltenstherapie für Schlaf (CBT-I):

        - **Feste Aufstehzeit**, auch am Wochenende. Das ist wichtiger als die Zubettgehzeit.
        - **Bett nur zum Schlafen.** Kein Handy, keine Serien, kein Grübeln im Bett.
        - **20-Minuten-Regel:** Kannst du nicht einschlafen, steh auf, geh in einen anderen Raum, mach etwas Ruhiges bei gedimmtem Licht, und komm erst müde zurück.
        - **Keine Uhr anschauen** in der Nacht.
        - **Klanganreicherung:** Ein leiser Klang im Schlafzimmer nimmt der Stille den Kontrast. Nutze dafür die Klanganreicherung mit Sleep-Timer; sie läuft auch bei gesperrtem Bildschirm weiter.
        - Koffein nach 14 Uhr und Alkohol am Abend vermeiden.

        Gib den Regeln zwei bis drei Wochen. Am Anfang kann der Schlaf sogar etwas schlechter werden, bevor er besser wird.
        """, tool: nil, reflect: [
            "Wann stehst du ab jetzt jeden Tag auf?",
            "Was tust du, wenn du nach 20 Minuten noch wach bist?",
        ]),
        Lesson(id: "l8", n: 8, title: "Rückschläge meistern", sub: "Laute Tage gehören dazu", minutes: 6, body: """
        Tinnitus schwankt. Nach Lärm, Stress, einer Erkältung, wenig Schlaf oder manchmal ganz ohne erkennbaren Grund wird er lauter. Das ist normal und bedeutet nicht, dass alles umsonst war. Fast immer pendelt er sich in Stunden bis Tagen wieder ein.

        Gefährlich ist nicht der laute Tag, sondern die Bewertung: „Jetzt geht alles von vorne los.“ Genau dieser Gedanke startet den Teufelskreis neu.

        Darum lohnt sich ein **Notfallplan**, den du an einem guten Tag schreibst:

        - Was hilft mir kurzfristig? Zum Beispiel Klanganreicherung, Atemübung, rausgehen.
        - Welcher Satz hilft mir? Zum Beispiel „Das war schon öfter so und ist wieder vorbeigegangen.“
        - Wen kann ich anrufen?
        - Was lasse ich bleiben? Zum Beispiel stundenlang nachhorchen, im Internet nach Horrorgeschichten suchen.

        **Gehörschutz bleibt Pflicht:** Gefilterte Ohrstöpsel bei Konzerten und in lauten Umgebungen, aber nicht in normaler Umgebung, sonst wird das Gehör empfindlicher.

        **Ärztlich abklären lassen:** plötzliche deutliche Veränderung, pulsierender Tinnitus, Hörsturz, Schwindel.
        """, tool: "plan", reflect: []),
    ]

    public static func lesson(_ id: String) -> Lesson? { lessons.first { $0.id == id } }

    /// Evidence base of the lessons (shown under each lesson).
    public static let lessonRefs = "Mazurek et al. 2022, S3-Leitlinie Chronischer Tinnitus; Fuller et al. 2020, Cochrane"
}

/// Minimal parser for the lesson markup.
public enum Prose {
    public enum Block: Hashable, Sendable {
        case paragraph(String)
        case bullets([String])
    }

    public static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for raw in normalized.components(separatedBy: "\n\n") {
            let lines = raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            let para = lines.filter { !$0.hasPrefix("- ") }
            let bullets = lines.filter { $0.hasPrefix("- ") }.map { String($0.dropFirst(2)) }
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))) }
            if !bullets.isEmpty { out.append(.bullets(bullets)) }
        }
        return out
    }
}
