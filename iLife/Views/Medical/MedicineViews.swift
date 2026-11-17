import SwiftUI
import SwiftData

// MARK: - Today's medicines (Health tab)

struct MedicinesTodayCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.name) private var meds: [Medication]
    @Query private var doses: [MedicationDose]
    @State private var editing: Medication?

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var due: [Medication] { meds.filter { $0.isDue(on: today) } }

    private func taken(_ m: Medication, _ slot: DoseSlot) -> MedicationDose? {
        doses.first { $0.medicationUID == m.uid && $0.slot == slot.rawValue && Calendar.current.isDate($0.day, inSameDayAs: today) }
    }

    var body: some View {
        if !due.isEmpty {
            let total = due.reduce(0) { $0 + $1.doseSlots.count }
            let done = due.reduce(0) { sum, m in sum + m.doseSlots.filter { taken(m, $0) != nil }.count }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Medicines today", systemImage: "cross.case.fill").font(.headline)
                    Spacer()
                    Text("\(done) / \(total)").font(.caption.bold()).foregroundStyle(done == total ? Color.green : Color.orange)
                }
                ForEach(due) { m in
                    VStack(alignment: .leading, spacing: 6) {
                        Button { editing = m } label: {
                            HStack(spacing: 10) {
                                ItemThumbnail(photo: m.photo, illustration: Illustration(symbol: m.form.icon, colors: [.red, .pink]), size: 40, corner: 10)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(m.displayName).font(.subheadline.bold())
                                    Text([m.dose, m.cause].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        ForEach(m.doseSlots) { slot in
                            let d = taken(m, slot)
                            Button { toggle(m, slot, d) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: d != nil ? "checkmark.circle.fill" : "circle").font(.title3)
                                        .foregroundStyle(d != nil ? Color.green : Color.secondary).contentTransition(.symbolEffect(.replace))
                                    Text(slot.rawValue).font(.subheadline).strikethrough(d != nil, color: .secondary)
                                    Spacer()
                                    if let d { Text(d.takenAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .glassCard()
            .sheet(item: $editing) { MedicineEditor(medication: $0) }
        }
    }

    private func toggle(_ m: Medication, _ slot: DoseSlot, _ existing: MedicationDose?) {
        if let existing { context.delete(existing); Haptics.tap() }
        else { context.insert(MedicationDose(medicationUID: m.uid, slot: slot.rawValue, day: today)); Haptics.success() }
        try? context.save()
    }
}

// MARK: - All medicines

struct MedicineListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.startDate, order: .reverse) private var meds: [Medication]
    @Query private var doses: [MedicationDose]
    @State private var editing: Medication?
    @State private var adding = false

    private func progress(_ m: Medication) -> (taken: Int, planned: Int) {
        let cal = Calendar.current
        var planned = 0
        var d = cal.startOfDay(for: m.startDate)
        let today = cal.startOfDay(for: .now)
        var n = 0
        while d <= today && n < 800 {
            if m.isDue(on: d) { planned += m.doseSlots.count }
            d = cal.date(byAdding: .day, value: 1, to: d)!; n += 1
        }
        return (doses.filter { $0.medicationUID == m.uid }.count, planned)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if meds.isEmpty {
                    ContentUnavailableView {
                        Label("No medicines", systemImage: "cross.case")
                    } description: {
                        Text("Add a prescribed medicine with its cause, doctor, schedule, prescription and bill. iLife reminds you and tracks every dose.")
                    } actions: {
                        Button("Add medicine") { adding = true }.buttonStyle(.borderedProminent)
                    }
                    .glassCard()
                }
                section("Current", meds.filter { !$0.isFinished && !$0.isPaused })
                section("Paused", meds.filter { $0.isPaused && !$0.isFinished })
                section("Completed", meds.filter(\.isFinished))
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Medicines")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { MedicineEditor(medication: nil) }
        .sheet(item: $editing) { MedicineEditor(medication: $0) }
        .task { MedicationReminders.syncAll(meds) }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Medication]) -> some View {
        if !items.isEmpty {
            Text(title).font(.headline)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                let p = progress(m)
                Button { editing = m } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            ItemThumbnail(photo: m.photo, illustration: Illustration(symbol: m.form.icon, colors: [.red, .pink]), size: 58, corner: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.displayName).font(.headline)
                                Text([m.form.rawValue, m.company].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                Text((m.dose.isEmpty ? "" : m.dose + " — ") + m.scheduleText).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        Text(m.doseSlots.map(\.rawValue).joined(separator: " · ")).font(.caption2).foregroundStyle(.tint)
                        HStack {
                            if !m.cause.isEmpty { Label(m.cause, systemImage: "stethoscope") }
                            Spacer()
                            if !m.doctorName.isEmpty { Text("Dr. \(m.doctorName)") }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                        if p.planned > 0 {
                            ProgressView(value: Double(min(p.taken, p.planned)), total: Double(p.planned)).tint(p.taken >= p.planned ? .green : .orange)
                            Text("\(p.taken) of \(p.planned) doses taken").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .glassCard()
                }
                .buttonStyle(PressStyle())
                .appear(min(i, 8))
            }
        }
    }
}

// MARK: - Editor

struct MedicineEditor: View {
    let medication: Medication?
    var linkUID: String = ""
    var linkKind: String = ""
    var presetCause: String = ""
    var presetDoctor: String = ""
    var presetHospital: String = ""

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Injury.date, order: .reverse) private var injuries: [Injury]
    @Query(sort: \HealthEvent.date, order: .reverse) private var events: [HealthEvent]

    @State private var uid = UUID().uuidString
    @State private var name = ""
    @State private var company = ""
    @State private var strength = ""
    @State private var form: MedForm = .tablet
    @State private var dose = ""
    @State private var slots: [DoseSlot] = [.afterBreakfast]
    @State private var everyDay = true
    @State private var weekdays: Set<Int> = []
    @State private var start = Date.now
    @State private var ongoing = false
    @State private var weeks = 1
    @State private var days = 7
    @State private var inDays = true
    @State private var cause = ""
    @State private var doctor = ""
    @State private var doctorPhone = ""
    @State private var hospital = ""
    @State private var instructions = ""
    @State private var notes = ""
    @State private var remind = true
    @State private var paused = false
    @State private var photo: Data?
    @State private var link = ""        // "injury:uid" / "event:uid" / ""
    @State private var confirmDelete = false
    @State private var saved = false

    private var weeksValue: Int { ongoing ? 0 : (inDays ? 0 : weeks) }
    private var daysValue: Int { !ongoing && inDays ? days : 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ItemThumbnail(photo: photo, illustration: Illustration(symbol: form.icon, colors: [.red, .pink]), size: 76, corner: 14)
                        VStack(alignment: .leading, spacing: 6) {
                            PhotoSourceButton(onPick: { photo = ImageTools.jpeg($0, maxSide: 1200) }) {
                                Label(photo == nil ? "Photo of the medicine" : "Change photo", systemImage: "camera.fill")
                            }
                            if photo != nil { Button("Remove", role: .destructive) { photo = nil }.font(.caption) }
                        }
                    }
                    Text(summary).font(.callout).foregroundStyle(.tint)
                }

                Section("Medicine") {
                    TextField("Name (e.g. Augmentin, Pan-D)", text: $name)
                    TextField("Strength (e.g. 625 mg, 40 mg)", text: $strength)
                    TextField("Company / brand", text: $company)
                    Picker("Type", selection: $form) { ForEach(MedForm.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) } }
                    TextField(form == .syrup ? "Dose each time (e.g. 5 ml, 1 spoon)" : form == .injection ? "Dose (e.g. 1 injection, 2 ml)" : "Dose each time (e.g. 1 tablet)", text: $dose)
                    TextField("Instructions (e.g. after food, with water)", text: $instructions)
                }

                Section("Prescribed for") {
                    TextField("Cause / condition (e.g. throat infection)", text: $cause)
                    TextField("Doctor's name", text: $doctor)
                    TextField("Doctor's phone (optional)", text: $doctorPhone).keyboardType(.phonePad)
                    TextField("Hospital / clinic", text: $hospital)
                    Picker("Linked to", selection: $link) {
                        Text("Nothing").tag("")
                        ForEach(injuries) { Text("Injury: \($0.title)").tag("injury:\($0.uid)") }
                        ForEach(events) { Text("Health event: \($0.title)").tag("event:\($0.uid)") }
                    }
                }

                Section {
                    Stepper("Times a day: \(slots.count)", value: Binding(get: { slots.count }, set: { setCount($0) }), in: 1...6)
                    ForEach(slots.indices, id: \.self) { i in
                        Picker(slots.count == 1 ? "When" : "Time \(i + 1)", selection: Binding(get: { i < slots.count ? slots[i] : .afterLunch },
                                                                                         set: { if i < slots.count { slots[i] = $0 } })) {
                            ForEach(DoseSlot.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                        }
                    }
                    if Set(slots).count != slots.count { Text("Pick a different time for each dose.").font(.caption).foregroundStyle(.orange) }
                    Toggle("Every day", isOn: $everyDay.animation())
                    if !everyDay {
                        HStack {
                            ForEach(1...7, id: \.self) { d in
                                let on = weekdays.contains(d)
                                Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) { if on { weekdays.remove(d) } else { weekdays.insert(d) } }
                                    .font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 34)
                                    .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.gray.opacity(0.2)), in: Circle())
                                    .foregroundStyle(on ? Color.white : Color.primary).buttonStyle(.plain)
                            }
                        }
                    }
                } header: { Text("Schedule") }

                Section("Course") {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    Toggle("Ongoing (no end date)", isOn: $ongoing.animation())
                    if !ongoing {
                        Picker("Count in", selection: $inDays) { Text("Days").tag(true); Text("Weeks").tag(false) }.pickerStyle(.segmented)
                        if inDays { Stepper("For \(days) day\(days == 1 ? "" : "s")", value: $days, in: 1...365) }
                        else { Stepper("For \(weeks) week\(weeks == 1 ? "" : "s")", value: $weeks, in: 1...104) }
                    }
                    Toggle("Remind me at each dose", isOn: $remind)
                    if medication != nil { Toggle("Paused", isOn: $paused) }
                }

                AttachmentsSection(ownerUID: uid, ownerKind: "medication", ownerTitle: "Medicine: \(name)",
                                   kinds: ["Prescription", "Bill", "Photo", "Report", "Other"], header: "Prescription & bills")

                Section("Notes") { TextField("Side effects, how you feel, anything else", text: $notes, axis: .vertical) }

                if medication != nil { Section { Button("Delete medicine", role: .destructive) { confirmDelete = true } } }

                Section {
                    Text("iLife tracks what your doctor prescribed. Always follow your doctor's or pharmacist's instructions on dose and duration.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(medication == nil ? "Add Medicine" : "Medicine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (!everyDay && weekdays.isEmpty) || Set(slots).count != slots.count)
                }
            }
            .confirmationDialog("Delete this medicine, its dose history, prescription and bills?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
            .onAppear(perform: load)
            .interactiveDismissDisabled()
        }
    }

    private var summary: String {
        var text = Supplement.scheduleText(timesPerDay: slots.count, weekdays: everyDay ? [] : weekdays.sorted(), weeks: weeksValue)
        if daysValue > 0 { text = text.replacingOccurrences(of: ", ongoing", with: "") + " for \(daysValue) day\(daysValue == 1 ? "" : "s")" }
        let what = [name.isEmpty ? "Medicine" : name, strength, dose].filter { !$0.isEmpty }.joined(separator: " ")
        return "\(what): \(text)."
    }

    private func setCount(_ n: Int) {
        let defaults: [DoseSlot] = [.afterBreakfast, .afterDinner, .afterLunch, .bedtime, .beforeBreakfast, .afterSnack]
        while slots.count < n { slots.append(defaults.first { !slots.contains($0) } ?? .afterLunch) }
        while slots.count > n { slots.removeLast() }
    }

    private func load() {
        guard !saved else { return }
        if let m = medication {
            guard name.isEmpty else { return }
            uid = m.uid; name = m.name; company = m.company; strength = m.strength; form = m.form; dose = m.dose
            slots = m.slots.compactMap(DoseSlot.init(rawValue:)); if slots.isEmpty { slots = [.afterBreakfast] }
            everyDay = m.weekdays.isEmpty || m.weekdays.count == 7; weekdays = Set(m.weekdays)
            start = m.startDate; ongoing = m.weeks == 0 && m.courseDays == 0; weeks = max(1, m.weeks)
            inDays = m.courseDays > 0; days = m.courseDays > 0 ? m.courseDays : 7
            cause = m.cause; doctor = m.doctorName; doctorPhone = m.doctorPhone; hospital = m.hospital
            instructions = m.instructions; notes = m.notes; remind = m.remind; paused = m.isPaused; photo = m.photo
            link = m.linkedUID.isEmpty ? "" : "\(m.linkedKind):\(m.linkedUID)"
        } else {
            if cause.isEmpty { cause = presetCause }
            if doctor.isEmpty { doctor = presetDoctor }
            if hospital.isEmpty { hospital = presetHospital }
            if link.isEmpty && !linkUID.isEmpty { link = "\(linkKind):\(linkUID)" }
        }
    }

    private func save() {
        let m = medication ?? Medication()
        if medication == nil { m.uid = uid; context.insert(m) }
        m.name = name.trimmingCharacters(in: .whitespaces); m.company = company; m.strength = strength; m.form = form; m.dose = dose
        m.slots = slots.map(\.rawValue); m.weekdays = everyDay ? [] : weekdays.sorted()
        m.startDate = start; m.weeks = weeksValue; m.courseDays = daysValue
        m.cause = cause; m.doctorName = doctor; m.doctorPhone = doctorPhone; m.hospital = hospital
        m.instructions = instructions; m.notes = notes; m.remind = remind; m.isPaused = paused; m.photo = photo
        let parts = link.split(separator: ":", maxSplits: 1).map(String.init)
        m.linkedKind = parts.count == 2 ? parts[0] : ""; m.linkedUID = parts.count == 2 ? parts[1] : ""
        MedicalMoney.retitle(owner: m.uid, title: "Medicine: \(m.name)", in: context)
        try? context.save()
        saved = true
        if remind { Task { await NotificationService.requestAuthorization(); MedicationReminders.schedule(m) } } else { MedicationReminders.cancel(m.uid) }
        Haptics.success()
        dismiss()
    }

    /// A new medicine that is cancelled shouldn't leave its attachments behind.
    private func cancel() {
        if medication == nil { MedicalMoney.deleteAttachments(owner: uid, in: context); try? context.save() }
        dismiss()
    }

    private func delete() {
        guard let m = medication else { return }
        MedicationReminders.cancel(m.uid)
        let id = m.uid
        ((try? context.fetch(FetchDescriptor<MedicationDose>(predicate: #Predicate { $0.medicationUID == id }))) ?? []).forEach { context.delete($0) }
        MedicalMoney.deleteAttachments(owner: id, in: context)
        context.delete(m)
        try? context.save()
        dismiss()
    }
}
