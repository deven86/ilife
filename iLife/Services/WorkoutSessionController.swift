import Foundation
import ActivityKit
import SwiftData
import HealthKit

/// Runs an in-app workout session: timer, Lock Screen Live Activity, Apple Music, heart rate, logging.
@MainActor
final class WorkoutSessionController: ObservableObject {
    static let shared = WorkoutSessionController()

    @Published var isActive = false
    @Published var isPaused = false
    @Published var name = ""
    @Published var category = "Strength"
    @Published var exercises: [String] = []
    @Published var exercisePhotos: [Data?] = []
    @Published var exerciseEquipment: [String] = []
    @Published var exerciseIndex = 0
    @Published var elapsed: TimeInterval = 0
    @Published var heartRate = 0
    @Published var calories: Double = 0

    private(set) var startDate = Date.now
    private var pausedAccum: TimeInterval = 0
    private var pauseStart: Date?
    private var timer: Timer?
    private var activity: Activity<WorkoutActivityAttributes>?
    private var tick = 0

    var currentExercise: String { exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : name }
    var currentPhoto: Data? { exercisePhotos.indices.contains(exerciseIndex) ? exercisePhotos[exerciseIndex] : nil }
    var currentEquipment: String { exerciseEquipment.indices.contains(exerciseIndex) ? exerciseEquipment[exerciseIndex] : "" }

    private var met: Double {
        switch category {
        case "HIIT": 8
        case "Cardio", "Running": 7.5
        case "Cycling": 7
        case "Yoga", "Mind & Body": 3
        case "Walking": 3.5
        default: 5
        }
    }

    func start(name: String, category: String, exercises: [String], photos: [Data?] = [], equipment: [String] = []) {
        guard !isActive else { return }
        self.name = name; self.category = category; self.exercises = exercises
        self.exercisePhotos = photos; self.exerciseEquipment = equipment
        exerciseIndex = 0; elapsed = 0; calories = 0; heartRate = 0; pausedAccum = 0; isPaused = false
        startDate = .now; isActive = true

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.onTick() }
        }
        startLiveActivity()
        Task { await MusicController.shared.startWorkoutMusic(); updateLiveActivity() }
    }

    private func onTick() async {
        guard isActive, !isPaused else { return }
        elapsed = Date.now.timeIntervalSince(startDate) - pausedAccum
        let weight = HealthKitManager.shared.weightKg > 0 ? HealthKitManager.shared.weightKg : 70
        calories = met * weight * (elapsed / 3600)
        tick += 1
        if tick % 10 == 0 {
            let hr = await HealthKitManager.shared.liveHeartRate()
            if hr > 0 { heartRate = hr }
            MusicController.shared.refreshNowPlaying()
            updateLiveActivity()
        }
    }

    func togglePause() {
        if isPaused, let p = pauseStart { pausedAccum += Date.now.timeIntervalSince(p); pauseStart = nil }
        else { pauseStart = .now }
        isPaused.toggle()
        updateLiveActivity()
    }

    func nextExercise() {
        if exerciseIndex < exercises.count - 1 { exerciseIndex += 1; updateLiveActivity() }
    }

    func finish(context: ModelContext, save: Bool) async {
        timer?.invalidate(); timer = nil
        if isPaused, let p = pauseStart { pausedAccum += Date.now.timeIntervalSince(p) }
        let duration = (Date.now.timeIntervalSince(startDate) - pausedAccum) / 60
        isActive = false
        MusicController.shared.stop()
        await endLiveActivity()
        guard save, duration >= 1 else { return }
        let log = WorkoutLog(name: name, category: category, start: startDate, durationMinutes: duration,
                             calories: calories, avgHeartRate: Double(heartRate), source: "iLife")
        context.insert(log)
        await HealthKitManager.shared.saveWorkout(log, activity: .from(category: category))
        try? context.save()
    }

    // MARK: Live Activity (Lock Screen + Dynamic Island)

    private var state: WorkoutActivityAttributes.ContentState {
        .init(startedAt: startDate.addingTimeInterval(pausedAccum), heartRate: heartRate, calories: Int(calories),
              currentExercise: currentExercise, songTitle: MusicController.shared.nowPlaying, isPaused: isPaused)
    }

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: WorkoutActivityAttributes(workoutName: name),
                                            content: .init(state: state, staleDate: nil))
        } catch {
            print("Live Activity failed: \(error)")
        }
    }

    private func updateLiveActivity() {
        guard let activity else { return }
        let s = state
        Task { await activity.update(.init(state: s, staleDate: nil)) }
    }

    private func endLiveActivity() async {
        await activity?.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(60)))
        activity = nil
    }
}
