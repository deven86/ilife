import Foundation
import ActivityKit

/// Shared between the app and the widget extension.
enum AppGroup {
    static let id = "group.com.jondhale.ilife"
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

/// Snapshot the app writes for the "Today's Target" widget.
struct TodaySnapshot: Codable, Equatable {
    var steps: Double = 0
    var stepGoal: Double = 10_000
    var activeCalories: Double = 0
    var calorieGoal: Double = 600
    var exerciseMinutes: Double = 0
    var exerciseGoal: Double = 45
    var waterLitres: Double = 0
    var waterGoal: Double = 3
    var caloriesEaten: Double = 0
    var calorieIntakeGoal: Double = 2200
    var updated: Date = .now

    static let key = "todaySnapshot"

    static func load() -> TodaySnapshot {
        guard let data = AppGroup.defaults.data(forKey: key),
              let snap = try? JSONDecoder().decode(TodaySnapshot.self, from: data) else { return TodaySnapshot() }
        return snap
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: Self.key)
        }
    }
}

/// Live Activity shown on the Lock Screen and Dynamic Island during a session.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var heartRate: Int
        var calories: Int
        var currentExercise: String
        var songTitle: String?
        var isPaused: Bool
    }
    var workoutName: String
}
