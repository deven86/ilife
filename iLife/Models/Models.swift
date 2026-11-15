import Foundation
import SwiftData

// CloudKit-compatible SwiftData models: every stored property has a default,
// no unique constraints, all relationships optional with an inverse.

// MARK: - Nutrition

enum MealType: String, Codable, CaseIterable, Identifiable {
    case earlyMorning, breakfast, preWorkout, postWorkout, lunch, snacks, dinner, drinks, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .earlyMorning: "Early Morning"
        case .breakfast: "Breakfast"
        case .preWorkout: "Pre-Workout"
        case .postWorkout: "Post-Workout"
        case .lunch: "Lunch"
        case .snacks: "Snacks"
        case .dinner: "Dinner"
        case .drinks: "Drinks & Beverages"
        case .other: "Other"
        }
    }
    var icon: String {
        switch self {
        case .earlyMorning: "sun.horizon.fill"
        case .breakfast: "sunrise.fill"
        case .preWorkout: "bolt.fill"
        case .postWorkout: "figure.cooldown"
        case .lunch: "sun.max.fill"
        case .snacks: "carrot.fill"
        case .dinner: "moon.stars.fill"
        case .drinks: "cup.and.saucer.fill"
        case .other: "fork.knife"
        }
    }
    /// The four main meals are always shown; the rest appear once something is logged in them.
    var isCore: Bool { [.breakfast, .lunch, .snacks, .dinner].contains(self) }

    /// Best guess for "now" — the user can always change it.
    static func suggested(for date: Date = .now) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<7: .earlyMorning
        case 7..<11: .breakfast
        case 11..<15: .lunch
        case 15..<19: .snacks
        case 19..<24: .dinner
        default: .other
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
    @Attribute(.externalStorage) var photo: Data?

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
    /// "Self" or "Personal Training"
    var sessionType: String = "Self"
    var trainerID: String = ""
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.log) var sets: [ExerciseSet]? = []

    var orderedSets: [ExerciseSet] { (sets ?? []).sorted { $0.order < $1.order } }
    var exerciseNames: [String] {
        var seen = Set<String>(); return orderedSets.map(\.exercise).filter { seen.insert($0).inserted }
    }
    var isPT: Bool { sessionType == "Personal Training" }

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
    var durationMinutes: Double = 0   // cardio
    var distanceKm: Double = 0        // cardio
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
    @Attribute(.externalStorage) var coverPhoto: Data?
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
    var equipment: String = ""
    @Attribute(.externalStorage) var photo: Data?
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
    // Extra values read by AI (0 = not on the sheet)
    var proteinKg: Double = 0
    var mineralKg: Double = 0
    var fatFreeMassKg: Double = 0
    var waistHipRatio: Double = 0
    var targetWeightKg: Double = 0
    var weightControlKg: Double = 0
    var fatControlKg: Double = 0
    var muscleControlKg: Double = 0
    var rightArmKg: Double = 0
    var leftArmKg: Double = 0
    var trunkKg: Double = 0
    var rightLegKg: Double = 0
    var leftLegKg: Double = 0
    /// "On-device" or "AI"
    var readBy: String = "On-device"
    var aiSummary: String = ""
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
    // Personal details
    var firstName: String = ""
    var lastName: String = ""
    var email: String = ""
    var phone: String = ""
    var dateOfBirth: Date?
    var gender: String = ""
    @Attribute(.externalStorage) var avatar: Data?
    init() {}

    var fullName: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

// MARK: - Transformation journey

@Model final class ProgressPhoto {
    var date: Date = Date.now
    var pose: String = "Front"        // Front | Side | Back | Other
    var weightKg: Double = 0
    var note: String = ""
    @Attribute(.externalStorage) var image: Data?
    @Attribute(.externalStorage) var thumbnail: Data?
    var isVideo: Bool = false
    var durationSeconds: Double = 0
    @Attribute(.externalStorage) var video: Data?
    init(date: Date = .now, pose: String, image: Data?, thumbnail: Data?) {
        self.date = date; self.pose = pose; self.image = image; self.thumbnail = thumbnail
    }
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
        InBodyScan.self, MedicalDocument.self, EmergencyContact.self, HealthProfile.self, AppAlarm.self, ProgressPhoto.self,
        BodyMeasurement.self, CoachMessage.self, LibraryPhoto.self, CustomFood.self, CustomExercise.self, GymMembership.self, Trainer.self, GymPayment.self, Expense.self,
        Supplement.self, SupplementDose.self, DailyReview.self, ExerciseMedia.self
    ]
}


// MARK: - Saved photos & personal library

/// A photo you added once for an exercise or a food — reused everywhere that item appears.
@Model final class LibraryPhoto {
    var kind: String = "exercise"     // exercise | food
    var key: String = ""              // normalised item name
    var updated: Date = Date.now
    @Attribute(.externalStorage) var image: Data?
    init(kind: String, key: String, image: Data?) { self.kind = kind; self.key = key; self.image = image }
}

@Model final class CustomFood {
    var name: String = ""
    var serving: String = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var category: String = "My Foods"
    var created: Date = Date.now
    init(name: String, serving: String, calories: Double, protein: Double, carbs: Double, fat: Double) {
        self.name = name; self.serving = serving; self.calories = calories; self.protein = protein; self.carbs = carbs; self.fat = fat
    }
}

@Model final class CustomExercise {
    var name: String = ""
    var muscle: String = "Other"
    var equipment: String = ""
    var isCardio: Bool = false
    init(name: String, muscle: String, equipment: String, isCardio: Bool) {
        self.name = name; self.muscle = muscle; self.equipment = equipment; self.isCardio = isCardio
    }
}

// MARK: - Gym, trainers, money

@Model final class GymMembership {
    var gymName: String = ""
    var branch: String = ""
    var address: String = ""
    var phone: String = ""
    var memberID: String = ""
    var planName: String = ""        // e.g. 12 months
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var fee: Double = 0
    var latitude: Double = 0
    var longitude: Double = 0
    var notes: String = ""
    @Attribute(.externalStorage) var photo: Data?
    init() {}
    var daysLeft: Int { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: endDate).day ?? 0 }
    var isActive: Bool { endDate >= Calendar.current.startOfDay(for: .now) }
}

@Model final class Trainer {
    var uid: String = UUID().uuidString
    var firstName: String = ""
    var lastName: String = ""
    var speciality: String = ""
    var phone: String = ""
    var gymName: String = ""
    var feePerSession: Double = 0
    /// Sessions already taken before you started logging them in iLife.
    var priorSessions: Int = 0
    var notes: String = ""
    @Attribute(.externalStorage) var photo: Data?
    init() {}
    var fullName: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

enum PaymentKind: String, CaseIterable, Identifiable {
    case membership = "Gym Membership", personalTraining = "Personal Training", other = "Other"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .membership: "building.2.fill"
        case .personalTraining: "figure.strengthtraining.traditional"
        case .other: "indianrupeesign.circle.fill"
        }
    }
}

@Model final class GymPayment {
    var kindRaw: String = PaymentKind.membership.rawValue
    var amount: Double = 0
    var date: Date = Date.now
    var method: String = "UPI"
    var trainerID: String = ""
    var sessionsIncluded: Int = 0      // personal-training package size
    var validFrom: Date?
    var validTo: Date?
    var reference: String = ""
    var notes: String = ""
    var billType: String = ""          // pdf | jpg
    @Attribute(.externalStorage) var bill: Data?
    init() {}
    var kind: PaymentKind {
        get { PaymentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case protein = "Protein", creatine = "Creatine", supplements = "Supplements", food = "Healthy Food",
         gear = "Gear & Clothing", shoes = "Shoes", equipment = "Home Equipment", medical = "Medical & Tests", other = "Other"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .protein: "takeoutbag.and.cup.and.straw.fill"
        case .creatine: "pills.fill"
        case .supplements: "cross.vial.fill"
        case .food: "carrot.fill"
        case .gear: "tshirt.fill"
        case .shoes: "shoe.fill"
        case .equipment: "dumbbell.fill"
        case .medical: "stethoscope"
        case .other: "bag.fill"
        }
    }
}

@Model final class Expense {
    var title: String = ""
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var amount: Double = 0
    var date: Date = Date.now
    var vendor: String = ""
    var quantity: String = ""
    var notes: String = ""
    var billType: String = ""          // pdf | jpg
    @Attribute(.externalStorage) var bill: Data?
    @Attribute(.externalStorage) var photo: Data?
    init() {}
    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}


// MARK: - Body measurements & coach chat

@Model final class BodyMeasurement {
    var date: Date = Date.now
    var weightKg: Double = 0
    var waistCm: Double = 0
    var chestCm: Double = 0
    var hipsCm: Double = 0
    var armCm: Double = 0
    var thighCm: Double = 0
    var neckCm: Double = 0
    var note: String = ""
    init(date: Date = .now) { self.date = date }
}

@Model final class CoachMessage {
    var role: String = "user"      // user | assistant
    var text: String = ""
    var date: Date = Date.now
    init(role: String, text: String) { self.role = role; self.text = text }
}


// MARK: - Supplements

/// When in the day a supplement is taken. `hour`/`minute` are the default reminder time.
enum DoseSlot: String, CaseIterable, Identifiable {
    case emptyStomach = "Empty stomach (morning)"
    case beforeBreakfast = "Before breakfast", afterBreakfast = "After breakfast"
    case beforeLunch = "Before lunch", afterLunch = "After lunch"
    case beforeSnack = "Before snack", afterSnack = "After snack"
    case preWorkout = "Pre-workout", postWorkout = "Post-workout"
    case beforeDinner = "Before dinner", afterDinner = "After dinner"
    case bedtime = "Bedtime"
    var id: String { rawValue }

    var time: (hour: Int, minute: Int) {
        switch self {
        case .emptyStomach: (6, 30)
        case .beforeBreakfast: (8, 0)
        case .afterBreakfast: (9, 0)
        case .beforeLunch: (12, 45)
        case .afterLunch: (14, 0)
        case .beforeSnack: (16, 30)
        case .afterSnack: (17, 15)
        case .preWorkout: (17, 45)
        case .postWorkout: (19, 15)
        case .beforeDinner: (20, 0)
        case .afterDinner: (21, 15)
        case .bedtime: (22, 30)
        }
    }

    var icon: String {
        switch self {
        case .emptyStomach: "sun.horizon.fill"
        case .beforeBreakfast, .afterBreakfast: "sunrise.fill"
        case .beforeLunch, .afterLunch: "sun.max.fill"
        case .beforeSnack, .afterSnack: "carrot.fill"
        case .preWorkout, .postWorkout: "dumbbell.fill"
        case .beforeDinner, .afterDinner: "moon.stars.fill"
        case .bedtime: "bed.double.fill"
        }
    }

    /// Slots sorted through the day.
    var order: Int { time.hour * 60 + time.minute }
}

@Model final class Supplement {
    var uid: String = UUID().uuidString
    var name: String = ""
    var company: String = ""
    var dose: String = ""                 // e.g. "1 tablet", "1 spoon"
    /// DoseSlot raw values — one entry per time it's taken in a day.
    var slots: [String] = []
    /// Weekdays 1 = Sunday … 7 = Saturday. Empty = every day.
    var weekdays: [Int] = []
    var startDate: Date = Date.now
    var weeks: Int = 4                    // 0 = ongoing, no end
    var suggestedBy: String = "Self"      // Doctor | Trainer | Dietitian | Self | Other
    var suggestedByName: String = ""
    var purpose: String = ""
    var notes: String = ""
    var remind: Bool = true
    var isPaused: Bool = false
    @Attribute(.externalStorage) var photo: Data?
    init() {}

    var doseSlots: [DoseSlot] { slots.compactMap(DoseSlot.init(rawValue:)).sorted { $0.order < $1.order } }
    var timesPerDay: Int { max(slots.count, 1) }
    var endDate: Date? {
        weeks > 0 ? Calendar.current.date(byAdding: .day, value: weeks * 7, to: Calendar.current.startOfDay(for: startDate)) : nil
    }
    var isFinished: Bool { endDate.map { $0 <= Calendar.current.startOfDay(for: .now) } ?? false }
    var isCurrent: Bool { !isPaused && !isFinished && Calendar.current.startOfDay(for: startDate) <= .now }

    func isDue(on day: Date) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        guard !isPaused, d >= cal.startOfDay(for: startDate) else { return false }
        if let end = endDate, d >= end { return false }
        return weekdays.isEmpty || weekdays.contains(cal.component(.weekday, from: d))
    }

    /// 1-based week number of the course today.
    var currentWeek: Int {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate), to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return max(1, days / 7 + 1)
    }

    var scheduleText: String { Supplement.scheduleText(timesPerDay: timesPerDay, weekdays: weekdays, weeks: weeks) }

    /// "twice a day, every day for 4 weeks" / "once a week, every Friday for 3 weeks"
    static func scheduleText(timesPerDay: Int, weekdays: [Int], weeks: Int) -> String {
        let cal = Calendar.current
        let days: String
        if weekdays.isEmpty || weekdays.count == 7 { days = "every day" }
        else if weekdays.count == 1 { days = "every " + cal.weekdaySymbols[weekdays[0] - 1] }
        else { days = "on " + weekdays.sorted().map { cal.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ") }
        let times = timesPerDay == 1 ? "once" : timesPerDay == 2 ? "twice" : "\(timesPerDay) times"
        let perDay = weekdays.count == 1 ? (timesPerDay == 1 ? "once a week" : "\(times) that day") : "\(times) a day"
        let length = weeks > 0 ? " for \(weeks) week\(weeks == 1 ? "" : "s")" : ", ongoing"
        return "\(perDay), \(days)\(length)"
    }
}

/// One dose ticked off.
@Model final class SupplementDose {
    var supplementUID: String = ""
    var slot: String = ""
    var day: Date = Date.now          // start of the day it was for
    var takenAt: Date = Date.now
    init(supplementUID: String, slot: String, day: Date) {
        self.supplementUID = supplementUID; self.slot = slot; self.day = day
    }
}


// MARK: - AI daily plan / review history

/// One AI-written morning plan or night review, kept so the history is always there (and never paid for twice).
@Model final class DailyReview {
    var day: Date = Date.now              // start of the day it is about
    var kind: String = "night"            // morning | night
    var createdAt: Date = Date.now
    var headline: String = ""
    var overallScore: Int = 0
    /// The AI's full answer as JSON (MorningBrief or NightReview).
    var payload: String = ""
    /// The numbers the AI was shown (DayStats JSON) — lets history redraw the charts exactly as they were.
    var stats: String = ""
    var model: String = ""
    init(day: Date, kind: String) { self.day = day; self.kind = kind }
}

// MARK: - Exercise explainer media (saved once per exercise)

@Model final class ExerciseMedia {
    var key: String = ""                  // normalised exercise name
    var videoType: String = ""            // mov | mp4 | gif | ""
    var link: String = ""                 // e.g. a YouTube explainer
    var cues: String = ""                 // your own form notes
    var updated: Date = Date.now
    @Attribute(.externalStorage) var video: Data?
    @Attribute(.externalStorage) var equipmentPhoto: Data?
    init(key: String) { self.key = key }
}
