import Foundation
import HealthKit
import SwiftData
import TinnitusCore

/// HealthKit (02-native-vorteile §2): read audiogram, sleep, HRV, resting HR, respiratory rate,
/// environmental and headphone audio exposure; write mindful minutes. Read per data type after consent;
/// data never leaves the device/iCloud.
@MainActor
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.audiogramSampleType(),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.environmentalAudioExposure),
            HKQuantityType(.headphoneAudioExposure),
        ]
    }

    private var writeTypes: Set<HKSampleType> { [HKCategoryType(.mindfulSession)] }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    // MARK: Write

    func saveMindful(start: Date, end: Date) async {
        guard isAvailable, store.authorizationStatus(for: HKCategoryType(.mindfulSession)) == .sharingAuthorized else { return }
        let s = HKCategorySample(type: HKCategoryType(.mindfulSession), value: HKCategoryValue.notApplicable.rawValue, start: start, end: end)
        try? await store.save(s)
    }

    // MARK: Audiogram

    struct Audiogram: Sendable {
        var date: Date
        var left: [HearingPoint]
        var right: [HearingPoint]
    }

    /// Latest audiogram (e.g. from the AirPods Pro hearing test), in dB HL, air conduction, unmasked preferred.
    func latestAudiogram() async -> Audiogram? {
        guard isAvailable else { return nil }
        let d = HKSampleQueryDescriptor(predicates: [.sample(type: HKObjectType.audiogramSampleType())], sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        guard let sample = try? await d.result(for: store).first as? HKAudiogramSample else { return nil }
        var left: [HearingPoint] = [], right: [HearingPoint] = []
        for p in sample.sensitivityPoints {
            let f = p.frequency.doubleValue(for: .hertz())
            let air = p.tests.filter { $0.type == .air }
            for side in [HKAudiogramSensitivityTestSide.left, .right] {
                let candidates = air.filter { $0.side == side }
                guard let t = candidates.first(where: { !$0.masked }) ?? candidates.first else { continue }
                let pt = HearingPoint(freq: f, level: t.sensitivity.doubleValue(for: .decibelHearingLevel()))
                if side == .left { left.append(pt) } else { right.append(pt) }
            }
        }
        return Audiogram(date: sample.endDate, left: left.sorted { $0.freq < $1.freq }, right: right.sorted { $0.freq < $1.freq })
    }

    // MARK: Daily values

    struct DayValues: Sendable {
        var day: String
        var sleepHours: Double?
        var hrvMs: Double?
        var restingHR: Double?
        var respiratoryRate: Double?
        var loudMinutes: Double?
        var headphoneDbA: Double?
        var headphoneMinutes: Double?
    }

    func dailyValues(days: Int = 30, now: Date = .now) async -> [DayValues] {
        guard isAvailable else { return [] }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now))!
        var out: [String: DayValues] = [:]
        func upd(_ key: String, _ f: (inout DayValues) -> Void) {
            var v = out[key] ?? DayValues(day: key)
            f(&v)
            out[key] = v
        }

        for (key, hours) in await sleepHours(since: start) { upd(key) { $0.sleepHours = hours } }
        for (key, v) in await dailyAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: start) { upd(key) { $0.hrvMs = v } }
        for (key, v) in await dailyAverage(.restingHeartRate, unit: .count().unitDivided(by: .minute()), since: start) { upd(key) { $0.restingHR = v } }
        for (key, v) in await dailyAverage(.respiratoryRate, unit: .count().unitDivided(by: .minute()), since: start) { upd(key) { $0.respiratoryRate = v } }
        for (key, v) in await exposure(.environmentalAudioExposure, since: start) { upd(key) { $0.loudMinutes = v.minutesOver80 } }
        for (key, v) in await exposure(.headphoneAudioExposure, since: start) {
            upd(key) {
                $0.headphoneDbA = v.leq
                $0.headphoneMinutes = v.minutes
            }
        }
        return out.values.sorted { $0.day < $1.day }
    }

    /// Writes/updates HealthSnapshot records.
    func sync(into ctx: ModelContext, days: Int = 30) async {
        let values = await dailyValues(days: days)
        let existing = Dictionary(ctx.all(HealthSnapshot.self).map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        for v in values {
            let snap = existing[v.day] ?? {
                let s = HealthSnapshot(day: v.day)
                ctx.insert(s)
                return s
            }()
            snap.sleepHours = v.sleepHours ?? snap.sleepHours
            snap.hrvMs = v.hrvMs ?? snap.hrvMs
            snap.restingHR = v.restingHR ?? snap.restingHR
            snap.respiratoryRate = v.respiratoryRate ?? snap.respiratoryRate
            snap.loudMinutes = v.loudMinutes ?? snap.loudMinutes
            snap.headphoneDbA = v.headphoneDbA ?? snap.headphoneDbA
            snap.headphoneMinutes = v.headphoneMinutes ?? snap.headphoneMinutes
            snap.updatedAt = .now
        }
        try? ctx.save()
    }

    /// Compares the app's estimated session levels with HealthKit's headphone exposure for Apple
    /// headphones and stores a ±3 dB correction per device (05-audio-engine, step 3).
    func plausibilityCheck(_ ctx: ModelContext) async {
        guard isAvailable else { return }
        let since = Date.now.addingTimeInterval(-30 * 86400)
        let sessions = ((try? ctx.fetch(FetchDescriptor<TherapySession>(predicate: #Predicate { $0.date > since }))) ?? [])
            .filter { $0.durationS >= 600 && $0.params.estimatedSPL != nil && ($0.params.device?.isApple ?? false) }
        var byKind: [DeviceKind: [(healthKit: Double, estimate: Double)]] = [:]
        for s in sessions {
            guard let est = s.params.estimatedSPL, let kind = s.params.device,
                  let leq = await headphoneLEQ(from: s.date.addingTimeInterval(-s.durationS), to: s.date) else { continue }
            byKind[kind, default: []].append((leq, est))
        }
        let settings = ctx.settings()
        for (kind, pairs) in byKind {
            if let c = Plausibility.correction(pairs) { settings.calibrationOffsets[Plausibility.key(kind)] = c }
        }
        try? ctx.save()
    }

    private func headphoneLEQ(from start: Date, to end: Date) async -> Double? {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let d = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.headphoneAudioExposure), predicate: pred)], sortDescriptors: [])
        guard let samples = try? await d.result(for: store), !samples.isEmpty else { return nil }
        var energy = 0.0, dur = 0.0
        for s in samples {
            let l = s.quantity.doubleValue(for: .decibelAWeightedSoundPressureLevel())
            let t = max(1, s.endDate.timeIntervalSince(s.startDate))
            energy += t * pow(10, l / 10)
            dur += t
        }
        return dur > 0 ? 10 * log10(energy / dur) : nil
    }

    /// Asleep time per wake-up day, overlapping samples from several sources merged.
    private func sleepHours(since start: Date) async -> [String: Double] {
        let pred = HKQuery.predicateForSamples(withStart: start, end: nil)
        let d = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: pred)], sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await d.result(for: store) else { return [:] }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        var byDay: [String: [(Date, Date)]] = [:]
        for s in samples where asleep.contains(s.value) {
            byDay[Day.key(s.endDate), default: []].append((s.startDate, s.endDate))
        }
        return byDay.mapValues { intervals in
            let sorted = intervals.sorted { $0.0 < $1.0 }
            var total = 0.0
            var cur: (Date, Date)?
            for iv in sorted {
                if let c = cur, iv.0 <= c.1 {
                    cur = (c.0, max(c.1, iv.1))
                } else {
                    if let c = cur { total += c.1.timeIntervalSince(c.0) }
                    cur = iv
                }
            }
            if let c = cur { total += c.1.timeIntervalSince(c.0) }
            return total / 3600
        }
    }

    private func dailyAverage(_ id: HKQuantityTypeIdentifier, unit: HKUnit, since start: Date) async -> [String: Double] {
        let type = HKQuantityType(id)
        let pred = HKQuery.predicateForSamples(withStart: start, end: nil)
        let d = HKStatisticsCollectionQueryDescriptor(predicate: .quantitySample(type: type, predicate: pred), options: .discreteAverage, anchorDate: Calendar.current.startOfDay(for: start), intervalComponents: DateComponents(day: 1))
        guard let coll = try? await d.result(for: store) else { return [:] }
        var out: [String: Double] = [:]
        coll.enumerateStatistics(from: start, to: .now) { stat, _ in
            if let q = stat.averageQuantity() { out[Day.key(stat.startDate)] = q.doubleValue(for: unit) }
        }
        return out
    }

    private struct Exposure { var minutesOver80: Double; var leq: Double?; var minutes: Double }

    /// Energy-averaged level (LEQ) and minutes > 80 dB(A) per day.
    private func exposure(_ id: HKQuantityTypeIdentifier, since start: Date) async -> [String: Exposure] {
        let pred = HKQuery.predicateForSamples(withStart: start, end: nil)
        let d = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id), predicate: pred)], sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await d.result(for: store) else { return [:] }
        var acc: [String: (energy: Double, dur: Double, loud: Double)] = [:]
        for s in samples {
            let l = s.quantity.doubleValue(for: .decibelAWeightedSoundPressureLevel())
            let dur = max(1, s.endDate.timeIntervalSince(s.startDate))
            let key = Day.key(s.startDate)
            var a = acc[key] ?? (0, 0, 0)
            a.energy += dur * pow(10, l / 10)
            a.dur += dur
            if l > 80 { a.loud += dur }
            acc[key] = a
        }
        return acc.mapValues { a in
            Exposure(minutesOver80: a.loud / 60, leq: a.dur > 0 ? 10 * log10(a.energy / a.dur) : nil, minutes: a.dur / 60)
        }
    }
}
