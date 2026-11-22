import AppIntents
import SwiftData
import Foundation

// "Hey Siri, …" — hands-free actions. They always act on YOUR records (not a family member's),
// and only when you're signed in to iLife on this device.

@MainActor
private enum SiriData {
    static var context: ModelContext? {
        AppData.shared.openIfSignedIn()
        return AppData.shared.container?.mainContext
    }
    static let notSignedIn: IntentDialog = "Open iLife and sign in first."

    static func me(_ ctx: ModelContext) -> HealthProfile? {
        ((try? ctx.fetch(FetchDescriptor<HealthProfile>())) ?? []).first { $0.memberUID.isEmpty }
    }

    static func today<T: PersistentModel & MemberOwned>(_ t: T.Type, _ ctx: ModelContext, date: KeyPath<T, Date>) -> [T] {
        let cal = Calendar.current
        return ((try? ctx.fetch(FetchDescriptor<T>())) ?? []).filter { $0.memberUID.isEmpty && cal.isDateInToday($0[keyPath: date]) }
    }
}

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Adds water to today's total in iLife.")

    @Parameter(title: "Millilitres", requestValueDialog: "How much water, in millilitres?")
    var millilitres: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let ctx = SiriData.context else { return .result(dialog: SiriData.notSignedIn) }
        guard (20...5000).contains(millilitres) else { return .result(dialog: "That doesn't sound right — say an amount between 20 and 5000 millilitres.") }
        let w = WaterEntry(millilitres: Double(millilitres))
        w.memberUID = ""
        ctx.insert(w)
        try? ctx.save()
        if Member.isMe { await HealthKitManager.shared.saveWater(ml: Double(millilitres)) }
        let total = SiriData.today(WaterEntry.self, ctx, date: \.date).reduce(0) { $0 + $1.millilitres } / 1000
        let goal = SiriData.me(ctx)?.waterGoalLitres ?? 3
        return .result(dialog: "Logged \(millilitres) ml. You've had \(String(format: "%.1f", total)) of \(String(format: "%.1f", goal)) litres today.")
    }
}

struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Weight"
    static let description = IntentDescription("Records today's body weight in iLife.")

    @Parameter(title: "Weight (kg)", requestValueDialog: "What’s your weight in kilograms?")
    var kilograms: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let ctx = SiriData.context else { return .result(dialog: SiriData.notSignedIn) }
        let m = BodyMeasurement(date: .now)
        m.memberUID = ""
        m.weightKg = kilograms
        ctx.insert(m)
        try? ctx.save()
        if Member.isMe { await HealthKitManager.shared.saveWeight(kg: kilograms) }
        var extra = ""
        if let goal = SiriData.me(ctx)?.targetWeightKg, goal > 0 {
            let diff = kilograms - goal
            extra = abs(diff) < 0.3 ? " You're at your goal!" : String(format: " %.1f kg to your goal.", abs(diff))
        }
        return .result(dialog: "Saved \(String(format: "%.1f", kilograms)) kilograms.\(extra)")
    }
}

struct TodaySummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "How's My Day"
    static let description = IntentDescription("Hear today's food, water, workouts and medicines from iLife.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let ctx = SiriData.context else { return .result(dialog: SiriData.notSignedIn) }
        let me = SiriData.me(ctx)
        let kcal = SiriData.today(FoodEntry.self, ctx, date: \.date).reduce(0) { $0 + $1.calories }
        let water = SiriData.today(WaterEntry.self, ctx, date: \.date).reduce(0) { $0 + $1.millilitres } / 1000
        let workouts = SiriData.today(WorkoutLog.self, ctx, date: \.start)
        let minutes = Int(workouts.reduce(0) { $0 + $1.durationMinutes })
        let today = Calendar.current.startOfDay(for: .now)
        let meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter { $0.memberUID.isEmpty && $0.isDue(on: today) }
        let taken = ((try? ctx.fetch(FetchDescriptor<MedicationDose>())) ?? []).filter { $0.memberUID.isEmpty && Calendar.current.isDate($0.day, inSameDayAs: today) }
        let dueCount = meds.reduce(0) { $0 + $1.doseSlots.count }
        var parts = ["You've eaten \(Int(kcal)) of \(Int(me?.calorieIntakeGoal ?? 2200)) calories",
                     "drunk \(String(format: "%.1f", water)) litres of water"]
        parts.append(workouts.isEmpty ? "no workout logged yet" : "worked out for \(minutes) minutes")
        var text = parts.joined(separator: ", ") + "."
        if dueCount > 0 {
            let left = max(0, dueCount - taken.count)
            text += left == 0 ? " All your medicine doses are ticked." : " \(left) medicine dose\(left == 1 ? "" : "s") still to take."
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct AskCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask iLife Coach"
    static let description = IntentDescription("Ask the iLife coach a question about your food, training or day. Uses Apple Intelligence on this iPhone, or Claude if you chose it.")

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask your coach?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let ctx = SiriData.context else { return .result(dialog: SiriData.notSignedIn) }
        let ai = AIService.shared
        guard ai.isOn else { return .result(dialog: "Turn on AI mode in iLife first: More, then AI Assistant.") }
        let data = await AIContext.build(day: .now, context: ctx, health: Member.isMe && HealthOwner.allowed ? .shared : .blank)
        do {
            let answer = try await ai.coach(history: [.init(role: "user", text: question)], context: data.text)
            let spoken = answer.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "#", with: "")
            return .result(dialog: IntentDialog(stringLiteral: String(spoken.prefix(900))))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        }
    }
}

struct ILifeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: [
            "Log water in \(.applicationName)", "Add water in \(.applicationName)", "I drank water \(.applicationName)"
        ], shortTitle: "Log Water", systemImageName: "drop.fill")
        AppShortcut(intent: LogWeightIntent(), phrases: [
            "Log my weight in \(.applicationName)", "Record weight in \(.applicationName)"
        ], shortTitle: "Log Weight", systemImageName: "scalemass.fill")
        AppShortcut(intent: TodaySummaryIntent(), phrases: [
            "How's my day in \(.applicationName)", "My day in \(.applicationName)", "\(.applicationName) summary"
        ], shortTitle: "My Day", systemImageName: "sun.max.fill")
        AppShortcut(intent: AskCoachIntent(), phrases: [
            "Ask \(.applicationName) coach", "Ask my coach in \(.applicationName)"
        ], shortTitle: "Ask Coach", systemImageName: "sparkles")
    }
}
