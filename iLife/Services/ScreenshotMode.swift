import SwiftUI
import SwiftData

/// App Store screenshots: launched by CI with `-uiScreenshots -screen <name>`.
/// Uses an in-memory store filled with sample data — never touches real data.
enum ScreenshotMode {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-uiScreenshots")
    static var screen: String {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-screen"), i + 1 < a.count else { return "home" }
        return a[i + 1]
    }

    /// Settings so no onboarding, lock or prompts cover the screen.
    static func prepareDefaults() {
        let d = UserDefaults.standard
        d.set(true, forKey: "onboarded")
        d.set(false, forKey: "lockEnabled")
        d.set("Rahul", forKey: "userName")
        d.set("", forKey: Member.key)
        d.set(false, forKey: "healthConnected")
    }

    @MainActor
    static func fakeHealth(_ h: HealthKitManager) {
        h.isAuthorized = true
        h.steps = 8_432; h.stepsYesterday = 10_210
        h.activeCalories = 486; h.exerciseMinutes = 38
        h.heartRate = 72; h.restingHeartRate = 61; h.hrv = 48
        h.sleepHours = 7.4; h.sleepYesterday = 6.9
        h.waterLitres = 2.1; h.weightKg = 78.4
        h.weeklyActiveCalories = [420, 610, 380, 702, 540, 655, 486]
    }

    @MainActor
    static func seed(_ ctx: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: dayOffset, to: today)!)!
        }

        // You
        let me = HealthProfile()
        me.firstName = "Rahul"; me.lastName = "Sharma"; me.gender = "Male"; me.bloodGroup = "B+"
        me.dateOfBirth = cal.date(byAdding: .year, value: -36, to: .now); me.heightCm = 176
        me.startWeightKg = 84; me.targetWeightKg = 75; me.calorieIntakeGoal = 2100; me.proteinGoal = 130
        me.stepGoal = 10_000; me.waterGoalLitres = 3; me.activeCalorieGoal = 600; me.exerciseMinuteGoal = 45
        ctx.insert(me)

        // Weight trend
        for (i, w) in [84.0, 83.1, 82.4, 81.6, 80.9, 80.1, 79.4, 78.9, 78.4].enumerated() {
            let m = BodyMeasurement(date: cal.date(byAdding: .day, value: -56 + i * 7, to: today)!)
            m.weightKg = w; m.waistCm = 94 - Double(i) * 0.8
            ctx.insert(m)
        }

        // Food today and earlier
        let foods: [(String, MealType, Double, Double, Double, Double, String, Int)] = [
            ("Black coffee", .earlyMorning, 5, 0, 1, 0, "1 cup", 6),
            ("Poha with peanuts", .breakfast, 320, 8, 52, 9, "1 plate", 8),
            ("Boiled eggs", .breakfast, 155, 13, 1, 11, "2 eggs", 8),
            ("Whey protein shake", .postWorkout, 140, 25, 4, 2, "1 scoop", 11),
            ("Dal, 2 rotis, sabzi", .lunch, 540, 22, 78, 14, "1 thali", 13),
            ("Greek yogurt with berries", .snacks, 180, 15, 20, 4, "1 bowl", 17),
        ]
        for f in foods {
            ctx.insert(FoodEntry(name: f.0, meal: f.1, calories: f.2, protein: f.3, carbs: f.4, fat: f.5, quantity: f.6, date: at(0, f.7)))
        }
        for d in 1...6 {
            ctx.insert(FoodEntry(name: "Breakfast", meal: .breakfast, calories: 420, protein: 22, carbs: 50, fat: 12, date: at(-d, 8)))
            ctx.insert(FoodEntry(name: "Lunch", meal: .lunch, calories: 650, protein: 32, carbs: 80, fat: 18, date: at(-d, 13)))
            ctx.insert(FoodEntry(name: "Dinner", meal: .dinner, calories: 600 + Double(d * 25), protein: 35, carbs: 60, fat: 20, date: at(-d, 20)))
        }
        for h in [7, 9, 11, 13, 15, 17] { ctx.insert(WaterEntry(millilitres: 350, date: at(0, h))) }

        // Workouts
        let plan: [(String, String, Int, Double, Double, [(String, Int, Double)])] = [
            ("Push day", "Strength", 0, 58, 410, [("Bench Press", 10, 60), ("Bench Press", 8, 65), ("Shoulder Press", 10, 30), ("Tricep Pushdown", 12, 25)]),
            ("Morning run", "Cardio", -1, 32, 340, []),
            ("Pull day", "Strength", -2, 62, 430, [("Deadlift", 6, 100), ("Lat Pulldown", 10, 55), ("Barbell Row", 10, 50)]),
            ("Yoga flow", "Flexibility", -3, 40, 160, []),
            ("Leg day", "Strength", -4, 65, 480, [("Squat", 8, 80), ("Leg Press", 12, 140), ("Lunges", 12, 20)]),
        ]
        for p in plan {
            let w = WorkoutLog(name: p.0, category: p.1, start: at(p.2, 7), durationMinutes: p.3, calories: p.4, avgHeartRate: 128)
            if p.0 == "Push day" { w.sessionType = "Personal Training" }
            ctx.insert(w)
            for (i, s) in p.5.enumerated() {
                let set = ExerciseSet(exercise: s.0, reps: s.1, weightKg: s.2, order: i)
                set.log = w
                ctx.insert(set)
            }
        }

        // Supplements
        for (n, c, slot) in [("Vitamin D3", "HealthKart", DoseSlot.afterBreakfast), ("Omega-3", "MuscleBlaze", DoseSlot.afterLunch), ("Magnesium", "Wellbeing", DoseSlot.bedtime)] {
            let s = Supplement(); s.name = n; s.company = c; s.dose = "1 capsule"; s.slots = [slot.rawValue]; s.weeks = 0; s.remind = false
            ctx.insert(s)
        }

        // Injury + its medicine
        let inj = Injury()
        inj.title = "Sprained right ankle"; inj.bodyPart = "Ankle"; inj.date = at(-9, 18); inj.severity = "Moderate"
        inj.howItHappened = "Twisted during box jumps"; inj.procedures = ["Ice / rest", "X-ray", "Physiotherapy"]
        inj.procedureNotes = "X-ray clear. Physio twice a week."; inj.doctorName = "Mehta"; inj.hospital = "City Ortho Clinic"
        inj.status = "Recovering"; inj.restrictions = "No running or jumping for 2 weeks"
        ctx.insert(inj)

        let meds: [(String, String, MedForm, String, [DoseSlot], Int, String, String)] = [
            ("Etoricoxib", "90 mg", .tablet, "1 tablet", [.afterBreakfast], 7, "Ankle pain", "injury"),
            ("Pantoprazole", "40 mg", .tablet, "1 tablet", [.emptyStomach], 7, "Stomach protection", "injury"),
            ("Diclofenac gel", "1%", .ointment, "Apply thin layer", [.afterBreakfast, .bedtime], 14, "Ankle swelling", "injury"),
            ("Thyronorm", "50 mcg", .tablet, "1 tablet", [.emptyStomach], 0, "Thyroid", ""),
        ]
        for m in meds {
            let x = Medication()
            x.name = m.0; x.strength = m.1; x.formRaw = m.2.rawValue; x.dose = m.3; x.slots = m.4.map(\.rawValue)
            x.startDate = at(-5, 9); x.courseDays = m.5; x.weeks = m.5 == 0 ? 0 : 1; x.cause = m.6
            x.doctorName = m.7.isEmpty ? "Rao" : "Mehta"; x.remind = false
            if m.7 == "injury" { x.linkedUID = inj.uid; x.linkedKind = "injury" }
            ctx.insert(x)
        }
        if let first = try? ctx.fetch(FetchDescriptor<Medication>()).first(where: { $0.name == "Thyronorm" }) {
            ctx.insert(MedicationDose(medicationUID: first.uid, slot: DoseSlot.emptyStomach.rawValue, day: today))
        }

        let ev = HealthEvent()
        ev.title = "Appendix surgery"; ev.kind = "Surgery / operation"; ev.date = cal.date(byAdding: .year, value: -2, to: today)!
        ev.procedure = "Laparoscopic appendectomy"; ev.doctorName = "Kulkarni"; ev.hospital = "Lifeline Hospital"
        ev.hospitalised = true; ev.status = "Recovered"
        ctx.insert(ev)

        // Family
        let family: [(String, String, String, Int, String, String)] = [
            ("Priya", "Wife", "Female", 33, "A+", "Penicillin"),
            ("Anaya", "Daughter", "Female", 7, "B+", "Peanuts"),
            ("Sunita", "Mother", "Female", 62, "O+", ""),
            ("Ramesh", "Father", "Male", 66, "B+", "Sulfa drugs"),
        ]
        for (i, f) in family.enumerated() {
            let p = HealthProfile()
            p.memberUID = UUID().uuidString; p.memberOrder = i + 1
            p.firstName = f.0; p.lastName = "Sharma"; p.relation = f.1; p.gender = f.2; p.bloodGroup = f.4; p.allergies = f.5
            p.dateOfBirth = cal.date(byAdding: .year, value: -f.3, to: .now)
            if f.1 == "Mother" { p.conditions = "Type 2 diabetes, BP" }
            ctx.insert(p)
            if f.1 == "Mother" {
                for (n, s) in [("Metformin", "500 mg"), ("Telmisartan", "40 mg")] {
                    let x = Medication(); x.memberUID = p.memberUID; x.name = n; x.strength = s; x.dose = "1 tablet"
                    x.slots = [DoseSlot.afterBreakfast.rawValue]; x.weeks = 0; x.remind = false
                    ctx.insert(x)
                }
            }
        }
        try? ctx.save()
        Member.cacheNames((try? ctx.fetch(FetchDescriptor<HealthProfile>())) ?? [])
    }
}
