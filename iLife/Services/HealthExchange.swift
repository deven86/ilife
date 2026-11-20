import Foundation

/// The file format shared by iLife and iTeam ("jondhale.health.v1").
/// Export from either app → a .json file → Import in the other app. Same file in both repos — keep them identical.
struct HealthExchange: Codable {
    var format = "jondhale.health.v1"
    var source: String
    var exported = Date.now
    var person: String

    struct ExSet: Codable { var exercise: String; var reps: Int; var weightKg: Double; var order: Int; var durationMinutes: Double; var distanceKm: Double }
    struct ExWorkout: Codable { var name: String; var category: String; var start: Date; var durationMinutes: Double; var calories: Double; var avgHeartRate: Double; var notes: String; var sessionType: String; var sets: [ExSet] }
    struct ExFood: Codable { var name: String; var meal: String; var calories: Double; var protein: Double; var carbs: Double; var fat: Double; var quantity: String; var date: Date }
    struct ExWater: Codable { var ml: Double; var date: Date }
    struct ExBody: Codable { var date: Date; var weightKg: Double; var waistCm: Double; var chestCm: Double; var hipsCm: Double; var armCm: Double; var thighCm: Double; var neckCm: Double; var note: String }
    struct ExPlanEx: Codable { var name: String; var sets: Int; var reps: String; var restSeconds: Int; var order: Int; var equipment: String }
    struct ExPlan: Codable { var name: String; var focus: String; var level: String; var estimatedMinutes: Int; var weekdays: [Int]; var exercises: [ExPlanEx] }
    struct ExSupplement: Codable { var uid: String; var name: String; var company: String; var dose: String; var slots: [String]; var weekdays: [Int]; var startDate: Date; var weeks: Int; var suggestedBy: String; var suggestedByName: String; var purpose: String; var notes: String; var remind: Bool; var isPaused: Bool }
    struct ExMeditation: Codable { var date: Date; var sessionID: String; var title: String; var category: String; var minutes: Double; var language: String; var soundscape: String; var moodBefore: Int; var moodAfter: Int; var completed: Bool; var note: String }
    struct ExCustomMeditation: Codable { var uid: String; var title: String; var language: String; var created: Date; var stepsJSON: String }
    /// times = minutes after midnight
    struct ExMedicine: Codable { var uid: String; var person: String; var name: String; var strength: String; var form: String; var dose: String; var times: [Int]; var weekdays: [Int]; var start: Date; var end: Date?; var instructions: String; var doctor: String; var notes: String; var paused: Bool }
    struct ExHealthEvent: Codable { var uid: String; var person: String; var kind: String; var title: String; var date: Date; var endDate: Date?; var details: String; var doctor: String; var hospital: String; var status: String }
    struct ExCustomFood: Codable { var name: String; var serving: String; var calories: Double; var protein: Double; var carbs: Double; var fat: Double; var category: String }
    struct ExCustomExercise: Codable { var name: String; var muscle: String; var equipment: String; var isCardio: Bool }

    var workouts: [ExWorkout] = []
    var food: [ExFood] = []
    var water: [ExWater] = []
    var body: [ExBody] = []
    var plans: [ExPlan] = []
    var supplements: [ExSupplement] = []
    var meditations: [ExMeditation] = []
    var customMeditations: [ExCustomMeditation] = []
    var medicines: [ExMedicine] = []
    var healthEvents: [ExHealthEvent] = []
    var customFoods: [ExCustomFood] = []
    var customExercises: [ExCustomExercise] = []

    static let fileName = "iLife-iTeam health data.json"

    func write() throws -> URL {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.fileName)
        try enc.encode(self).write(to: url, options: .atomic)
        return url
    }

    static func read(_ url: URL) throws -> HealthExchange {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let x = try dec.decode(HealthExchange.self, from: Data(contentsOf: url))
        guard x.format.hasPrefix("jondhale.health.") else { throw CocoaError(.fileReadCorruptFile) }
        return x
    }

    /// Dose-slot names used by iLife ↔ clock times used by iTeam Care.
    static let slotTimes: [String: Int] = [
        "Empty stomach (morning)": 390, "Before breakfast": 480, "After breakfast": 540, "Before lunch": 765, "After lunch": 840,
        "Before snack": 990, "After snack": 1035, "Pre-workout": 1065, "Post-workout": 1155, "Before dinner": 1215,
        "After dinner": 1290, "Bedtime": 1350,
    ]
    static func slot(for minutes: Int) -> String {
        slotTimes.min { abs($0.value - minutes) < abs($1.value - minutes) }?.key ?? "After breakfast"
    }

    var summary: String {
        var parts: [String] = []
        func add(_ n: Int, _ w: String) { if n > 0 { parts.append("\(n) \(w)") } }
        add(workouts.count, "workouts"); add(food.count, "meals"); add(water.count, "water logs"); add(body.count, "body logs")
        add(plans.count, "plans"); add(supplements.count, "supplements"); add(meditations.count, "meditations")
        add(medicines.count, "medicines"); add(healthEvents.count, "health events")
        return parts.isEmpty ? "No data" : parts.joined(separator: ", ")
    }
}
