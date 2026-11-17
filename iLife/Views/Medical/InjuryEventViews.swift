import SwiftUI
import SwiftData

// MARK: - Linked medicines (shared by injuries and health events)

struct LinkedMedicinesSection: View {
    let ownerUID: String
    let ownerKind: String
    let cause: String
    let doctor: String
    let hospital: String
    @MemberQuery(sort: \Medication.startDate, order: .reverse) private var meds: [Medication]
    @State private var editing: Medication?
    @State private var adding = false

    private var linked: [Medication] { meds.filter { $0.linkedUID == ownerUID } }

    var body: some View {
        Section {
            ForEach(linked) { m in
                Button { editing = m } label: {
                    HStack(spacing: 10) {
                        ItemThumbnail(photo: m.photo, illustration: Illustration(symbol: m.form.icon, colors: [.red, .pink]), size: 36, corner: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.displayName).foregroundStyle(Color.primary)
                            Text(m.scheduleText).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if m.isFinished { Text("Done").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            Button("Add a medicine for this", systemImage: "plus.circle.fill") { adding = true }
        } header: {
            Text("Medicines (\(linked.count))")
        } footer: {
            Text("Medicines added here also appear in Medicines, with reminders and dose tracking.")
        }
        .sheet(isPresented: $adding) {
            MedicineEditor(medication: nil, linkUID: ownerUID, linkKind: ownerKind, presetCause: cause, presetDoctor: doctor, presetHospital: hospital)
        }
        .sheet(item: $editing) { MedicineEditor(medication: $0) }
    }
}

/// Hospital stay fields shared by both editors.
struct HospitalStayFields: View {
    @Binding var hospitalised: Bool
    @Binding var admit: Date
    @Binding var discharge: Date
    @Binding var stillAdmitted: Bool
    var body: some View {
        Toggle("Hospitalised", isOn: $hospitalised.animation())
        if hospitalised {
            DatePicker("Admitted", selection: $admit, in: ...Date.now, displayedComponents: .date)
            Toggle("Still admitted", isOn: $stillAdmitted)
            if !stillAdmitted { DatePicker("Discharged", selection: $discharge, in: admit..., displayedComponents: .date) }
            if !stillAdmitted {
                let nights = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: admit), to: Calendar.current.startOfDay(for: discharge)).day ?? 0
                Text("\(nights) night\(nights == 1 ? "" : "s") in hospital").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Injuries

struct InjuryListView: View {
    @MemberQuery(sort: \Injury.date, order: .reverse) private var injuries: [Injury]
    @MemberQuery private var attachments: [MedicalAttachment]
    @State private var editing: Injury?
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if injuries.isEmpty {
                    ContentUnavailableView {
                        Label("No injuries logged", systemImage: "bandage")
                    } description: {
                        Text("Record what happened, the treatment (stitches, cast, surgery…), the hospital, photos, reports, medicines and costs.")
                    } actions: {
                        Button("Log an injury") { adding = true }.buttonStyle(.borderedProminent)
                    }
                    .glassCard()
                }
                ForEach(Array(injuries.enumerated()), id: \.element.id) { i, inj in
                    let atts = attachments.filter { $0.ownerUID == inj.uid }
                    let cost = atts.filter { $0.kind == "Bill" }.reduce(0) { $0 + $1.amount }
                    Button { editing = inj } label: {
                        HStack(alignment: .top, spacing: 12) {
                            medicalThumb(atts, icon: "bandage.fill", colors: [.orange, .red])
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(inj.title).font(.headline); Spacer(); StatusChip(text: inj.status) }
                                Text([inj.bodyPart, inj.date.formatted(date: .abbreviated, time: .omitted)].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if !inj.procedures.isEmpty { Text(inj.procedures.joined(separator: " · ")).font(.caption2).foregroundStyle(.tint) }
                                HStack(spacing: 10) {
                                    StatusChip(text: inj.severity)
                                    if inj.hospitalised { Label("Hospital", systemImage: "building.2.fill").font(.caption2) }
                                    if !atts.isEmpty { Label("\(atts.count)", systemImage: "paperclip").font(.caption2) }
                                    Spacer()
                                    if cost > 0 { Text(inr(cost)).font(.caption.bold()) }
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .glassCard()
                    }
                    .buttonStyle(PressStyle())
                    .appear(min(i, 8))
                }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Injuries")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { InjuryEditor(injury: nil) }
        .sheet(item: $editing) { InjuryEditor(injury: $0) }
    }
}

@ViewBuilder
func medicalThumb(_ atts: [MedicalAttachment], icon: String, colors: [Color]) -> some View {
    if let d = atts.first(where: { $0.kind == "Photo" })?.thumbnail ?? atts.first(where: { $0.thumbnail != nil })?.thumbnail, let img = UIImage(data: d) {
        Image(uiImage: img).resizable().scaledToFill().frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 12))
    } else {
        Image(systemName: icon).font(.title2).foregroundStyle(.white).frame(width: 58, height: 58)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct InjuryEditor: View {
    let injury: Injury?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var uid = UUID().uuidString
    @State private var title = ""
    @State private var bodyPart = ""
    @State private var date = Date.now
    @State private var how = ""
    @State private var severity = "Minor"
    @State private var procedures: Set<String> = []
    @State private var procedureNotes = ""
    @State private var doctor = ""
    @State private var hospital = ""
    @State private var hospitalised = false
    @State private var admit = Date.now
    @State private var discharge = Date.now
    @State private var stillAdmitted = false
    @State private var status = "Active"
    @State private var healed = Date.now
    @State private var restrictions = ""
    @State private var notes = ""
    @State private var confirmDelete = false
    @State private var loaded = false

    static let procedureOptions = ["First aid", "Ice / rest", "Dressing", "Stitches", "Plaster / cast", "Splint / brace", "X-ray", "MRI / CT scan",
                                   "Injection", "Surgery / operation", "Physiotherapy", "Other"]
    private let parts = ["Head", "Neck", "Shoulder", "Arm", "Elbow", "Wrist", "Hand / fingers", "Chest", "Back", "Lower back", "Abdomen",
                         "Hip", "Thigh", "Knee", "Leg", "Ankle", "Foot / toes"]

    var body: some View {
        NavigationStack {
            Form {
                Section("What happened") {
                    TextField("Title (e.g. Sprained right ankle)", text: $title)
                    TextField("Body part", text: $bodyPart)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(parts, id: \.self) { p in Button(p) { bodyPart = p }.font(.caption).buttonStyle(.bordered).tint(bodyPart == p ? .accentColor : .gray) } }
                    }
                    DatePicker("When", selection: $date, in: ...Date.now)
                    TextField("How it happened (e.g. during squats at the gym)", text: $how, axis: .vertical)
                    Picker("Severity", selection: $severity) { ForEach(["Minor", "Moderate", "Severe"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                }
                Section("Treatment") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 8) {
                        ForEach(Self.procedureOptions, id: \.self) { p in
                            let on = procedures.contains(p)
                            Button { if on { procedures.remove(p) } else { procedures.insert(p) } } label: {
                                Label(p, systemImage: on ? "checkmark.circle.fill" : "circle").font(.caption)
                            }
                            .buttonStyle(.plain).foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary))
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("Details (e.g. 6 stitches, cast for 4 weeks)", text: $procedureNotes, axis: .vertical)
                    TextField("Doctor", text: $doctor)
                    TextField("Hospital / clinic", text: $hospital)
                    HospitalStayFields(hospitalised: $hospitalised, admit: $admit, discharge: $discharge, stillAdmitted: $stillAdmitted)
                }
                Section("Recovery") {
                    Picker("Status", selection: $status) { ForEach(["Active", "Recovering", "Healed"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    if status == "Healed" { DatePicker("Healed on", selection: $healed, in: date..., displayedComponents: .date) }
                    TextField("Restrictions (e.g. no running for 3 weeks)", text: $restrictions, axis: .vertical)
                }
                AttachmentsSection(ownerUID: uid, ownerKind: "injury", ownerTitle: "Injury: \(title)")
                LinkedMedicinesSection(ownerUID: uid, ownerKind: "injury", cause: title, doctor: doctor, hospital: hospital)
                Section("Notes") { TextField("Pain level, progress, anything else", text: $notes, axis: .vertical) }
                if injury != nil { Section { Button("Delete injury", role: .destructive) { confirmDelete = true } } }
            }
            .navigationTitle(injury == nil ? "Log Injury" : "Injury")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .confirmationDialog("Delete this injury with its photos, reports and bills? Linked medicines are kept.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
            .onAppear(perform: load)
            .interactiveDismissDisabled()
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let x = injury else { return }
        uid = x.uid; title = x.title; bodyPart = x.bodyPart; date = x.date; how = x.howItHappened; severity = x.severity
        procedures = Set(x.procedures); procedureNotes = x.procedureNotes; doctor = x.doctorName; hospital = x.hospital
        hospitalised = x.hospitalised; admit = x.admitDate ?? x.date; discharge = x.dischargeDate ?? .now; stillAdmitted = x.hospitalised && x.dischargeDate == nil
        status = x.status; healed = x.healedDate ?? .now; restrictions = x.restrictions; notes = x.notes
    }

    private func save() {
        let x = injury ?? Injury()
        if injury == nil { x.uid = uid; context.insert(x) }
        x.title = title.trimmingCharacters(in: .whitespaces); x.bodyPart = bodyPart; x.date = date; x.howItHappened = how; x.severity = severity
        x.procedures = Self.procedureOptions.filter { procedures.contains($0) }; x.procedureNotes = procedureNotes
        x.doctorName = doctor; x.hospital = hospital; x.hospitalised = hospitalised
        x.admitDate = hospitalised ? admit : nil; x.dischargeDate = hospitalised && !stillAdmitted ? discharge : nil
        x.status = status; x.healedDate = status == "Healed" ? healed : nil; x.restrictions = restrictions; x.notes = notes
        MedicalMoney.retitle(owner: x.uid, title: "Injury: \(x.title)", in: context)
        try? context.save()
        Haptics.success()
        dismiss()
    }

    private func cancel() {
        if injury == nil {
            MedicalMoney.deleteAttachments(owner: uid, in: context)
            let id = uid
            ((try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.linkedUID == id }))) ?? []).forEach { $0.linkedUID = ""; $0.linkedKind = "" }
            try? context.save()
        }
        dismiss()
    }

    private func delete() {
        guard let x = injury else { return }
        MedicalMoney.deleteAttachments(owner: x.uid, in: context)
        let id = x.uid
        ((try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.linkedUID == id }))) ?? []).forEach { $0.linkedUID = ""; $0.linkedKind = "" }
        context.delete(x)
        try? context.save()
        dismiss()
    }
}

// MARK: - Major health events

struct HealthEventListView: View {
    @MemberQuery(sort: \HealthEvent.date, order: .reverse) private var events: [HealthEvent]
    @MemberQuery private var attachments: [MedicalAttachment]
    @State private var editing: HealthEvent?
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("No major health events", systemImage: "heart.text.square")
                    } description: {
                        Text("Keep a record of serious illnesses, operations and hospital stays: doctor, hospital, procedure, reports, photos, medicines and costs — all in one place.")
                    } actions: {
                        Button("Add a health event") { adding = true }.buttonStyle(.borderedProminent)
                    }
                    .glassCard()
                }
                ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                    let atts = attachments.filter { $0.ownerUID == e.uid }
                    let cost = atts.filter { $0.kind == "Bill" }.reduce(0) { $0 + $1.amount }
                    Button { editing = e } label: {
                        HStack(alignment: .top, spacing: 12) {
                            medicalThumb(atts, icon: HealthEventEditor.icon(e.kind), colors: [.purple, .indigo])
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(e.title).font(.headline); Spacer(); StatusChip(text: e.status) }
                                Text([e.kind, e.date.formatted(date: .abbreviated, time: .omitted)].joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                if !e.procedure.isEmpty { Text(e.procedure).font(.caption2).foregroundStyle(.tint).lineLimit(2) }
                                HStack(spacing: 10) {
                                    if !e.doctorName.isEmpty { Label("Dr. \(e.doctorName)", systemImage: "stethoscope") }
                                    if !e.hospital.isEmpty { Label(e.hospital, systemImage: "building.2.fill").lineLimit(1) }
                                    Spacer()
                                    if cost > 0 { Text(inr(cost)).font(.caption.bold()) }
                                }
                                .font(.caption2).foregroundStyle(.secondary)
                                if let f = e.followUp, f >= Calendar.current.startOfDay(for: .now) {
                                    Label("Follow-up \(f.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar.badge.clock").font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        }
                        .glassCard()
                    }
                    .buttonStyle(PressStyle())
                    .appear(min(i, 8))
                }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Major Health Events")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { HealthEventEditor(event: nil) }
        .sheet(item: $editing) { HealthEventEditor(event: $0) }
    }
}

struct HealthEventEditor: View {
    let event: HealthEvent?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var uid = UUID().uuidString
    @State private var title = ""
    @State private var kind = "Illness / disease"
    @State private var date = Date.now
    @State private var hasEnd = false
    @State private var endDate = Date.now
    @State private var diagnosis = ""
    @State private var procedure = ""
    @State private var doctor = ""
    @State private var specialty = ""
    @State private var hospital = ""
    @State private var hospitalised = false
    @State private var admit = Date.now
    @State private var discharge = Date.now
    @State private var stillAdmitted = false
    @State private var status = "Under treatment"
    @State private var hasFollowUp = false
    @State private var followUp = Date.now.addingTimeInterval(14 * 86400)
    @State private var notes = ""
    @State private var confirmDelete = false
    @State private var loaded = false

    static let kinds = ["Illness / disease", "Surgery / operation", "Injury", "Hospitalisation", "Other"]
    static func icon(_ k: String) -> String {
        switch k {
        case "Surgery / operation": "cross.case.fill"
        case "Injury": "bandage.fill"
        case "Hospitalisation": "bed.double.fill"
        default: "heart.text.square.fill"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Name (e.g. Appendix surgery, Dengue)", text: $title)
                    Picker("Type", selection: $kind) { ForEach(Self.kinds, id: \.self) { Label($0, systemImage: Self.icon($0)).tag($0) } }
                    DatePicker("Started / date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    Toggle("Has ended", isOn: $hasEnd)
                    if hasEnd { DatePicker("Ended", selection: $endDate, in: date..., displayedComponents: .date) }
                    Picker("Status", selection: $status) {
                        ForEach(["Under treatment", "Monitoring", "Recovered", "Ongoing / chronic"], id: \.self) { Text($0) }
                    }
                }
                Section("Medical details") {
                    TextField("Diagnosis", text: $diagnosis, axis: .vertical)
                    TextField("Procedure (e.g. laparoscopic appendectomy)", text: $procedure, axis: .vertical)
                    TextField("Doctor's name", text: $doctor)
                    TextField("Speciality (e.g. orthopaedic surgeon)", text: $specialty)
                    TextField("Hospital", text: $hospital)
                    HospitalStayFields(hospitalised: $hospitalised, admit: $admit, discharge: $discharge, stillAdmitted: $stillAdmitted)
                    Toggle("Follow-up appointment", isOn: $hasFollowUp)
                    if hasFollowUp { DatePicker("Follow-up", selection: $followUp, displayedComponents: [.date, .hourAndMinute]) }
                }
                AttachmentsSection(ownerUID: uid, ownerKind: "event", ownerTitle: "Health: \(title)")
                LinkedMedicinesSection(ownerUID: uid, ownerKind: "event", cause: title, doctor: doctor, hospital: hospital)
                Section("Notes") { TextField("Anything to remember — symptoms, advice, diet, restrictions", text: $notes, axis: .vertical) }
                if event != nil { Section { Button("Delete health event", role: .destructive) { confirmDelete = true } } }
            }
            .navigationTitle(event == nil ? "Add Health Event" : "Health Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .confirmationDialog("Delete this record with its reports, photos and bills? Linked medicines are kept.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
            .onAppear(perform: load)
            .interactiveDismissDisabled()
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let e = event else { return }
        uid = e.uid; title = e.title; kind = e.kind; date = e.date; hasEnd = e.endDate != nil; endDate = e.endDate ?? .now
        diagnosis = e.diagnosis; procedure = e.procedure; doctor = e.doctorName; specialty = e.specialty; hospital = e.hospital
        hospitalised = e.hospitalised; admit = e.admitDate ?? e.date; discharge = e.dischargeDate ?? .now
        stillAdmitted = e.hospitalised && e.dischargeDate == nil
        status = e.status; hasFollowUp = e.followUp != nil; followUp = e.followUp ?? followUp; notes = e.notes
    }

    private func save() {
        let e = event ?? HealthEvent()
        if event == nil { e.uid = uid; context.insert(e) }
        e.title = title.trimmingCharacters(in: .whitespaces); e.kind = kind; e.date = date; e.endDate = hasEnd ? endDate : nil
        e.diagnosis = diagnosis; e.procedure = procedure; e.doctorName = doctor; e.specialty = specialty; e.hospital = hospital
        e.hospitalised = hospitalised; e.admitDate = hospitalised ? admit : nil; e.dischargeDate = hospitalised && !stillAdmitted ? discharge : nil
        e.status = status; e.followUp = hasFollowUp ? followUp : nil; e.notes = notes
        MedicalMoney.retitle(owner: e.uid, title: "Health: \(e.title)", in: context)
        try? context.save()
        if hasFollowUp && followUp > .now {
            let c = UNMutableNotificationContent()
            c.title = "Follow-up: " + Member.prefix(e.memberUID) + e.title
            c.userInfo["member"] = e.memberUID
            c.body = [doctor.isEmpty ? nil : "Dr. \(doctor)", hospital.isEmpty ? nil : hospital].compactMap { $0 }.joined(separator: " · ")
            c.sound = .default
            let when = followUp.addingTimeInterval(-2 * 3600)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when > .now ? when : followUp)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "followup.\(e.uid)", content: c,
                                                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["followup.\(e.uid)"])
        }
        Haptics.success()
        dismiss()
    }

    private func cancel() {
        if event == nil {
            MedicalMoney.deleteAttachments(owner: uid, in: context)
            let id = uid
            ((try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.linkedUID == id }))) ?? []).forEach { $0.linkedUID = ""; $0.linkedKind = "" }
            try? context.save()
        }
        dismiss()
    }

    private func delete() {
        guard let e = event else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["followup.\(e.uid)"])
        MedicalMoney.deleteAttachments(owner: e.uid, in: context)
        let id = e.uid
        ((try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.linkedUID == id }))) ?? []).forEach { $0.linkedUID = ""; $0.linkedKind = "" }
        context.delete(e)
        try? context.save()
        dismiss()
    }
}

// MARK: - Medical card on the Health tab

struct MedicalHubCard: View {
    @MemberQuery private var meds: [Medication]
    @MemberQuery private var injuries: [Injury]
    @MemberQuery private var events: [HealthEvent]
    @MemberQuery private var attachments: [MedicalAttachment]

    var body: some View {
        let activeMeds = meds.filter(\.isCurrent).count
        let activeInj = injuries.filter { $0.status != "Healed" }.count
        let openEvents = events.filter { $0.status != "Recovered" }.count
        let spent = attachments.filter { $0.kind == "Bill" }.reduce(0) { $0 + $1.amount }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Medical").font(.headline)
                Spacer()
                if spent > 0 { Text("Bills \(inr(spent))").font(.caption).foregroundStyle(.secondary) }
            }
            row("Medicines", "cross.case.fill", .red, activeMeds > 0 ? "\(activeMeds) current" : "\(meds.count) total") { MedicineListView() }
            row("Injuries", "bandage.fill", .orange, activeInj > 0 ? "\(activeInj) healing" : "\(injuries.count) logged") { InjuryListView() }
            row("Major health events", "heart.text.square.fill", .purple, openEvents > 0 ? "\(openEvents) open" : "\(events.count) recorded") { HealthEventListView() }
        }
        .glassCard()
    }

    private func row<D: View>(_ title: String, _ icon: String, _ color: Color, _ detail: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(.white).frame(width: 36, height: 36).background(color.gradient, in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.subheadline.bold()).foregroundStyle(Color.primary)
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
