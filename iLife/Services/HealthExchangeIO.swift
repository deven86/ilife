import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// iLife ⇄ iTeam: export everything to one file, import a file made by iTeam (or iLife).
@MainActor
enum HealthExchangeIO {
    private static func person(_ uid: String) -> String { uid.isEmpty ? "Me" : (Member.name(uid).isEmpty ? "Me" : Member.name(uid)) }

    private static func memberUID(for person: String) -> String {
        if person == "Me" || person.isEmpty { return "" }
        let names = UserDefaults.standard.dictionary(forKey: "memberNames") as? [String: String] ?? [:]
        return names.first { $0.value == person }?.key ?? ""
    }

    static func export(_ ctx: ModelContext) throws -> URL {
        var x = HealthExchange(source: "iLife", person: "Me")
        x.addFitness(from: ctx)
        let meds = (try? ctx.fetch(FetchDescriptor<Medication>())) ?? []
        x.medicines = meds.map { m in
            HealthExchange.ExMedicine(uid: m.uid, person: person(m.memberUID), name: m.name, strength: m.strength, form: m.formRaw, dose: m.dose,
                                      times: m.slots.compactMap { HealthExchange.slotTimes[$0] }.sorted(), weekdays: m.weekdays,
                                      start: m.startDate, end: m.endDate, instructions: m.instructions, doctor: m.doctorName, notes: m.notes, paused: m.isPaused)
        }
        let events = (try? ctx.fetch(FetchDescriptor<HealthEvent>())) ?? []
        x.healthEvents = events.map { e in
            HealthExchange.ExHealthEvent(uid: e.uid, person: person(e.memberUID), kind: e.kind, title: e.title, date: e.date, endDate: e.endDate,
                                         details: [e.diagnosis, e.procedure, e.notes].filter { !$0.isEmpty }.joined(separator: " · "),
                                         doctor: e.doctorName, hospital: e.hospital, status: e.status)
        }
        let injuries = (try? ctx.fetch(FetchDescriptor<Injury>())) ?? []
        x.healthEvents += injuries.map { i in
            HealthExchange.ExHealthEvent(uid: i.uid, person: person(i.memberUID), kind: "Injury", title: i.title, date: i.date, endDate: i.healedDate,
                                         details: [i.bodyPart, i.howItHappened, i.notes].filter { !$0.isEmpty }.joined(separator: " · "),
                                         doctor: i.doctorName, hospital: i.hospital, status: i.status)
        }
        return try x.write()
    }

    static func importFile(_ url: URL, into ctx: ModelContext) throws -> String {
        let x = try HealthExchange.read(url)
        var added = x.importFitness(into: ctx)
        let haveMeds = Set(((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).map(\.uid))
        for m in x.medicines where !haveMeds.contains(m.uid) {
            let med = Medication()
            med.uid = m.uid; med.memberUID = memberUID(for: m.person)
            med.name = m.name; med.strength = m.strength; med.dose = m.dose
            med.formRaw = MedForm(rawValue: m.form)?.rawValue ?? MedForm.allCases.first { $0.rawValue.lowercased().hasPrefix(m.form.lowercased()) }?.rawValue ?? MedForm.other.rawValue
            med.slots = Array(Set(m.times.map { HealthExchange.slot(for: $0) }))
            med.weekdays = m.weekdays; med.startDate = m.start
            if let end = m.end {
                med.weeks = 0
                med.courseDays = max(1, Calendar.current.dateComponents([.day], from: m.start, to: end).day ?? 1)
            } else { med.weeks = 0; med.courseDays = 0 }
            med.instructions = m.instructions; med.doctorName = m.doctor; med.notes = m.notes; med.isPaused = m.paused
            ctx.insert(med); added += 1
        }
        let haveEvents = Set(((try? ctx.fetch(FetchDescriptor<HealthEvent>())) ?? []).map(\.uid))
            .union(((try? ctx.fetch(FetchDescriptor<Injury>())) ?? []).map(\.uid))
        for e in x.healthEvents where !haveEvents.contains(e.uid) {
            if e.kind.lowercased().contains("injur") {
                let i = Injury()
                i.uid = e.uid; i.memberUID = memberUID(for: e.person); i.title = e.title; i.date = e.date
                i.notes = e.details; i.doctorName = e.doctor; i.hospital = e.hospital
                i.status = e.status.lowercased().contains("recover") || e.status.lowercased().contains("heal") ? "Healed" : "Active"
                i.healedDate = e.endDate
                ctx.insert(i)
            } else {
                let h = HealthEvent()
                h.uid = e.uid; h.memberUID = memberUID(for: e.person); h.title = e.title; h.date = e.date; h.endDate = e.endDate
                let k = e.kind.lowercased()
                h.kind = k.contains("surg") ? "Surgery / operation" : k.contains("hospital") ? "Hospitalisation" : k.contains("ill") ? "Illness / disease" : "Other"
                h.notes = e.details; h.doctorName = e.doctor; h.hospital = e.hospital
                h.status = e.status.lowercased().contains("recover") ? "Recovered" : "Under treatment"
                ctx.insert(h)
            }
            added += 1
        }
        try? ctx.save()
        return "Added \(added) item(s) from \(x.source) — \(x.summary). Anything already here was skipped."
    }
}

/// Settings → iTeam ⇄ iLife
struct HealthExchangeView: View {
    @Environment(\.modelContext) private var ctx
    @State private var shareURL: URL?
    @State private var importing = false
    @State private var result: String?

    var body: some View {
        Form {
            Section {
                Button("Export to iTeam", systemImage: "square.and.arrow.up") {
                    do { shareURL = try HealthExchangeIO.export(ctx) } catch { result = error.localizedDescription }
                }
                Button("Import from iTeam", systemImage: "square.and.arrow.down") { importing = true }
                if let result { Text(result).font(.callout) }
            } footer: {
                Text("Workouts, plans, meals, water, body measurements, supplements, meditation, medicines, injuries and health events move between iLife and iTeam in one file. Export here → save to Files or AirDrop → in iTeam open Settings → iLife ⇄ iTeam → Import (and the other way round). Nothing already present is duplicated.")
            }
        }
        .navigationTitle("iTeam ⇄ iLife")
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            switch r {
            case .success(let url):
                do { result = try HealthExchangeIO.importFile(url, into: ctx) } catch { result = "Couldn't read that file. Export it again from iTeam and retry." }
            case .failure(let e): result = e.localizedDescription
            }
        }
    }
}
