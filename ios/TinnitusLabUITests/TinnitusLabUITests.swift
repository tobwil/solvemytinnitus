import XCTest

/// Smoke tests of the main flows (03-architektur: "wenige Smoke-Tests der Hauptflüsse").
@MainActor
final class TinnitusLabUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + args
        app.launch()
        return app
    }

    func testOnboardingReachesToday() {
        let app = launch([])
        app.buttons["Los geht’s"].tap()
        app.buttons["Nichts davon trifft zu"].tap()
        app.buttons["Weiter"].tap()
        if app.staticTexts["Lautsprecher – Messungen gesperrt"].waitForExistence(timeout: 2) {
            // real device without headphones: measurements are blocked, skip for later
            XCTAssertFalse(app.buttons["Testton links"].isEnabled)
            app.buttons["Keine Kopfhörer zur Hand – später prüfen"].tap()
        } else {
            // headphones (the simulator route counts as wired headphones)
            for side in ["links", "rechts"] {
                let b = app.buttons["Testton \(side)"]
                b.tap()
                for _ in 0..<40 where b.value as? String != "geprüft" { usleep(100_000) }
                XCTAssertEqual(b.value as? String, "geprüft")
            }
            let confirm = app.buttons["Ja, links und rechts stimmen"]
            for _ in 0..<30 where !confirm.isEnabled { usleep(200_000) }
            XCTAssertTrue(confirm.isEnabled)
            confirm.tap()
        }
        app.buttons["Passt so"].tap()
        // avoid the notification permission alert in the test
        let reminders = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Check-in-Erinnerungen'")).firstMatch
        XCTAssertTrue(reminders.waitForExistence(timeout: 3))
        if reminders.value as? String == "1" { reminders.switches.firstMatch.tap() }
        XCTAssertEqual(reminders.value as? String, "0")
        app.buttons["Programm starten"].tap()
        XCTAssertTrue(app.staticTexts["Wie laut ist er gerade?"].waitForExistence(timeout: 8))
    }

    func testInlineCheckInFlow() {
        let app = launch(["-onboarded"])
        XCTAssertTrue(app.staticTexts["Wie laut ist er gerade?"].waitForExistence(timeout: 8))
        // tap the dial tracks at 60 % and 40 % of their width (the track sits at ~2/3 of the dial's height)
        app.otherElements["Lautheit"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.66)).tap()
        let distress = app.otherElements["Belastung"].firstMatch
        XCTAssertTrue(distress.waitForExistence(timeout: 3))
        distress.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.66)).tap()
        app.buttons["Eintragen"].tap()
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Erfasst um' AND label CONTAINS '6/10'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 4))

        // correct it: 6 → 8
        app.buttons["Ändern"].tap()
        XCTAssertTrue(app.buttons["Änderung speichern"].waitForExistence(timeout: 3))
        app.otherElements["Lautheit"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.66)).tap()
        app.buttons["Änderung speichern"].tap()
        let changed = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Erfasst um' AND label CONTAINS '8/10'")).firstMatch
        XCTAssertTrue(changed.waitForExistence(timeout: 4))

        // delete it: the empty check-in comes back
        app.buttons["Ändern"].tap()
        app.buttons["Eintrag löschen"].tap()
        app.alerts.buttons["Löschen"].tap()
        XCTAssertTrue(app.staticTexts["Wie laut ist er gerade?"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Ändern"].exists)
    }

    func testCheckInSheetFromDeepLink() {
        let app = launch(["-onboarded", "-route", "tinnituslab://checkin"])
        XCTAssertTrue(app.staticTexts["Wie ist es gerade?"].waitForExistence(timeout: 8))
        app.otherElements["Lautheit"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.66)).tap()
        app.otherElements["Belastung"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.66)).tap()
        app.buttons["Speichern"].tap()
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Erfasst um' AND label CONTAINS '6/10'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 4))
    }

    func testRoomsWithDemoData() {
        let app = launch(["-demo"])
        XCTAssertTrue(app.staticTexts["Dein Tag"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Üben"].tap()
        XCTAssertTrue(app.staticTexts["Was brauchst du jetzt?"].waitForExistence(timeout: 3))
        app.buttons["Er ist laut"].tap()
        XCTAssertTrue(app.staticTexts["Klang darüberlegen"].waitForExistence(timeout: 3))
        app.staticTexts["Klang"].tap()
        XCTAssertTrue(app.staticTexts["Klangprogramme"].waitForExistence(timeout: 3))
        app.staticTexts["Klanganreicherung"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Ich"].tap()
        XCTAssertTrue(app.staticTexts["Dein Tinnitus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Was sich zeigt"].exists || app.staticTexts["WAS SICH ZEIGT"].exists)
        app.staticTexts["Verlauf und Tagebuch"].tap()
        XCTAssertTrue(app.staticTexts["Was sich verändert"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Fluss"].tap()
        XCTAssertTrue(app.staticTexts["Dein Tag"].waitForExistence(timeout: 3))
    }

    func testSoundSessionStartsAndStops() {
        let app = launch(["-demo", "-route", "tinnituslab://sound/enrichment"])
        let start = app.buttons["Start"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        app.buttons["Überspringen"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        sleep(22)
        app.buttons["Beenden"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Sitzung beendet"].waitForExistence(timeout: 3))
        app.buttons["4 von 10"].tap()
    }
}
