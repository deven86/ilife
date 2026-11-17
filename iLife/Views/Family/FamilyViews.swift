import SwiftUI
import SwiftData

// MARK: - Banner shown on every screen while viewing a family member

struct ViewingMemberBanner: View {
    var onTap: () -> Void
    @Query private var profiles: [HealthProfile]
    var body: some View {
        let p = profiles.first { $0.memberUID == Member.current }
        Button(action: onTap) {
            HStack(spacing: 8) {
                AvatarView(data: p?.avatar, name: p?.fullName ?? "?", size: 24)
                Text("Viewing \(p?.firstName.isEmpty == false ? p!.firstName : (p?.relation ?? "member"))").font(.footnote.bold())
                if let r = p?.relation, !r.isEmpty, p?.firstName.isEmpty == false { Text(r).font(.caption2).foregroundStyle(.white.opacity(0.85)) }
                Spacer()
                Text("Switch").font(.caption.bold())
                Image(systemName: "chevron.down").font(.caption2.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick switcher

struct MemberPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HealthProfile.memberOrder) private var profiles: [HealthProfile]
    @ObservedObject private var store = MemberStore.shared
    @AppStorage("userName") private var userName = "Devendra"
    @State private var adding = false

    private var me: HealthProfile? { profiles.first { $0.memberUID.isEmpty } }
    private var family: [HealthProfile] { profiles.filter { !$0.memberUID.isEmpty } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(uid: "", avatar: me?.avatar, name: (me?.fullName.isEmpty == false ? me!.fullName : userName), detail: "You")
                    ForEach(family) { p in
                        row(uid: p.memberUID, avatar: p.avatar, name: p.fullName.isEmpty ? p.relation : p.fullName, detail: FamilyData.subtitle(p))
                    }
                } footer: {
                    Text("Everything you log — food, workouts, medicines, reports, injuries, expenses — is saved for the person selected here.")
                }
                Section {
                    Button("Add family member", systemImage: "person.crop.circle.badge.plus") { adding = true }
                    NavigationLink { FamilyView() } label: { Label("Manage family", systemImage: "person.3.fill") }
                }
            }
            .navigationTitle("Who are you logging for?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $adding) { MemberEditor(profile: nil) { uid in store.switchTo(uid); dismiss() } }
        }
    }

    private func row(uid: String, avatar: Data?, name: String, detail: String) -> some View {
        Button {
            store.switchTo(uid)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                AvatarView(data: avatar, name: name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).foregroundStyle(Color.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.uid == uid { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.tint) }
            }
        }
    }
}

// MARK: - Family overview

struct FamilyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HealthProfile.memberOrder) private var profiles: [HealthProfile]
    @Query private var meds: [Medication]
    @Query private var injuries: [Injury]
    @Query private var events: [HealthEvent]
    @Query private var expenses: [Expense]
    @ObservedObject private var store = MemberStore.shared
    @State private var editing: HealthProfile?
    @State private var adding = false

    private var family: [HealthProfile] { profiles.filter { !$0.memberUID.isEmpty } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if family.isEmpty {
                    ContentUnavailableView {
                        Label("Add your family", systemImage: "person.3.fill")
                    } description: {
                        Text("Track your wife, children, parents, siblings and other relatives — their food, workouts, medicines, reports, injuries, health events and expenses, each kept separately.")
                    } actions: {
                        Button("Add family member") { adding = true }.buttonStyle(.borderedProminent)
                    }
                    .glassCard()
                }
                ForEach(Array(family.enumerated()), id: \.element.id) { i, p in
                    card(p).appear(min(i, 8))
                }
                if !family.isEmpty {
                    let year = Calendar.current.dateInterval(of: .year, for: .now)!
                    let yearSpend = expenses.filter { year.contains($0.date) }.reduce(0) { $0 + $1.amount }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Whole family this year").font(.headline)
                        HStack {
                            Text("All expenses"); Spacer(); Text(inr(yearSpend)).bold()
                        }
                        .font(.subheadline)
                        ForEach([""] + family.map(\.memberUID), id: \.self) { uid in
                            let v = expenses.filter { $0.memberUID == uid && year.contains($0.date) }.reduce(0) { $0 + $1.amount }
                            if v > 0 {
                                HStack { Text(uid.isEmpty ? "You" : name(uid)).foregroundStyle(.secondary); Spacer(); Text(inr(v)) }.font(.caption)
                            }
                        }
                    }
                    .glassCard()
                }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Family")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { MemberEditor(profile: nil) }
        .sheet(item: $editing) { MemberEditor(profile: $0) }
        .onAppear { Member.cacheNames(profiles) }
    }

    private func name(_ uid: String) -> String {
        guard let p = profiles.first(where: { $0.memberUID == uid }) else { return "Member" }
        return p.firstName.isEmpty ? p.relation : p.firstName
    }

    private func card(_ p: HealthProfile) -> some View {
        let uid = p.memberUID
        let activeMeds = meds.filter { $0.memberUID == uid && $0.isCurrent }.count
        let openInj = injuries.filter { $0.memberUID == uid && $0.status != "Healed" }.count
        let openEv = events.filter { $0.memberUID == uid && $0.status != "Recovered" }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(data: p.avatar, name: p.fullName.isEmpty ? p.relation : p.fullName, size: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.fullName.isEmpty ? p.relation : p.fullName).font(.headline)
                    Text(FamilyData.subtitle(p)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit") { editing = p }.buttonStyle(.bordered).controlSize(.small)
            }
            if !p.allergies.trimmingCharacters(in: .whitespaces).isEmpty {
                Label("Allergies: \(p.allergies)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold()).foregroundStyle(.red)
            }
            if !p.conditions.trimmingCharacters(in: .whitespaces).isEmpty {
                Label(p.conditions, systemImage: "heart.text.square").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 14) {
                if activeMeds > 0 { Label("\(activeMeds) medicine\(activeMeds == 1 ? "" : "s")", systemImage: "pills.fill") }
                if openInj > 0 { Label("\(openInj) injury", systemImage: "bandage.fill") }
                if openEv > 0 { Label("\(openEv) health", systemImage: "cross.case.fill") }
                Spacer()
                Button(store.uid == uid ? "Viewing" : "Open \(p.firstName.isEmpty ? p.relation : p.firstName)") { store.switchTo(uid) }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(store.uid == uid)
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .glassCard()
    }
}

// MARK: - Add / edit a member

struct MemberEditor: View {
    let profile: HealthProfile?
    var onCreated: ((String) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allProfiles: [HealthProfile]

    @State private var avatar: Data?
    @State private var first = ""
    @State private var last = ""
    @State private var relation = "Wife"
    @State private var customRelation = ""
    @State private var gender = ""
    @State private var ageOnly = false
    @State private var dob = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
    @State private var hasDOB = true
    @State private var age = 30
    @State private var blood = ""
    @State private var height: Double = 0
    @State private var weight: Double = 0
    @State private var allergies = ""
    @State private var conditions = ""
    @State private var phone = ""
    @State private var notes = ""
    @State private var kcalGoal: Double = 2000
    @State private var waterGoal: Double = 2.5
    @State private var stepGoal: Double = 8000
    @State private var confirmDelete = false
    @State private var deleteCount = 0
    @State private var loaded = false

    private let allergyChips = ["Penicillin", "Sulfa drugs", "Aspirin / NSAIDs", "Peanuts", "Tree nuts", "Milk / lactose", "Egg", "Gluten / wheat",
                                "Soy", "Shellfish", "Fish", "Dust", "Pollen", "Latex"]
    private let bloods = ["", "A+", "A−", "B+", "B−", "AB+", "AB−", "O+", "O−"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            PhotoSourceButton(onPick: { avatar = ImageTools.jpeg($0, maxSide: 800) }) {
                                AvatarView(data: avatar, name: [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces).isEmpty ? relation : "\(first) \(last)", size: 100)
                                    .overlay(alignment: .bottomTrailing) { Image(systemName: "camera.circle.fill").font(.title).foregroundStyle(.white, .blue) }
                            }
                            .buttonStyle(.plain)
                            if avatar != nil { Button("Remove photo", role: .destructive) { avatar = nil }.font(.caption) }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Who") {
                    TextField("First name", text: $first).textContentType(.givenName)
                    TextField("Last name", text: $last).textContentType(.familyName)
                    Picker("Relation to you", selection: $relation) { ForEach(FamilyData.relations, id: \.self) { Text($0) } }
                    if relation == "Other" { TextField("Relation (e.g. Godmother)", text: $customRelation) }
                    Picker("Sex", selection: $gender) { ForEach(["", "Male", "Female", "Other"], id: \.self) { Text($0.isEmpty ? "Not set" : $0) } }.pickerStyle(.segmented)
                }
                Section {
                    Toggle("I only know the age", isOn: $ageOnly)
                    if ageOnly {
                        Stepper("Age: \(age) years", value: $age, in: 0...110)
                    } else {
                        DatePicker("Date of birth", selection: $dob, in: ...Date.now, displayedComponents: .date)
                        Text(ageText).font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Age") }
                Section("Body") {
                    Picker("Blood group", selection: $blood) { ForEach(bloods, id: \.self) { Text($0.isEmpty ? "Not known" : $0) } }
                    HStack { Text("Height"); Spacer(); TextField("cm", value: $height, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text("cm").foregroundStyle(.secondary) }
                    if profile == nil {
                        HStack { Text("Weight now"); Spacer(); TextField("kg", value: $weight, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text("kg").foregroundStyle(.secondary) }
                    }
                }
                Section {
                    TextField("Allergies (medicines, food, other)", text: $allergies, axis: .vertical)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(allergyChips, id: \.self) { a in
                                let on = allergies.localizedCaseInsensitiveContains(a)
                                Button(a) { toggleAllergy(a, on: on) }.font(.caption).buttonStyle(.bordered).tint(on ? .red : .gray)
                            }
                        }
                    }
                    TextField("Ongoing conditions (e.g. thyroid, BP, asthma)", text: $conditions, axis: .vertical)
                } header: { Text("Allergies & conditions") } footer: {
                    Text("Allergies show in red on their card and Medical ID, and the AI never suggests foods they're allergic to.")
                }
                Section("Daily targets") {
                    Stepper("Calories: \(Int(kcalGoal)) kcal", value: $kcalGoal, in: 600...5000, step: 50)
                    Stepper(String(format: "Water: %.1f L", waterGoal), value: $waterGoal, in: 0.5...6, step: 0.25)
                    Stepper("Steps: \(Int(stepGoal).formatted())", value: $stepGoal, in: 0...30000, step: 500)
                }
                Section("Other") {
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    TextField("Notes (school, doctor, insurance…)", text: $notes, axis: .vertical)
                }
                if profile != nil {
                    Section {
                        Button("Delete member and all their entries", role: .destructive) {
                            deleteCount = FamilyData.entryCount(profile!.memberUID, in: context)
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(profile == nil ? "Add Family Member" : "Edit Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(first.trimmingCharacters(in: .whitespaces).isEmpty && relation == "Other" && customRelation.isEmpty) }
            }
            .confirmationDialog("Delete \(first.isEmpty ? "this member" : first) and \(deleteCount) entr\(deleteCount == 1 ? "y" : "ies") (food, workouts, medicines, reports, photos, expenses…)? This can't be undone.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { delete() }
            }
            .onAppear(perform: load)
        }
    }

    private var ageText: String {
        let c = Calendar.current.dateComponents([.year, .month], from: dob, to: .now)
        let y = c.year ?? 0, m = c.month ?? 0
        return y < 2 ? "\(y * 12 + m) months old" : "\(y) years old"
    }

    private func toggleAllergy(_ a: String, on: Bool) {
        var parts = allergies.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if on { parts.removeAll { $0.localizedCaseInsensitiveCompare(a) == .orderedSame } } else { parts.append(a) }
        allergies = parts.joined(separator: ", ")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let p = profile else { return }
        avatar = p.avatar; first = p.firstName; last = p.lastName; gender = p.gender
        if FamilyData.relations.contains(p.relation) { relation = p.relation } else { relation = "Other"; customRelation = p.relation }
        ageOnly = p.ageOnly
        if let d = p.dateOfBirth { dob = d; age = Calendar.current.dateComponents([.year], from: d, to: .now).year ?? 30 }
        blood = p.bloodGroup; height = p.heightCm; allergies = p.allergies; conditions = p.conditions
        phone = p.phone; notes = p.memberNotes
        kcalGoal = p.calorieIntakeGoal; waterGoal = p.waterGoalLitres; stepGoal = p.stepGoal
    }

    private func save() {
        let isNew = profile == nil
        let p = profile ?? HealthProfile()
        if isNew {
            p.memberUID = UUID().uuidString
            p.memberOrder = (allProfiles.map(\.memberOrder).max() ?? 0) + 1
            p.created = .now
            p.proteinGoal = 60; p.activeCalorieGoal = 300; p.exerciseMinuteGoal = 30
            context.insert(p)
        }
        p.avatar = avatar
        p.firstName = first.trimmingCharacters(in: .whitespaces); p.lastName = last.trimmingCharacters(in: .whitespaces)
        p.relation = relation == "Other" ? (customRelation.isEmpty ? "Other" : customRelation) : relation
        p.gender = gender
        p.ageOnly = ageOnly
        p.dateOfBirth = ageOnly ? Calendar.current.date(byAdding: .year, value: -age, to: .now) : dob
        p.bloodGroup = blood; p.heightCm = height; p.allergies = allergies; p.conditions = conditions
        p.phone = phone; p.memberNotes = notes
        p.calorieIntakeGoal = kcalGoal; p.waterGoalLitres = waterGoal; p.stepGoal = stepGoal
        if isNew && weight > 0 {
            p.startWeightKg = weight
            let m = BodyMeasurement(date: .now)
            m.memberUID = p.memberUID
            m.weightKg = weight
            context.insert(m)
        }
        try? context.save()
        Member.cacheNames(allProfiles + (isNew ? [p] : []))
        Haptics.success()
        let uid = p.memberUID
        dismiss()
        if isNew { onCreated?(uid) }
    }

    private func delete() {
        guard let p = profile else { return }
        let uid = p.memberUID
        if MemberStore.shared.uid == uid { MemberStore.shared.switchTo("") }
        FamilyData.deleteMember(uid, in: context)
        dismiss()
    }
}
