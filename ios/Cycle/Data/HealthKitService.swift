import Foundation
import HealthKit

/// Read-only access to Apple Health. Everything is aggregated per calendar day on device.
final class HealthKitService: HealthDataSource {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType(),
            HKQuantityType(.appleSleepingWristTemperature),
            HKCategoryType(.menstrualFlow),
        ]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func healthDays(from: Date, to: Date) async -> [String: HealthDay] {
        guard isAvailable else { return [:] }

        async let hrv = dailyStatistic(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), sum: false, from: from, to: to)
        async let rhr = dailyStatistic(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), sum: false, from: from, to: to)
        async let steps = dailyStatistic(.stepCount, unit: .count(), sum: true, from: from, to: to)
        async let energy = dailyStatistic(.activeEnergyBurned, unit: .kilocalorie(), sum: true, from: from, to: to)
        async let temp = dailyStatistic(.appleSleepingWristTemperature, unit: .degreeCelsius(), sum: false, from: from, to: to)
        async let sleep = sleepByNight(from: Day.add(-1, to: from), to: to)
        async let workouts = workoutsByDay(from: from, to: to)
        async let flow = menstrualFlow(from: from, to: to)

        let (hrvV, rhrV, stepsV, energyV, tempV, sleepV, workoutsV, flowV) =
            await (hrv, rhr, steps, energy, temp, sleep, workouts, flow)

        var out: [String: HealthDay] = [:]
        var day = Day.start(from)
        while day < to {
            let k = Day.key(day)
            var h = HealthDay()
            h.hrv = hrvV[k]
            h.restingHR = rhrV[k]
            h.steps = stepsV[k]
            h.activeEnergy = energyV[k]
            h.wristTemp = tempV[k]
            h.sleepHours = sleepV[k]?.hours
            h.sleepEfficiency = sleepV[k]?.efficiency
            h.workoutCount = workoutsV[k]?.count ?? 0
            h.workoutMinutes = workoutsV[k]?.minutes ?? 0
            h.flow = flowV[k]?.flow ?? false
            h.cycleStartMarked = flowV[k]?.start ?? false
            out[k] = h
            day = Day.add(1, to: day)
        }
        return out
    }

    // MARK: Quantity statistics

    private func dailyStatistic(_ id: HKQuantityTypeIdentifier, unit: HKUnit, sum: Bool,
                                from: Date, to: Date) async -> [String: Double] {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: sum ? .cumulativeSum : .discreteAverage,
            anchorDate: Day.start(from),
            intervalComponents: DateComponents(day: 1))
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var out: [String: Double] = [:]
        collection.enumerateStatistics(from: from, to: to) { stats, _ in
            let q = sum ? stats.sumQuantity() : stats.averageQuantity()
            if let q { out[Day.key(stats.startDate)] = q.doubleValue(for: unit) }
        }
        return out
    }

    // MARK: Sleep

    private struct Night {
        var hours: Double
        var efficiency: Double?
    }

    /// Sleep is assigned to the morning it ends: a session that starts between 18:00 the
    /// previous day and 18:00 belongs to that day. Overlapping samples from several sources
    /// (iPhone + Watch) are merged so nothing is double-counted.
    private func sleepByNight(from: Date, to: Date) async -> [String: Night] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: store) else { return [:] }

        let asleepValues = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        var asleep: [String: [DateInterval]] = [:]
        var inBed: [String: [DateInterval]] = [:]
        for s in samples {
            guard s.endDate > s.startDate else { continue }
            let key = Day.key(s.startDate.addingTimeInterval(6 * 3600))
            let interval = DateInterval(start: s.startDate, end: s.endDate)
            if asleepValues.contains(s.value) {
                asleep[key, default: []].append(interval)
            } else {
                inBed[key, default: []].append(interval) // inBed and awake
            }
        }

        var out: [String: Night] = [:]
        for (key, intervals) in asleep {
            let asleepSeconds = Self.mergedDuration(intervals)
            guard asleepSeconds > 30 * 60 else { continue }
            var efficiency: Double?
            if let bed = inBed[key], !bed.isEmpty {
                let total = Self.mergedDuration(bed + intervals)
                if total > 0 { efficiency = min(1, asleepSeconds / total) }
            }
            out[key] = Night(hours: asleepSeconds / 3600, efficiency: efficiency)
        }
        return out
    }

    private static func mergedDuration(_ intervals: [DateInterval]) -> TimeInterval {
        let sorted = intervals.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: DateInterval?
        for i in sorted {
            if let c = current, i.start <= c.end {
                current = DateInterval(start: c.start, end: max(c.end, i.end))
            } else {
                if let c = current { total += c.duration }
                current = i
            }
        }
        if let c = current { total += c.duration }
        return total
    }

    // MARK: Workouts

    private func workoutsByDay(from: Date, to: Date) async -> [String: (count: Int, minutes: Double)] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let workouts = try? await descriptor.result(for: store) else { return [:] }
        var out: [String: (count: Int, minutes: Double)] = [:]
        for w in workouts {
            let k = Day.key(w.startDate)
            let prev = out[k] ?? (0, 0)
            out[k] = (prev.count + 1, prev.minutes + w.duration / 60)
        }
        return out
    }

    // MARK: Cycle

    private func menstrualFlow(from: Date, to: Date) async -> [String: (flow: Bool, start: Bool)] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.menstrualFlow), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: store) else { return [:] }
        let noFlow = HKCategoryValueMenstrualFlow.none.rawValue
        var out: [String: (flow: Bool, start: Bool)] = [:]
        for s in samples where s.value != noFlow {
            let k = Day.key(s.startDate)
            let isStart = (s.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool) ?? false
            let prev = out[k] ?? (false, false)
            out[k] = (true, prev.start || isStart)
        }
        return out
    }
}
