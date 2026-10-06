import Foundation

public enum Contraindication: String, Codable, Sendable, CaseIterable, Identifiable {
    case acuteNeckPain, discHerniation, dizziness, recentInjury, jawLock
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .acuteNeckPain: "Akute Nackenschmerzen"
        case .discHerniation: "Bandscheibenvorfall (Halswirbelsäule)"
        case .dizziness: "Schwindel bei Kopfbewegung"
        case .recentInjury: "Frische Verletzung an Kopf, Nacken oder Kiefer"
        case .jawLock: "Kieferblockade oder Kiefergelenk-Schmerz"
        }
    }
}

/// Target for AirPods-guided stretching. Signs: yaw left −/right +, roll left −/right +, pitch flexion +.
public struct MotionTarget: Sendable, Hashable {
    public enum Axis: String, Sendable, Hashable { case yaw, roll, pitch }
    public var axis: Axis
    /// Signed target in degrees for the first (left) side.
    public var degrees: Double
    public var holdS: Double
    public init(axis: Axis, degrees: Double, holdS: Double) {
        self.axis = axis
        self.degrees = degrees
        self.holdS = holdS
    }
}

/// Repeating phases inside an exercise ("Halten 5 s / Lösen 2 s", "Einatmen / Ausatmen").
/// The player shows the current phase and gives a haptic tick at each change.
public struct Rhythm: Sendable, Hashable {
    public struct Phase: Sendable, Hashable {
        public var label: String
        public var seconds: Double
        public init(_ label: String, _ seconds: Double) {
            self.label = label
            self.seconds = seconds
        }
    }
    public var phases: [Phase]
    public init(_ phases: [Phase]) { self.phases = phases }

    public static let breath = Rhythm([.init("Einatmen", 4), .init("Ausatmen", 6)])
    public static func hold(_ label: String, _ hold: Double, release: Double, releaseLabel: String = "Lösen") -> Rhythm {
        Rhythm([.init(label, hold), .init(releaseLabel, release)])
    }

    /// Phase index and time left in that phase at `t` seconds.
    public func phase(at t: Double) -> (index: Int, left: Double) {
        let cycle = phases.reduce(0) { $0 + $1.seconds }
        guard cycle > 0 else { return (0, 0) }
        var x = max(0, t).truncatingRemainder(dividingBy: cycle)
        for (i, p) in phases.enumerated() {
            if x < p.seconds { return (i, p.seconds - x) }
            x -= p.seconds
        }
        return (phases.count - 1, 0)
    }
}

/// One exercise as a clear, step-by-step instruction (no figure needed): a short main cue,
/// numbered steps, the most common mistake, timing and an optional rhythm.
public struct BodyExercise: Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var target: String
    /// Short main instruction shown large and spoken.
    public var cue: String
    public var steps: [String]
    public var mistake: String
    /// Duration per side in seconds.
    public var seconds: Double
    /// 2 for left/right exercises.
    public var sides: Int
    public var excludedBy: Set<Contraindication>
    public var rhythm: Rhythm?
    public var motion: MotionTarget?

    public init(id: String, title: String, target: String, cue: String, steps: [String], mistake: String, seconds: Double, sides: Int,
                excludedBy: Set<Contraindication>, rhythm: Rhythm? = nil, motion: MotionTarget? = nil) {
        self.id = id
        self.title = title
        self.target = target
        self.cue = cue
        self.steps = steps
        self.mistake = mistake
        self.seconds = seconds
        self.sides = sides
        self.excludedBy = excludedBy
        self.rhythm = rhythm
        self.motion = motion
    }

    public var totalSeconds: Double { seconds * Double(sides) }

    /// Cue with the side for two-sided exercises.
    public func cue(side: Int) -> String {
        sides == 2 ? "\(cue) – \(side == 0 ? "links" : "rechts")" : cue
    }
}

public struct BodyProgram: Sendable, Identifiable, Hashable {
    public var id: BodyProgramID
    public var title: String
    public var sub: String
    public var symbol: String
    public var exercises: [BodyExercise]

    public func exercises(excluding c: Set<Contraindication>) -> [BodyExercise] {
        exercises.filter { $0.excludedBy.isDisjoint(with: c) }
    }

    public func minutes(excluding c: Set<Contraindication> = []) -> Int {
        Int((exercises(excluding: c).reduce(0) { $0 + $1.totalSeconds } / 60).rounded(.up))
    }
}

public enum BodyContent {
    private static let neckRisk: Set<Contraindication> = [.acuteNeckPain, .discHerniation, .dizziness, .recentInjury]
    private static let jawRisk: Set<Contraindication> = [.jawLock, .recentInjury]

    public static let neck = BodyProgram(id: .neck, title: "Nacken und Schultern", sub: "8 Übungen · Kopfvorhaltung, Trapezius, SCM", symbol: "figure.mind.and.body", exercises: [
        BodyExercise(id: "n1", title: "Schulterkreisen rückwärts", target: "Aufwärmen, Schultern senken",
                     cue: "Schultern langsam rückwärts kreisen",
                     steps: ["Aufrecht sitzen oder stehen, Arme hängen locker.", "Schultern hochziehen, nach hinten führen und nach unten sinken lassen.", "Große, ruhige Kreise – der Kopf bleibt still."],
                     mistake: "Nicht hektisch kreisen und den Nacken nicht mitbewegen.", seconds: 30, sides: 1, excludedBy: []),
        BodyExercise(id: "n2", title: "Kinn einziehen (Chin Tuck)", target: "Tiefe Nackenbeuger, Kopfvorhaltung",
                     cue: "Kinn waagerecht nach hinten schieben",
                     steps: ["Blick geradeaus, Nacken lang.", "Kinn waagerecht nach hinten gleiten lassen, als würdest du ein Doppelkinn machen.", "5 Sekunden halten, lösen – etwa 10 Wiederholungen."],
                     mistake: "Nicht nicken: Der Blick bleibt geradeaus, der Kopf gleitet nur nach hinten.", seconds: 60, sides: 1, excludedBy: [.recentInjury],
                     rhythm: .hold("Halten", 5, release: 2)),
        BodyExercise(id: "n3", title: "Seitneigung mit leichtem Handzug", target: "Oberer Trapezius",
                     cue: "Ohr sanft Richtung Schulter",
                     steps: ["Kopf zur Seite neigen, das Ohr wandert Richtung Schulter.", "Die Hand derselben Seite liegt locker auf dem Kopf – nur ihr Gewicht wirkt.", "Die andere Schulter Richtung Boden sinken lassen und ruhig atmen."],
                     mistake: "Nicht die Schulter zum Ohr hochziehen, nicht ziehen bis es schmerzt.", seconds: 30, sides: 2, excludedBy: neckRisk,
                     motion: MotionTarget(axis: .roll, degrees: -30, holdS: 20)),
        BodyExercise(id: "n4", title: "Blick zur Achsel", target: "Levator scapulae",
                     cue: "Nase Richtung Achsel",
                     steps: ["Kopf etwa 45 Grad zur Seite drehen.", "Blick senken, die Nase zeigt Richtung Achsel.", "Hand an den Hinterkopf und sanft Gewicht geben."],
                     mistake: "Nicht ruckartig, kein Druck auf den Hinterkopf.", seconds: 30, sides: 2, excludedBy: neckRisk,
                     motion: MotionTarget(axis: .yaw, degrees: -40, holdS: 20)),
        BodyExercise(id: "n5", title: "Rotation mit leichtem Kinnheben", target: "Kopfwender (SCM), häufiger Tinnitus-Triggerpunkt",
                     cue: "Drehen, Kinn leicht schräg nach oben",
                     steps: ["Kopf zur Seite drehen.", "Kinn leicht schräg nach oben heben, bis die Gegenseite des Halses lang wird.", "Ruhig weiteratmen."],
                     mistake: "Den Kopf nicht in den Nacken fallen lassen.", seconds: 30, sides: 2, excludedBy: neckRisk,
                     motion: MotionTarget(axis: .yaw, degrees: -55, holdS: 20)),
        BodyExercise(id: "n6", title: "Isometrisch halten", target: "Stabilisierung, bewusste Entspannung",
                     cue: "Gegen die Hand drücken – ohne Bewegung",
                     steps: ["Hand an die Stirn und mit halber Kraft dagegen drücken.", "Dann am Hinterkopf, an der linken und an der rechten Schläfe.", "Der Kopf bewegt sich nicht. Nach jedem Drücken bewusst locker lassen."],
                     mistake: "Nicht mit voller Kraft und nicht die Luft anhalten.", seconds: 60, sides: 1, excludedBy: neckRisk,
                     rhythm: .hold("Drücken", 5, release: 3)),
        BodyExercise(id: "n7", title: "Brustöffner", target: "Gegenspieler der Vorhaltung",
                     cue: "Brust öffnen, kleiner Schritt nach vorn",
                     steps: ["Unterarme an einen Türrahmen oder an die Wand, Ellbogen auf Schulterhöhe.", "Einen kleinen Schritt nach vorn, bis sich die Brust öffnet.", "Bauch leicht fest, kein Hohlkreuz."],
                     mistake: "Nicht ins Hohlkreuz fallen.", seconds: 45, sides: 1, excludedBy: []),
        BodyExercise(id: "n8", title: "Nachspüren", target: "Abschluss",
                     cue: "Ruhig atmen und nachspüren",
                     steps: ["Augen schließen, wenn du magst.", "Ein paar langsame Atemzüge.", "Wie fühlen sich Nacken und Schultern jetzt an?"],
                     mistake: "", seconds: 30, sides: 1, excludedBy: [], rhythm: .breath),
    ])

    public static let jaw = BodyProgram(id: .jaw, title: "Kiefer und Gesicht", sub: "8 Übungen · Ruheposition, Rocabado, Kaumuskeln", symbol: "figure.cooldown", exercises: [
        BodyExercise(id: "j1", title: "Ruheposition", target: "Grundhaltung gegen Pressen",
                     cue: "Zunge oben, Zähne auseinander",
                     steps: ["Zungenspitze an den Gaumen hinter den Schneidezähnen.", "Zähne leicht auseinander, Lippen locker geschlossen.", "Ruhig durch die Nase atmen."],
                     mistake: "Die Zähne berühren sich nicht.", seconds: 45, sides: 1, excludedBy: [], rhythm: .breath),
        BodyExercise(id: "j2", title: "Geführte Öffnung", target: "Rocabado 6×6, kontrollierte Öffnung",
                     cue: "Mund langsam öffnen, Zunge bleibt oben",
                     steps: ["Zungenspitze am Gaumen lassen.", "Mund langsam öffnen – nur so weit, wie es mit der Zunge oben geht.", "Langsam wieder schließen, etwa 6 Wiederholungen."],
                     mistake: "Der Kiefer weicht nicht zur Seite aus, die Zunge bleibt oben.", seconds: 60, sides: 1, excludedBy: jawRisk,
                     rhythm: .hold("Öffnen", 4, release: 4, releaseLabel: "Schließen")),
        BodyExercise(id: "j3", title: "Kaumuskel-Massage", target: "Masseter",
                     cue: "Kaumuskel sanft kreisend massieren",
                     steps: ["Kaumuskel finden: vor dem Ohr, spürbar beim Zubeißen.", "Mund leicht öffnen.", "Mit den Fingerkuppen langsam und mit sanftem Druck kreisen."],
                     mistake: "Kein starker Druck auf das Gelenk selbst.", seconds: 45, sides: 2, excludedBy: []),
        BodyExercise(id: "j4", title: "Schläfenmuskel-Massage", target: "Temporalis",
                     cue: "Schläfen sanft kreisen",
                     steps: ["Fingerkuppen an beide Schläfen.", "Langsam kreisen.", "Den Unterkiefer dabei locker hängen lassen."],
                     mistake: "Nicht die Stirn runzeln.", seconds: 45, sides: 1, excludedBy: []),
        BodyExercise(id: "j5", title: "Kiefer pendeln", target: "Mobilisation",
                     cue: "Kiefer locker seitlich pendeln",
                     steps: ["Mund leicht öffnen.", "Unterkiefer locker nach links und rechts pendeln lassen.", "Klein und ohne Kraft."],
                     mistake: "Keine großen Ausschläge, kein Knacken provozieren.", seconds: 30, sides: 1, excludedBy: jawRisk),
        BodyExercise(id: "j6", title: "Öffnen gegen die Hand", target: "Koordination",
                     cue: "Gegen die Hand öffnen – ohne Bewegung",
                     steps: ["Faust oder Hand unter das Kinn.", "Den Mund mit leichter Kraft öffnen wollen, die Hand hält dagegen.", "Halten, lösen – etwa 5 Wiederholungen."],
                     mistake: "Nur leichte Kraft, keine Schmerzen.", seconds: 45, sides: 1, excludedBy: jawRisk,
                     rhythm: .hold("Dagegen halten", 5, release: 3)),
        BodyExercise(id: "j7", title: "Gesicht anspannen und loslassen", target: "Kontrast-Entspannung",
                     cue: "Anspannen – und loslassen",
                     steps: ["Ganzes Gesicht anspannen: Augen zukneifen, Nase rümpfen, Lippen zusammen.", "Kurz halten.", "Alles loslassen und nachspüren – 3 Mal."],
                     mistake: "Die Zähne nicht aufeinanderpressen.", seconds: 45, sides: 1, excludedBy: [],
                     rhythm: .hold("Anspannen", 5, release: 10, releaseLabel: "Loslassen")),
        BodyExercise(id: "j8", title: "Nachspüren", target: "Abschluss",
                     cue: "Ruheposition finden",
                     steps: ["Zunge am Gaumen, Zähne auseinander, Lippen zu.", "Ruhig atmen.", "Spür nach, wie weich der Kiefer jetzt ist."],
                     mistake: "", seconds: 30, sides: 1, excludedBy: [], rhythm: .breath),
    ])

    public static let programs = [neck, jaw]
    public static func program(_ id: BodyProgramID) -> BodyProgram { id == .neck ? neck : jaw }

    public static let intro = "Etwa zwei Drittel der Betroffenen können ihren Tinnitus über Kiefer oder Nacken verändern. Für sie sind diese Programme ein gezielter Baustein, für alle anderen eine gute Entspannung. Sie ersetzen keine Physiotherapie."
    /// Sources for the intro and the exercise selection (shown under the header).
    public static let refs = "Levine 1999; Sanchez et al. 2002; Michiels et al. 2016, Manual Therapy; Michiels et al. 2018"
}
