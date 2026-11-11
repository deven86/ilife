import Foundation
import SwiftData

// CloudKit-compatible SwiftData models: every stored property has a default,
// no unique constraints, all relationships optional with an inverse.

// MARK: - Nutrition

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, snacks, dinner
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .snacks: "carrot.fill"
        case .dinner: "moon.stars.fill"
        }
    }
}

@Model final class FoodEntry {
    var name: String = ""
    var mealRaw: String = MealType.breakfast.rawValue
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var quantity: String = ""
    var date: Date = Date.now

    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .breakfast }
        set { mealRaw = newValue.rawValue }
    }

    init(name: String, meal: MealType, calories: Double, protein: Double, carbs: Double, fat: Double, quantity: String = "", date: Date = .now) {
        self.name = name; self.mealRaw = meal.rawValue; self.calories = calories
        self.protein = protein; self.carbs = carbs; self.fat = fat; self.quantity = quantity; self.date = date
    }
}

@Model final class WaterEntry {
    var millilitres: Double = 250
    var date: Date = Date.now
    init(millilitres: Double, date: Date = .now) { self.millilitres = millilitres; self.date = date }
}

// MARK: - Workouts

@Model final class WorkoutLog {
    var name: String = ""
    var category: String = "Strength"
    var start: Date = Date.now
    var durationMinutes: Double = 0
    var calories: Double = 0
    var avgHeartRate: Double = 0
    var notes: String = ""
    /// "iLife", "Apple Health", "Apple Watch" … where the workout came from
    var source: String = "iLife"
    /// HealthKit UUID, so imported workouts are never duplicated
    var healthKitID: String = ""
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.log) var sets: [ExerciseSet]? = []

    init(name: String, category: String, start: Date, durationMinutes: Double, calories: Double, avgHeartRate: Double = 0, source: String = "iLife", healthKitID: String = "") {
        self.name = name; self.category = category; self.start = start; self.durationMinutes = durationMinutes
        self.calories = calories; self.avgHeartRate = avgHeartRate; self.source = source; self.healthKitID = healthKitID
    }
}

@Model final class ExerciseSet {
    var exercise: String = ""
    var reps: Int = 0
    var weightKg: Double = 0
    var order: Int = 0
    var log: WorkoutLog?
    init(exercise: String, reps: Int, weightKg: Double, order: Int) {
        self.exercise = exercise; self.reps = reps; self.weightKg = weightKg; self.order = order
    }
}

@Model final class WorkoutPlan {
    var name: String = ""
    var focus: String = "Full Body"
    var level: String = "Intermediate"
    var estimatedMinutes: Int = 45
    /// Weekdays 1 = Sunday … 7 = Saturday (Calendar convention)
    var weekdays: [Int] = []
    var created: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \PlanExercise.plan) var exercises: [PlanExercise]? = []

    init(name: String, focus: String, level: String, estimatedMinutes: Int, weekdays: [Int]) {
        self.name = name; self.focus = focus; self.level = level
        self.estimatedMinutes = estimatedMinutes; self.weekdays = weekdays
    }

    var orderedExercises: [PlanExercise] { (exercises ?? []).sorted { $0.order < $1.order } }
}

@Model final class PlanExercise {
    var name: String = ""
    var sets: Int = 3
    var reps: String = "12"
    var restSeconds: Int = 60
    var order: Int = 0
    var plan: WorkoutPlan?
    init(name: String, sets: Int, reps: String, restSeconds: Int, order: Int) {
        self.name = name; self.sets = sets; self.reps = reps; self.restSeconds = restSeconds; self.order = order
    }
}

// MARK: - Body composition (InBody)

@Model final class InBodyScan {
    var date: Date = Date.now
    var weightKg: Double = 0
    var skeletalMuscleKg: Double = 0
    var bodyFatKg: Double = 0
    var bodyFatPercent: Double = 0
    var bmi: Double = 0
    var totalBodyWaterL: Double = 0
    var visceralFatLevel: Double = 0
    var bmrKcal: Double = 0
    var inBodyScore: Double = 0
    var notes: String = ""
    @Attribute(.externalStorage) var image: Data?

    init(date: Date = .now) { self.date = date }
}

// MARK: - Medical vault

enum MedicalDocKind: String, Codable, CaseIterable, Identifiable {
    case report = "Reports", prescription = "Prescriptions", lab = "Lab Reports", doctorNote = "Doctor Notes"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .report: "doc.text.fill"
        case .prescription: "pills.fill"
        case .lab: "flask.fill"
        case .doctorNote: "stethoscope"
        }
    }
}

@Model final class MedicalDocument {
    var title: String = ""
    var kindRaw: String = MedicalDocKind.report.rawValue
    var date: Date = Date.now
    var doctor: String = ""
    var notes: String = ""
    var fileType: String = "pdf"   // pdf | jpg
    @Attribute(.externalStorage) var file: Data?

    var kind: MedicalDocKind {
        get { MedicalDocKind(rawValue: kindRaw) ?? .report }
        set { kindRaw = newValue.rawValue }
    }

    init(title: String, kind: MedicalDocKind, date: Date = .now, fileType: String, file: Data?) {
        self.title = title; self.kindRaw = kind.rawValue; self.date = date; self.fileType = fileType; self.file = file
    }
}

// MARK: - Profile, emergency, goals, alarms

@Model final class EmergencyContact {
    var name: String = ""
    var relation: String = ""
    var phone: String = ""
    var isPrimary: Bool = false
    init(name: String, relation: String, phone: String, isPrimary: Bool = false) {
        self.name = name; self.relation = relation; self.phone = phone; self.isPrimary = isPrimary
    }
}

@Model final class HealthProfile {
    var bloodGroup: String = ""
    var allergies: String = ""
    var conditions: String = ""
    var medications: String = ""
    var heightCm: Double = 0
    var stepGoal: Double = 10_000
    var activeCalorieGoal: Double = 600
    var exerciseMinuteGoal: Double = 45
    var waterGoalLitres: Double = 3
    var calorieIntakeGoal: Double = 2200
    var proteinGoal: Double = 120
    var targetWeightKg: Double = 0
    var targetDate: Date = Date.now.addingTimeInterval(60 * 60 * 24 * 90)
    var startWeightKg: Double = 0
    init() {}
}

@Model final class AppAlarm {
    var label: String = "Workout"
    var hour: Int = 6
    var minute: Int = 30
    var weekdays: [Int] = []      // empty = every day
    var isOn: Bool = true
    var notificationID: String = UUID().uuidString
    init(label: String, hour: Int, minute: Int, weekdays: [Int]) {
        self.label = label; self.hour = hour; self.minute = minute; self.weekdays = weekdays
    }
    var timeText: String { String(format: "%02d:%02d", hour, minute) }
}

enum ILifeSchema {
    static let models: [any PersistentModel.Type] = [
        FoodEntry.self, WaterEntry.self, WorkoutLog.self, ExerciseSet.self, WorkoutPlan.self, PlanExercise.self,
        InBodyScan.self, MedicalDocument.self, EmergencyContact.self, HealthProfile.self, AppAlarm.self
    ]
}
