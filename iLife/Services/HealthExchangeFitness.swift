import Foundation
import SwiftData

/// Fitness, nutrition, supplements and meditation use the SAME models in iLife and iTeam,
/// so this file is identical in both apps. Care / medical data has its own adapter per app.
extension HealthExchange {
    @MainActor
    mutating func addFitness(from ctx: ModelContext) {
        func all<T: PersistentModel>(_ t: T.Type) -> [T] { (try? ctx.fetch(FetchDescriptor<T>())) ?? [] }
        workouts = all(WorkoutLog.self).map { w in
            ExWorkout(name: w.name, category: w.category, start: w.start, durationMinutes: w.durationMinutes, calories: w.calories,
                    avgHeartRate: w.avgHeartRate, notes: w.notes, sessionType: w.sessionType,
                    sets: w.orderedSets.map { ExSet(exercise: $0.exercise, reps: $0.reps, weightKg: $0.weightKg, order: $0.order, durationMinutes: $0.durationMinutes, distanceKm: $0.distanceKm) })
        }
        food = all(FoodEntry.self).map { ExFood(name: $0.name, meal: $0.mealRaw, calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, quantity: $0.quantity, date: $0.date) }
        water = all(WaterEntry.self).map { ExWater(ml: $0.millilitres, date: $0.date) }
        body = all(BodyMeasurement.self).map { ExBody(date: $0.date, weightKg: $0.weightKg, waistCm: $0.waistCm, chestCm: $0.chestCm, hipsCm: $0.hipsCm, armCm: $0.armCm, thighCm: $0.thighCm, neckCm: $0.neckCm, note: $0.note) }
        plans = all(WorkoutPlan.self).map { p in
            ExPlan(name: p.name, focus: p.focus, level: p.level, estimatedMinutes: p.estimatedMinutes, weekdays: p.weekdays,
                 exercises: p.orderedExercises.map { ExPlanEx(name: $0.name, sets: $0.sets, reps: $0.reps, restSeconds: $0.restSeconds, order: $0.order, equipment: $0.equipment) })
        }
        supplements = all(Supplement.self).map { s in
            ExSupplement(uid: s.uid, name: s.name, company: s.company, dose: s.dose, slots: s.slots, weekdays: s.weekdays, startDate: s.startDate, weeks: s.weeks,
                       suggestedBy: s.suggestedBy, suggestedByName: s.suggestedByName, purpose: s.purpose, notes: s.notes, remind: s.remind, isPaused: s.isPaused)
        }
        meditations = all(MeditationLog.self).map { m in
            ExMeditation(date: m.date, sessionID: m.sessionID, title: m.title, category: m.category, minutes: m.minutes, language: m.language,
                       soundscape: m.soundscape, moodBefore: m.moodBefore, moodAfter: m.moodAfter, completed: m.completed, note: m.note)
        }
        customMeditations = all(CustomMeditation.self).map { ExCustomMeditation(uid: $0.uid, title: $0.title, language: $0.language, created: $0.created, stepsJSON: $0.stepsJSON) }
        customFoods = all(CustomFood.self).map { ExCustomFood(name: $0.name, serving: $0.serving, calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, category: $0.category) }
        customExercises = all(CustomExercise.self).map { ExCustomExercise(name: $0.name, muscle: $0.muscle, equipment: $0.equipment, isCardio: $0.isCardio) }
    }

    /// Adds what isn't already there (matched by name + time, or uid). Returns how many items were added.
    @MainActor
    func importFitness(into ctx: ModelContext) -> Int {
        func all<T: PersistentModel>(_ t: T.Type) -> [T] { (try? ctx.fetch(FetchDescriptor<T>())) ?? [] }
        func key(_ d: Date) -> Int { Int(d.timeIntervalSince1970 / 60) }
        var added = 0

        let haveW = Set(all(WorkoutLog.self).map { "\($0.name)|\(key($0.start))" })
        for w in workouts where !haveW.contains("\(w.name)|\(key(w.start))") {
            let log = WorkoutLog(name: w.name, category: w.category, start: w.start, durationMinutes: w.durationMinutes, calories: w.calories, avgHeartRate: w.avgHeartRate)
            log.notes = w.notes; log.sessionType = w.sessionType
            ctx.insert(log)
            for s in w.sets {
                let set = ExerciseSet(exercise: s.exercise, reps: s.reps, weightKg: s.weightKg, order: s.order)
                set.durationMinutes = s.durationMinutes; set.distanceKm = s.distanceKm; set.log = log
                ctx.insert(set)
            }
            added += 1
        }
        let haveF = Set(all(FoodEntry.self).map { "\($0.name)|\(key($0.date))" })
        for f in food where !haveF.contains("\(f.name)|\(key(f.date))") {
            let e = FoodEntry(name: f.name, meal: MealType(rawValue: f.meal) ?? .snacks, calories: f.calories, protein: f.protein, carbs: f.carbs, fat: f.fat, quantity: f.quantity, date: f.date)
            ctx.insert(e); added += 1
        }
        let haveWa = Set(all(WaterEntry.self).map { "\(Int($0.millilitres))|\(key($0.date))" })
        for w in water where !haveWa.contains("\(Int(w.ml))|\(key(w.date))") { ctx.insert(WaterEntry(millilitres: w.ml, date: w.date)); added += 1 }
        let haveB = Set(all(BodyMeasurement.self).map { key($0.date) })
        for b in body where !haveB.contains(key(b.date)) {
            let m = BodyMeasurement(date: b.date)
            m.weightKg = b.weightKg; m.waistCm = b.waistCm; m.chestCm = b.chestCm; m.hipsCm = b.hipsCm; m.armCm = b.armCm; m.thighCm = b.thighCm; m.neckCm = b.neckCm; m.note = b.note
            ctx.insert(m); added += 1
        }
        let haveP = Set(all(WorkoutPlan.self).map(\.name))
        for p in plans where !haveP.contains(p.name) {
            let plan = WorkoutPlan(name: p.name, focus: p.focus, level: p.level, estimatedMinutes: p.estimatedMinutes, weekdays: p.weekdays)
            ctx.insert(plan)
            for x in p.exercises {
                let e = PlanExercise(name: x.name, sets: x.sets, reps: x.reps, restSeconds: x.restSeconds, order: x.order)
                e.equipment = x.equipment; e.plan = plan
                ctx.insert(e)
            }
            added += 1
        }
        let haveS = Set(all(Supplement.self).map(\.uid))
        for s in supplements where !haveS.contains(s.uid) {
            let x = Supplement()
            x.uid = s.uid; x.name = s.name; x.company = s.company; x.dose = s.dose; x.slots = s.slots; x.weekdays = s.weekdays
            x.startDate = s.startDate; x.weeks = s.weeks; x.suggestedBy = s.suggestedBy; x.suggestedByName = s.suggestedByName
            x.purpose = s.purpose; x.notes = s.notes; x.remind = s.remind; x.isPaused = s.isPaused
            ctx.insert(x); added += 1
        }
        let haveM = Set(all(MeditationLog.self).map { "\($0.title)|\(key($0.date))" })
        for m in meditations where !haveM.contains("\(m.title)|\(key(m.date))") {
            let l = MeditationLog(date: m.date, sessionID: m.sessionID, title: m.title, minutes: m.minutes)
            l.category = m.category; l.language = m.language; l.soundscape = m.soundscape
            l.moodBefore = m.moodBefore; l.moodAfter = m.moodAfter; l.completed = m.completed; l.note = m.note
            ctx.insert(l); added += 1
        }
        let haveCM = Set(all(CustomMeditation.self).map(\.uid))
        for c in customMeditations where !haveCM.contains(c.uid) {
            let x = CustomMeditation(title: c.title, language: c.language, stepsJSON: c.stepsJSON)
            x.uid = c.uid; x.created = c.created
            ctx.insert(x); added += 1
        }
        let haveCF = Set(all(CustomFood.self).map(\.name))
        for c in customFoods where !haveCF.contains(c.name) {
            let x = CustomFood(name: c.name, serving: c.serving, calories: c.calories, protein: c.protein, carbs: c.carbs, fat: c.fat)
            x.category = c.category
            ctx.insert(x); added += 1
        }
        let haveCE = Set(all(CustomExercise.self).map(\.name))
        for c in customExercises where !haveCE.contains(c.name) {
            ctx.insert(CustomExercise(name: c.name, muscle: c.muscle, equipment: c.equipment, isCardio: c.isCardio)); added += 1
        }
        try? ctx.save()
        return added
    }
}
