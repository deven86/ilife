import SwiftUI
import SwiftData

/// Anything that belongs to one person in the family.
protocol MemberOwned: AnyObject {
    var memberUID: String { get set }
}

/// Who the app is currently showing. "" = you (the iPhone's owner).
enum Member {
    static let key = "activeMember"
    static var current: String { UserDefaults.standard.string(forKey: key) ?? "" }
    static var isMe: Bool { current.isEmpty }

    /// Cached first names, so notifications and labels can say whose medicine it is.
    static func name(_ uid: String) -> String {
        uid.isEmpty ? "" : ((UserDefaults.standard.dictionary(forKey: "memberNames") as? [String: String])?[uid] ?? "")
    }
    /// "Priya · " for a family member, "" for you.
    static func prefix(_ uid: String) -> String {
        let n = name(uid)
        return n.isEmpty ? "" : "\(n) · "
    }
    static func cacheNames(_ profiles: [HealthProfile]) {
        var d: [String: String] = [:]
        for p in profiles where !p.memberUID.isEmpty { d[p.memberUID] = p.firstName.isEmpty ? p.relation : p.firstName }
        UserDefaults.standard.set(d, forKey: "memberNames")
    }
}

@MainActor
final class MemberStore: ObservableObject {
    static let shared = MemberStore()
    @Published private(set) var uid: String = Member.current
    var isMe: Bool { uid.isEmpty }

    func switchTo(_ newUID: String) {
        guard newUID != uid else { return }
        UserDefaults.standard.set(newUID, forKey: Member.key)
        uid = newUID
        AICoordinator.shared.loadToday()
        Haptics.tap()
    }
}

extension Array where Element: MemberOwned {
    /// Only the entries of the person currently shown.
    var mine: [Element] { let u = Member.current; return filter { $0.memberUID == u } }
}

/// Like `@Query`, but only returns the entries of the family member currently shown.
@propertyWrapper
struct MemberQuery<T: PersistentModel & MemberOwned>: DynamicProperty {
    @Query private var all: [T]
    @ObservedObject private var store = MemberStore.shared

    init() { _all = Query() }
    init<V: Comparable>(sort: KeyPath<T, V>, order: SortOrder = .forward) { _all = Query(sort: sort, order: order) }
    init<V: Comparable>(sort: KeyPath<T, V?>, order: SortOrder = .forward) { _all = Query(sort: sort, order: order) }

    var wrappedValue: [T] {
        let u = Member.current
        return all.filter { $0.memberUID == u }
    }
}

// MARK: - Family data

enum FamilyData {
    static let relations = ["Wife", "Husband", "Daughter", "Son", "Mother", "Father", "Sister", "Brother",
                            "Grandmother", "Grandfather", "Mother-in-law", "Father-in-law", "Sister-in-law", "Brother-in-law",
                            "Daughter-in-law", "Son-in-law", "Aunt", "Uncle", "Niece", "Nephew", "Cousin", "Granddaughter", "Grandson", "Friend", "Other"]

    static func icon(_ relation: String) -> String {
        switch relation {
        case "Daughter", "Son", "Niece", "Nephew", "Granddaughter", "Grandson": "figure.child"
        case "Grandmother", "Grandfather": "figure.walk.motion"
        default: "person.fill"
        }
    }

    static func age(_ p: HealthProfile) -> Int? {
        guard let dob = p.dateOfBirth else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: .now).year
    }

    /// "Wife · 34 y · Female"
    static func subtitle(_ p: HealthProfile) -> String {
        var parts: [String] = []
        if !p.relation.isEmpty { parts.append(p.relation) }
        if let a = age(p) {
            if a < 2, let dob = p.dateOfBirth, let m = Calendar.current.dateComponents([.month], from: dob, to: .now).month { parts.append("\(m) mo") }
            else { parts.append("\(p.ageOnly ? "~" : "")\(a) y") }
        }
        if !p.gender.isEmpty { parts.append(p.gender) }
        if !p.bloodGroup.isEmpty { parts.append(p.bloodGroup) }
        return parts.joined(separator: " · ")
    }

    /// Deletes every entry that belongs to a member, then the member.
    @MainActor
    static func deleteMember(_ uid: String, in ctx: ModelContext) {
        guard !uid.isEmpty else { return }
        func purge<T: PersistentModel & MemberOwned>(_ t: T.Type) {
            ((try? ctx.fetch(FetchDescriptor<T>())) ?? []).filter { $0.memberUID == uid }.forEach { ctx.delete($0) }
        }
        purge(FoodEntry.self); purge(WaterEntry.self); purge(WorkoutLog.self); purge(WorkoutPlan.self); purge(InBodyScan.self)
        purge(MedicalDocument.self); purge(EmergencyContact.self); purge(ProgressPhoto.self); purge(GymMembership.self)
        purge(Trainer.self); purge(GymPayment.self); purge(Expense.self); purge(BodyMeasurement.self); purge(CoachMessage.self)
        purge(Supplement.self); purge(SupplementDose.self); purge(DailyReview.self); purge(MeditationLog.self)
        purge(Medication.self); purge(MedicationDose.self); purge(Injury.self); purge(HealthEvent.self); purge(MedicalAttachment.self)
        purge(HealthProfile.self)
        // Remove that member's pending reminders.
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.filter { ($0.content.userInfo["member"] as? String) == uid }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        try? ctx.save()
    }

    /// How many entries a member has, for the delete warning.
    @MainActor
    static func entryCount(_ uid: String, in ctx: ModelContext) -> Int {
        func n<T: PersistentModel & MemberOwned>(_ t: T.Type) -> Int { ((try? ctx.fetch(FetchDescriptor<T>())) ?? []).filter { $0.memberUID == uid }.count }
        return n(FoodEntry.self) + n(WaterEntry.self) + n(WorkoutLog.self) + n(InBodyScan.self) + n(MedicalDocument.self) + n(ProgressPhoto.self)
            + n(BodyMeasurement.self) + n(Supplement.self) + n(MeditationLog.self) + n(Medication.self) + n(Injury.self) + n(HealthEvent.self)
            + n(MedicalAttachment.self) + n(Expense.self) + n(GymPayment.self)
    }
}
