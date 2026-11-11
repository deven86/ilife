import Foundation
import HealthKit
import SwiftData
import UserNotifications

/// Everything iLife reads from / writes to Apple Health.
/// Apple Watch, Google-ecosystem and third-party devices reach iLife through Apple Health:
/// any app that writes to Health (Watch, Garmin Connect, Strava, Fitbit via sync apps, etc.)
/// shows up here automatically.
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var steps: Double = 0
    @Published var activeCalories: Double = 0
    @Published var exerciseMinutes: Double = 0
    @Published var heartRate: Double = 0
    @Published var restingHeartRate: Double = 0
    @Published var hrv: Double = 0
    @Published var sleepHours: Double = 0
    @Published var waterLitres: Double = 0
    @Published var weightKg: Double = 0
    @Published var stepsYesterday: Double = 0
    @Published var sleepYesterday: Double = 0
    @Published var weeklyActiveCalories: [Double] = Array(repeating: 0, count: 7)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKObjectType.workoutType()]
        let q: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .appleExerciseTime, .heartRate,
                                              .restingHeartRate, .heartRateVariabilitySDNN, .bodyMass, .bodyFatPercentage,
                                              .leanBodyMass, .dietaryWater, .dietaryEnergyConsumed, .distanceWalkingRunning]
        q.forEach { s.insert(HKQuantityType($0)) }
        s.insert(HKCategoryType(.sleepAnalysis))
        return s
    }

    private var shareTypes: Set<HKSampleType> {
        var s: Set<HKSampleType> = [HKObjectType.workoutType()]
        let q: [HKQuantityTypeIdentifier] = [.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal,
                                              .dietaryWater, .bodyMass, .bodyFatPercentage, .leanBodyMass, .activeEnergyBurned]
        q.forEach { s.insert(HKQuantityType($0)) }
        return s
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            isAuthorized = true
            UserDefaults.standard.set(true, forKey: "healthConnected")
        } catch {
            print("HealthKit auth failed: \(error)")
        }
    }

    // MARK: Reading

    func refreshToday() async {
        guard isAvailable else { return }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: .now)
        let today = HKQuery.predicateForSamples(withStart: startOfDay, end: .now)
        let yStart = cal.date(byAdding: .day, value: -1, to: startOfDay)!
        let yesterday = HKQuery.predicateForSamples(withStart: yStart, end: startOfDay)

        steps = await sum(.stepCount, .count(), today)
        stepsYesterday = await sum(.stepCount, .count(), yesterday)
        activeCalories = await sum(.activeEnergyBurned, .kilocalorie(), today)
        exerciseMinutes = await sum(.appleExerciseTime, .minute(), today)
        waterLitres = await sum(.dietaryWater, .liter(), today)
        heartRate = await latest(.heartRate, HKUnit.count().unitDivided(by: .minute()))
        restingHeartRate = await latest(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()))
        hrv = await latest(.heartRateVariabilitySDNN, .secondUnit(with: .milli))
        weightKg = await latest(.bodyMass, .gramUnit(with: .kilo))
        sleepHours = await sleep(endingOn: startOfDay.addingTimeInterval(12 * 3600))
        sleepYesterday = await sleep(endingOn: yStart.addingTimeInterval(12 * 3600))

        var week: [Double] = []
        for offset in (0..<7).reversed() {
            let d = cal.date(byAdding: .day, value: -offset, to: startOfDay)!
            let p = HKQuery.predicateForSamples(withStart: d, end: cal.date(byAdding: .day, value: 1, to: d)!)
            week.append(await sum(.activeEnergyBurned, .kilocalorie(), p))
        }
        weeklyActiveCalories = week
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ predicate: NSPredicate) async -> Double {
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate), options: .cumulativeSum)
        let result = try? await descriptor.result(for: store)
        return result?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> Double {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        let samples = try? await descriptor.result(for: store)
        return samples?.first?.quantity.doubleValue(for: unit) ?? 0
    }

    /// Hours asleep in the 24h window ending at `end` (noon), counting only "asleep" stages.
    private func sleep(endingOn end: Date) async -> Double {
        let start = end.addingTimeInterval(-24 * 3600)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [])
        guard let samples = try? await descriptor.result(for: store) else { return 0 }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        // Merge overlapping intervals so Watch + iPhone don't double count.
        let intervals = samples.filter { asleep.contains($0.value) }
            .map { ($0.startDate, $0.endDate) }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for i in intervals {
            if let c = current, i.0 <= c.1 { current = (c.0, max(c.1, i.1)) }
            else { if let c = current { total += c.1.timeIntervalSince(c.0) }; current = i }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total / 3600
    }

    func recentWorkouts(days: Int = 30) async -> [HKWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 200)
        return (try? await descriptor.result(for: store)) ?? []
    }

    // MARK: Auto-detect workouts from Apple Watch / other apps

    /// Imports workouts recorded anywhere (Apple Watch auto-detect, Fitness, Strava, Garmin…) into iLife.
    /// Returns how many new workouts were imported.
    @discardableResult
    func importWorkouts(into context: ModelContext, notify: Bool) async -> Int {
        let workouts = await recentWorkouts()
        let existing = Set(((try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []).map(\.healthKitID))
        var added = 0
        for w in workouts where !existing.contains(w.uuid.uuidString) {
            // Skip workouts iLife itself saved (already logged locally)
            if w.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier { continue }
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            let hr = w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
            let source = w.sourceRevision.source.name
            let log = WorkoutLog(name: w.workoutActivityType.displayName, category: w.workoutActivityType.category,
                                 start: w.startDate, durationMinutes: w.duration / 60, calories: kcal, avgHeartRate: hr,
                                 source: source, healthKitID: w.uuid.uuidString)
            context.insert(log)
            added += 1
            if notify && w.endDate > Date.now.addingTimeInterval(-6 * 3600) {
                NotificationService.post(title: "Workout detected",
                                         body: "\(log.name) · \(Int(log.durationMinutes)) min · \(Int(kcal)) kcal from \(source) was added to iLife.")
            }
        }
        try? context.save()
        return added
    }

    /// Wakes iLife in the background whenever a new workout lands in Apple Health.
    func enableBackgroundWorkoutDetection(container: ModelContainer) {
        guard isAvailable else { return }
        let type = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            guard error == nil else { completion(); return }
            Task { @MainActor in
                let ctx = ModelContext(container)
                await HealthKitManager.shared.importWorkouts(into: ctx, notify: true)
                completion()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    // MARK: Writing

    func saveFood(_ entry: FoodEntry) async {
        let meta: [String: Any] = [HKMetadataKeyFoodType: entry.name]
        var samples: [HKQuantitySample] = []
        func add(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ v: Double) {
            guard v > 0 else { return }
            samples.append(HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: v),
                                            start: entry.date, end: entry.date, metadata: meta))
        }
        add(.dietaryEnergyConsumed, .kilocalorie(), entry.calories)
        add(.dietaryProtein, .gram(), entry.protein)
        add(.dietaryCarbohydrates, .gram(), entry.carbs)
        add(.dietaryFatTotal, .gram(), entry.fat)
        try? await store.save(samples)
    }

    func saveWater(ml: Double) async {
        let s = HKQuantitySample(type: HKQuantityType(.dietaryWater), quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml),
                                 start: .now, end: .now)
        try? await store.save(s)
        await refreshToday()
    }

    func saveInBody(_ scan: InBodyScan) async {
        var samples: [HKQuantitySample] = []
        if scan.weightKg > 0 {
            samples.append(HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: scan.weightKg), start: scan.date, end: scan.date))
        }
        if scan.bodyFatPercent > 0 {
            samples.append(HKQuantitySample(type: HKQuantityType(.bodyFatPercentage), quantity: HKQuantity(unit: .percent(), doubleValue: scan.bodyFatPercent / 100), start: scan.date, end: scan.date))
        }
        if scan.weightKg > 0 && scan.bodyFatKg > 0 {
            samples.append(HKQuantitySample(type: HKQuantityType(.leanBodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: scan.weightKg - scan.bodyFatKg), start: scan.date, end: scan.date))
        }
        try? await store.save(samples)
    }

    func saveWorkout(_ log: WorkoutLog, activity: HKWorkoutActivityType) async {
        let config = HKWorkoutConfiguration()
        config.activityType = activity
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        let end = log.start.addingTimeInterval(log.durationMinutes * 60)
        do {
            try await builder.beginCollection(at: log.start)
            if log.calories > 0 {
                let energy = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                              quantity: HKQuantity(unit: .kilocalorie(), doubleValue: log.calories), start: log.start, end: end)
                try await builder.addSamples([energy])
            }
            try await builder.endCollection(at: end)
            if let w = try await builder.finishWorkout() { log.healthKitID = w.uuid.uuidString }
        } catch {
            print("Save workout failed: \(error)")
        }
    }

    /// Most recent heart-rate sample within the last 2 minutes (streamed by Apple Watch during workouts).
    func liveHeartRate() async -> Int {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate),
                                         predicate: HKQuery.predicateForSamples(withStart: .now.addingTimeInterval(-120), end: .now))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        let s = try? await descriptor.result(for: store)
        return Int(s?.first?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0)
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength Training"
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .yoga: "Yoga"
        case .highIntensityIntervalTraining: "HIIT"
        case .swimming: "Swimming"
        case .coreTraining: "Core Training"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .stairClimbing: "Stair Climbing"
        case .dance: "Dance"
        case .pilates: "Pilates"
        case .hiking: "Hiking"
        case .badminton: "Badminton"
        case .cricket: "Cricket"
        case .tennis: "Tennis"
        case .mixedCardio: "Cardio"
        case .flexibility: "Stretching"
        default: "Workout"
        }
    }

    var category: String {
        switch self {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: "Strength"
        case .yoga, .pilates, .flexibility: "Mind & Body"
        default: "Cardio"
        }
    }

    static func from(category: String) -> HKWorkoutActivityType {
        switch category {
        case "Strength": .traditionalStrengthTraining
        case "Cardio": .mixedCardio
        case "HIIT": .highIntensityIntervalTraining
        case "Yoga", "Mind & Body": .yoga
        case "Running": .running
        case "Walking": .walking
        case "Cycling": .cycling
        default: .other
        }
    }
}

enum NotificationService {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func post(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
