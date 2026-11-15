import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Reminders

enum SupplementReminders {
    private static func ids(for uid: String) -> [String] {
        var out: [String] = []
        for slot in DoseSlot.allCases { for day in 0...7 { out.append("supp.\(uid).\(slot.order).\(day)") } }
        return out
    }

    static func cancel(_ uid: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids(for: uid))
    }

    /// Re-creates the repeating reminders for one supplement (or removes them if it's paused, finished or reminders are off).
    static func schedule(_ s: Supplement) {
        cancel(s.uid)
        guard s.remind, s.isCurrent else { return }
        let center = UNUserNotificationCenter.current()
        let days = s.weekdays.isEmpty || s.weekdays.count == 7 ? [0] : s.weekdays
        for slot in s.doseSlots {
            let content = UNMutableNotificationContent()
            content.title = "\(s.name)\(s.dose.isEmpty ? "" : " · \(s.dose)")"
            content.body = "\(slot.rawValue). Tap to tick it off in iLife."
            content.sound = .default
            for day in days {
                var comps = DateComponents()
                comps.hour = slot.time.hour
                comps.minute = slot.time.minute
                if day > 0 { comps.weekday = day }
                center.add(UNNotificationRequest(identifier: "supp.\(s.uid).\(slot.order).\(day)", content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
            }
        }
    }

    /// Keeps reminders in step with the list — in particular, stops them once a course has ended.
    static func syncAll(_ all: [Supplement]) {
        for s in all {
            if s.remind && s.isCurrent { schedule(s) } else { cancel(s.uid) }
        }
    }
}

// MARK: - Card on the Nutrition screen

struct SupplementsCard: View {
    let day: Date
    @Environment(\.modelContext) private var context
    @Query(sort: \Supplement.name) private var supplements: [Supplement]
    @Query private var doses: [SupplementDose]
    @State private var editing: Supplement?
    @State private var adding = false

    private var dayStart: Date { Calendar.current.startOfDay(for: day) }
    private var due: [Supplement] { supplements.filter { $0.isDue(on: day) } }
    private var active: [Supplement] { supplements.filter { !$0.isFinished } }

    private func taken(_ s: Supplement, _ slot: DoseSlot) -> SupplementDose? {
        doses.first { $0.supplementUID == s.uid && $0.slot == slot.rawValue && Calendar.current.isDate($0.day, inSameDayAs: dayStart) }
    }

    var body: some View {
        let total = due.reduce(0) { $0 + $1.doseSlots.count }
        let done = due.reduce(0) { sum, s in sum + s.doseSlots.filter { taken(s, $0) != nil }.count }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Supplements", systemImage: "pills.fill").font(.headline)
                Spacer()
                if total > 0 { Text("\(done) / \(total) taken").font(.caption).foregroundStyle(done == total ? Color.green : Color.secondary) }
                Button { adding = true } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.tint) }
                    .buttonStyle(PressStyle())
            }

            if supplements.isEmpty {
                Text("Add what you take — fish oil, shilajit, whey, vitamins — with the days, times and how many weeks. iLife reminds you and tracks each dose.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if due.isEmpty {
                Text(active.isEmpty ? "No active supplements." : "Nothing scheduled for this day.").font(.caption).foregroundStyle(.secondary)
            }

            ForEach(due) { s in
                VStack(alignment: .leading, spacing: 8) {
                    Button { editing = s } label: {
                        HStack(spacing: 12) {
                            ItemThumbnail(photo: s.photo, illustration: Illustration(symbol: "pills.fill", colors: [.teal, .green]), size: 46, corner: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.subheadline.bold())
                                Text([s.dose, s.company].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                                Text(s.weeks > 0 ? "Week \(min(s.currentWeek, s.weeks)) of \(s.weeks)" : "Ongoing").font(.caption2).foregroundStyle(.tint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    ForEach(s.doseSlots) { slot in
                        let dose = taken(s, slot)
                        Button { toggle(s, slot, dose) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: dose != nil ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(dose != nil ? Color.green : Color.secondary)
                                    .contentTransition(.symbolEffect(.replace))
                                Image(systemName: slot.icon).font(.caption).foregroundStyle(.secondary).frame(width: 18)
                                Text(slot.rawValue).font(.subheadline).strikethrough(dose != nil, color: .secondary)
                                Spacer()
                                if let dose { Text(dose.takenAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if !supplements.isEmpty {
                NavigationLink { SupplementListView() } label: {
                    Label("All supplements (\(supplements.count))", systemImage: "list.bullet").font(.caption.bold())
                }
            }
        }
        .glassCard()
        .sheet(isPresented: $adding) { SupplementEditor(supplement: nil) }
        .sheet(item: $editing) { SupplementEditor(supplement: $0) }
        .task { SupplementReminders.syncAll(supplements) }
    }

    private func toggle(_ s: Supplement, _ slot: DoseSlot, _ existing: SupplementDose?) {
        if let existing {
            context.delete(existing)
            Haptics.tap()
        } else {
            context.insert(SupplementDose(supplementUID: s.uid, slot: slot.rawValue, day: dayStart))
            Haptics.success()
        }
        try? context.save()
    }
}

// MARK: - Full list

struct SupplementListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Supplement.startDate, order: .reverse) private var supplements: [Supplement]
    @Query private var doses: [SupplementDose]
    @State private var editing: Supplement?
    @State private var adding = false

    /// Doses that should have been taken from the start until today, and how many were ticked.
    private func progress(_ s: Supplement) -> (taken: Int, planned: Int) {
        let cal = Calendar.current
        var planned = 0
        var d = cal.startOfDay(for: s.startDate)
        let today = cal.startOfDay(for: .now)
        var guardCount = 0
        while d <= today && guardCount < 800 {
            if s.isDue(on: d) { planned += s.doseSlots.count }
            d = cal.date(byAdding: .day, value: 1, to: d)!
            guardCount += 1
        }
        return (doses.filter { $0.supplementUID == s.uid }.count, planned)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if supplements.isEmpty {
                    ContentUnavailableView("No supplements yet", systemImage: "pills", description: Text("Tap + to add your first one."))
                        .glassCard()
                }
                section("Current", supplements.filter { !$0.isFinished && !$0.isPaused })
                section("Paused", supplements.filter { $0.isPaused && !$0.isFinished })
                section("Completed", supplements.filter(\.isFinished))
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Supplements")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { SupplementEditor(supplement: nil) }
        .sheet(item: $editing) { SupplementEditor(supplement: $0) }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Supplement]) -> some View {
        if !items.isEmpty {
            Text(title).font(.headline)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                let p = progress(s)
                Button { editing = s } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            ItemThumbnail(photo: s.photo, illustration: Illustration(symbol: "pills.fill", colors: [.teal, .green]), size: 60, corner: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.name).font(.headline)
                                if !s.company.isEmpty { Text(s.company).font(.caption).foregroundStyle(.secondary) }
                                Text((s.dose.isEmpty ? "" : s.dose + " — ") + s.scheduleText).font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        Text(s.doseSlots.map(\.rawValue).joined(separator: " · ")).font(.caption2).foregroundStyle(.tint)
                        HStack {
                            Label(s.suggestedBy + (s.suggestedByName.isEmpty ? "" : " — \(s.suggestedByName)"), systemImage: "person.fill.checkmark")
                            Spacer()
                            if let end = s.endDate { Text((s.isFinished ? "Ended " : "Until ") + end.addingTimeInterval(-86400).formatted(date: .abbreviated, time: .omitted)) }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                        if p.planned > 0 {
                            ProgressView(value: Double(min(p.taken, p.planned)), total: Double(p.planned)).tint(.green)
                            Text("\(p.taken) of \(p.planned) doses taken so far").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .glassCard()
                }
                .buttonStyle(PressStyle())
                .appear(i)
            }
        }
    }
}

// MARK: - Editor

struct SupplementEditor: View {
    let supplement: Supplement?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trainer.firstName) private var trainers: [Trainer]

    @State private var name = ""
    @State private var company = ""
    @State private var dose = ""
    @State private var slots: [DoseSlot] = [.afterBreakfast]
    @State private var everyDay = true
    @State private var weekdays: Set<Int> = []
    @State private var start = Date.now
    @State private var ongoing = false
    @State private var weeks = 4
    @State private var suggestedBy = "Self"
    @State private var suggestedByName = ""
    @State private var purpose = ""
    @State private var notes = ""
    @State private var remind = true
    @State private var paused = false
    @State private var photo: Data?
    @State private var confirmDelete = false

    private let defaults: [DoseSlot] = [.afterBreakfast, .afterDinner, .afterLunch, .bedtime, .beforeBreakfast, .afterSnack]
    private let quickNames = ["Fish Oil / Omega-3", "Shilajit", "Multivitamin", "Vitamin D3", "Vitamin B12", "Creatine", "Whey Protein",
                              "Ashwagandha", "Magnesium", "Zinc", "Calcium", "Iron", "Probiotic", "Collagen", "BCAA", "Pre-Workout"]

    /// The plain-English sentence for what's set up, shown live at the top.
    private var summary: String {
        let text = Supplement.scheduleText(timesPerDay: slots.count, weekdays: everyDay ? [] : weekdays.sorted(), weeks: ongoing ? 0 : weeks)
        let what = [name.isEmpty ? "Supplement" : name, dose].filter { !$0.isEmpty }.joined(separator: ", ")
        return "\(what): \(text)."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ItemThumbnail(photo: photo, illustration: Illustration(symbol: "pills.fill", colors: [.teal, .green]), size: 76, corner: 14)
                        VStack(alignment: .leading, spacing: 6) {
                            PhotoSourceButton(onPick: { photo = ImageTools.jpeg($0, maxSide: 1200) }) {
                                Label(photo == nil ? "Add product photo" : "Change photo", systemImage: "camera.fill")
                            }
                            if photo != nil { Button("Remove", role: .destructive) { photo = nil }.font(.caption) }
                        }
                    }
                    Text(summary).font(.callout).foregroundStyle(.tint)
                }

                Section("Supplement") {
                    TextField("Name (e.g. Fish Oil, Shilajit)", text: $name)
                    if name.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(quickNames, id: \.self) { n in Button(n) { name = n }.font(.caption).buttonStyle(.bordered) } }
                        }
                    }
                    TextField("Company / brand", text: $company)
                    TextField("How much each time (e.g. 1 tablet, 1 spoon)", text: $dose)
                }

                Section {
                    Stepper("Times a day: \(slots.count)", value: Binding(get: { slots.count }, set: { setCount($0) }), in: 1...6)
                    ForEach(slots.indices, id: \.self) { i in
                        Picker(slots.count == 1 ? "When" : "Time \(i + 1)", selection: Binding(
                            get: { i < slots.count ? slots[i] : .afterLunch },
                            set: { if i < slots.count { slots[i] = $0 } })) {
                            ForEach(DoseSlot.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                        }
                    }
                    if hasDuplicateTimes {
                        Text("Two times are the same — pick a different time for each.").font(.caption).foregroundStyle(.orange)
                    }
                } header: {
                    Text("When in the day")
                }

                Section("Which days") {
                    Toggle("Every day", isOn: $everyDay.animation())
                    if !everyDay {
                        HStack {
                            ForEach(1...7, id: \.self) { d in
                                let on = weekdays.contains(d)
                                Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) {
                                    if on { weekdays.remove(d) } else { weekdays.insert(d) }
                                }
                                .font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 36)
                                .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.gray.opacity(0.2)), in: Circle())
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .buttonStyle(.plain)
                            }
                        }
                        Text("\(weekdays.count) day\(weekdays.count == 1 ? "" : "s") a week").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("How long") {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    Toggle("Ongoing (no end date)", isOn: $ongoing.animation())
                    if !ongoing {
                        Stepper("For \(weeks) week\(weeks == 1 ? "" : "s")", value: $weeks, in: 1...104)
                        if let end = Calendar.current.date(byAdding: .day, value: weeks * 7 - 1, to: start) {
                            Text("Last day: \(end.formatted(date: .complete, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Suggested by") {
                    Picker("Suggested by", selection: $suggestedBy) {
                        ForEach(["Self", "Doctor", "Trainer", "Dietitian / Nutritionist", "Ayurvedic doctor", "Friend / Family", "Other"], id: \.self) { Text($0) }
                    }
                    if suggestedBy != "Self" {
                        TextField("Their name (optional)", text: $suggestedByName)
                        if suggestedBy == "Trainer" && !trainers.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack { ForEach(trainers) { t in Button(t.fullName) { suggestedByName = t.fullName }.font(.caption).buttonStyle(.bordered) } }
                            }
                        }
                    }
                    TextField("What it's for (e.g. joints, energy, recovery)", text: $purpose)
                }

                Section {
                    Toggle("Remind me at each time", isOn: $remind)
                    if supplement != nil { Toggle("Pause this supplement", isOn: $paused) }
                    TextField("Notes (e.g. with warm milk, not with tea)", text: $notes, axis: .vertical)
                } footer: {
                    Text("Reminders use usual meal times (for example, after breakfast is 9:00 am). This is a tracker — follow your doctor's advice on what to take and how much.")
                }

                if supplement != nil {
                    Section { Button("Delete supplement", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(supplement == nil ? "Add Supplement" : "Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (!everyDay && weekdays.isEmpty) || hasDuplicateTimes)
                }
            }
            .confirmationDialog("Delete this supplement and its history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
            .onAppear(perform: load)
        }
    }

    private var hasDuplicateTimes: Bool { Set(slots).count != slots.count }

    private func setCount(_ n: Int) {
        while slots.count < n { slots.append(defaults.first { !slots.contains($0) } ?? .afterLunch) }
        while slots.count > n { slots.removeLast() }
    }

    private func load() {
        guard let s = supplement, name.isEmpty else { return }
        name = s.name; company = s.company; dose = s.dose
        slots = s.slots.compactMap(DoseSlot.init(rawValue:)); if slots.isEmpty { slots = [.afterBreakfast] }
        everyDay = s.weekdays.isEmpty || s.weekdays.count == 7; weekdays = Set(s.weekdays)
        start = s.startDate; ongoing = s.weeks == 0; weeks = s.weeks == 0 ? 4 : s.weeks
        suggestedBy = s.suggestedBy; suggestedByName = s.suggestedByName; purpose = s.purpose; notes = s.notes
        remind = s.remind; paused = s.isPaused; photo = s.photo
    }

    private func save() {
        let s = supplement ?? Supplement()
        if supplement == nil { context.insert(s) }
        s.name = name.trimmingCharacters(in: .whitespaces); s.company = company; s.dose = dose
        s.slots = slots.map(\.rawValue)
        s.weekdays = everyDay ? [] : weekdays.sorted()
        s.startDate = start; s.weeks = ongoing ? 0 : weeks
        s.suggestedBy = suggestedBy; s.suggestedByName = suggestedBy == "Self" ? "" : suggestedByName
        s.purpose = purpose; s.notes = notes; s.remind = remind; s.isPaused = paused; s.photo = photo
        try? context.save()
        if remind { Task { await NotificationService.requestAuthorization(); SupplementReminders.schedule(s) } }
        else { SupplementReminders.cancel(s.uid) }
        Haptics.success()
        dismiss()
    }

    private func delete() {
        guard let s = supplement else { return }
        SupplementReminders.cancel(s.uid)
        let uid = s.uid
        let old = (try? context.fetch(FetchDescriptor<SupplementDose>(predicate: #Predicate { $0.supplementUID == uid }))) ?? []
        old.forEach { context.delete($0) }
        context.delete(s)
        try? context.save()
        dismiss()
    }
}
