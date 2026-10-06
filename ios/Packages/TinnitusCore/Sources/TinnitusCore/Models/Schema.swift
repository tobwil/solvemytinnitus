import Foundation
import SwiftData

public enum TinnitusSchema {
    public static let models: [any PersistentModel.Type] = [
        HearingTest.self, TinnitusSpectrum.self, TinnitusMatch.self, RITrial.self, SomaticTest.self,
        TherapySession.self, CheckIn.self, JournalEntry.self, WeeklyCheck.self, ThoughtRecord.self,
        MindExercise.self, BodySession.self, HealthSnapshot.self, AppSettings.self,
    ]

    public static let appGroup = "group.io.solvemytinnitus.lab"
    public static let cloudContainer = "iCloud.io.solvemytinnitus.lab"

    /// Shared store in the app group so widgets, intents and the app see the same data.
    /// CloudKit sync is used automatically when the iCloud entitlement is present.
    public static func makeContainer(inMemory: Bool = false, cloud: Bool = true) throws -> ModelContainer {
        let schema = Schema(models)
        let config: ModelConfiguration
        if inMemory {
            // explicit .none: the default (.automatic) would mirror even an in-memory store to CloudKit
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            #if os(macOS)
            config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            #else
            let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            let hasGroup = groupURL != nil
            // SwiftData stores in <group>/Library/Application Support, which doesn't exist on first launch
            if let groupURL {
                try? FileManager.default.createDirectory(at: groupURL.appending(path: "Library/Application Support"), withIntermediateDirectories: true)
            }
            config = ModelConfiguration(
                schema: schema,
                groupContainer: hasGroup ? .identifier(appGroup) : .none,
                cloudKitDatabase: cloud ? .automatic : .none
            )
            #endif
        }
        return try ModelContainer(for: schema, configurations: config)
    }
}

extension ModelContext {
    /// Fetch-or-create the single settings record.
    public func settings() -> AppSettings {
        if let s = try? fetch(FetchDescriptor<AppSettings>()).first { return s }
        let s = AppSettings()
        insert(s)
        return s
    }

    public func all<T: PersistentModel>(_ type: T.Type, sortBy: [SortDescriptor<T>] = []) -> [T] {
        (try? fetch(FetchDescriptor<T>(sortBy: sortBy))) ?? []
    }

    public func latestMatch() -> TinnitusMatch? {
        var d = FetchDescriptor<TinnitusMatch>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    public func latestSpectrum() -> TinnitusSpectrum? {
        var d = FetchDescriptor<TinnitusSpectrum>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    public func latestHearing() -> HearingTest? {
        var d = FetchDescriptor<HearingTest>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    public func latestSomatic() -> SomaticTest? {
        var d = FetchDescriptor<SomaticTest>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    /// Deletes every record. Used by "Alle Daten löschen" and before an import.
    public func deleteEverything() throws {
        try delete(model: HearingTest.self)
        try delete(model: TinnitusSpectrum.self)
        try delete(model: TinnitusMatch.self)
        try delete(model: RITrial.self)
        try delete(model: SomaticTest.self)
        try delete(model: TherapySession.self)
        try delete(model: CheckIn.self)
        try delete(model: JournalEntry.self)
        try delete(model: WeeklyCheck.self)
        try delete(model: ThoughtRecord.self)
        try delete(model: MindExercise.self)
        try delete(model: BodySession.self)
        try delete(model: HealthSnapshot.self)
        try delete(model: AppSettings.self)
        try save()
    }
}
