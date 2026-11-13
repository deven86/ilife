import SwiftUI
import SwiftData

// MARK: - Exercise picker (built-in library + your own exercises)

struct ExercisePickerView: View {
    let onDone: ([LibraryExercise]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomExercise.name) private var mine: [CustomExercise]
    @State private var search = ""
    @State private var muscle = "All"
    @State private var picked: [LibraryExercise] = []
    @State private var showNew = false

    private var all: [LibraryExercise] {
        mine.map { LibraryExercise(name: $0.name, muscle: "My Exercises", equipment: $0.equipment, isCardio: $0.isCardio) } + ExerciseLibrary.all
    }
    private var filtered: [LibraryExercise] {
        let base = muscle == "All" ? all : all.filter { $0.muscle == muscle }
        return search.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.equipment.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["All", "My Exercises"] + ExerciseLibrary.muscles, id: \.self) { m in
                                Button(m) { muscle = m }
                                    .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(muscle == m ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.gray.opacity(0.2)), in: Capsule())
                                    .foregroundStyle(muscle == m ? Color.white : Color.primary)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    Button { showNew = true } label: {
                        Label(search.isEmpty ? "Create your own exercise" : "Create \"\(search)\"", systemImage: "plus.circle.fill")
                    }
                }
                Section {
                    ForEach(filtered) { ex in
                        let count = picked.filter { $0.name == ex.name }.count
                        HStack(spacing: 12) {
                            SavedPhotoButton(kind: "exercise", name: ex.name, equipment: ex.equipment, size: 48)
                            Button {
                                if count > 0 { picked.removeAll { $0.name == ex.name } } else { picked.append(ex) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name).foregroundStyle(.primary)
                                        Text([ex.muscle, ex.equipment.isEmpty ? "Bodyweight" : ex.equipment].joined(separator: " · "))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: count > 0 ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(count > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } footer: {
                    Text("Tap a picture to add your own photo — it's saved and shown everywhere that exercise appears.")
                }
            }
            .searchable(text: $search, prompt: "Search \(ExerciseLibrary.all.count)+ exercises")
            .navigationTitle("Add Exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(picked.isEmpty ? "" : "(\(picked.count))")") { onDone(picked); dismiss() }.disabled(picked.isEmpty)
                }
            }
            .sheet(isPresented: $showNew) {
                NewExerciseSheet(initialName: search) { ex in picked.append(ex) }
            }
        }
    }
}

struct NewExerciseSheet: View {
    var initialName = ""
    let onCreate: (LibraryExercise) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscle = "Chest"
    @State private var equipment = ""
    @State private var isCardio = false
    @State private var photo: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Group {
                            if let photo { Image(uiImage: photo).resizable().scaledToFill() }
                            else { ItemThumbnail(photo: nil, illustration: .exercise(name, equipment: equipment), size: 72, corner: 14) }
                        }
                        .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 14))
                        PhotoSourceButton(onPick: { photo = $0 }) { Label(photo == nil ? "Add photo (e.g. the machine)" : "Change photo", systemImage: "camera.fill") }
                    }
                }
                Section {
                    TextField("Exercise name", text: $name)
                    Picker("Muscle group", selection: $muscle) { ForEach(ExerciseLibrary.muscles, id: \.self) { Text($0) } }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.all, id: \.self) { Text($0.isEmpty ? "Bodyweight / none" : $0) }
                    }
                    Toggle("Cardio (log time & distance)", isOn: $isCardio)
                }
            }
            .navigationTitle("New Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        context.insert(CustomExercise(name: n, muscle: muscle, equipment: equipment, isCardio: isCardio))
                        try? context.save()
                        if let photo { MediaStore.shared.set("exercise", n, image: photo) }
                        onCreate(LibraryExercise(name: n, muscle: "My Exercises", equipment: equipment, isCardio: isCardio))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if name.isEmpty { name = initialName }
                isCardio = muscle == "Cardio"
            }
            .onChange(of: muscle) { _, m in if m == "Cardio" { isCardio = true } }
        }
    }
}

// MARK: - Log / edit a workout

struct WorkoutEditorView: View {
    let log: WorkoutLog?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trainer.firstName) private var trainers: [Trainer]

    struct SetRow: Identifiable { let id = UUID(); var reps: Int; var kg: Double }
    struct Block: Identifiable {
        let id = UUID()
        var exercise: String
        var equipment: String
        var isCardio: Bool
        var sets: [SetRow] = [SetRow(reps: 10, kg: 0)]
        var minutes: Double = 20
        var km: Double = 0
    }

    @State private var name = ""
    @State private var category = "Strength"
    @State private var start = Date.now.addingTimeInterval(-3600)
    @State private var minutes = 60.0
    @State private var calories = ""
    @State private var notes = ""
    @State private var sessionType = "Self"
    @State private var trainerID = ""
    @State private var blocks: [Block] = []
    @State private var showPicker = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    Picker("Type", selection: $sessionType) {
                        Text("Self training").tag("Self")
                        Text("Personal training").tag("Personal Training")
                    }
                    .pickerStyle(.segmented)
                    if sessionType == "Personal Training" {
                        if trainers.isEmpty {
                            Text("Add your trainer in Fitness → Gym to link sessions.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Picker("Trainer", selection: $trainerID) {
                                Text("Not set").tag("")
                                ForEach(trainers) { Text($0.fullName).tag($0.uid) }
                            }
                        }
                    }
                }

                Section("Workout") {
                    TextField("Name (optional — e.g. Chest & Triceps)", text: $name)
                    Picker("Type", selection: $category) {
                        ForEach(["Strength", "Cardio", "HIIT", "Functional", "Yoga", "Running", "Walking", "Cycling", "Sports"], id: \.self) { Text($0) }
                    }
                    DatePicker("Started", selection: $start)
                    Stepper("Duration: \(Int(minutes)) min", value: $minutes, in: 1...300, step: 5)
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("auto", text: $calories).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                }

                ForEach($blocks) { $block in
                    Section {
                        HStack(spacing: 12) {
                            ItemThumbnail.exercise(block.exercise, equipment: block.equipment, size: 44, corner: 10)
                            VStack(alignment: .leading) {
                                Text(block.exercise).font(.headline)
                                if !block.equipment.isEmpty { Text(block.equipment).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button(role: .destructive) { blocks.removeAll { $0.id == block.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                        if block.isCardio {
                            Stepper("Time: \(Int(block.minutes)) min", value: $block.minutes, in: 1...300, step: 1)
                            Stepper("Distance: \(block.km.clean == "–" ? "0" : block.km.clean) km", value: $block.km, in: 0...100, step: 0.5)
                        } else {
                            ForEach(Array(block.sets.enumerated()), id: \.element.id) { i, _ in
                                HStack {
                                    Text("Set \(i + 1)").font(.caption.bold()).frame(width: 44, alignment: .leading)
                                    Stepper("\(block.sets[i].reps) reps", value: $block.sets[i].reps, in: 0...100).font(.subheadline)
                                    TextField("kg", value: $block.sets[i].kg, format: .number)
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 52)
                                    Text("kg").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .onDelete { block.sets.remove(atOffsets: $0) }
                            Button("Add set", systemImage: "plus") {
                                block.sets.append(block.sets.last.map { SetRow(reps: $0.reps, kg: $0.kg) } ?? SetRow(reps: 10, kg: 0))
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Section {
                    Button { showPicker = true } label: { Label("Add exercises", systemImage: "plus.circle.fill").font(.headline) }
                }

                Section("Notes") { TextField("How did it feel?", text: $notes, axis: .vertical) }

                if log != nil {
                    Section { Button("Delete workout", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(log == nil ? "Log Workout" : "Edit Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { picked in
                    blocks += picked.map { Block(exercise: $0.name, equipment: $0.equipment, isCardio: $0.isCardio) }
                    if !picked.isEmpty && picked.allSatisfy(\.isCardio) && blocks.allSatisfy(\.isCardio) { category = "Cardio" }
                }
            }
            .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let log { context.delete(log); try? context.save() }; dismiss() }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let log, blocks.isEmpty else { return }
        name = log.name; category = log.category; start = log.start; minutes = max(1, log.durationMinutes.rounded())
        calories = log.calories > 0 ? String(Int(log.calories)) : ""
        notes = log.notes; sessionType = log.sessionType; trainerID = log.trainerID
        var result: [Block] = []
        for s in log.orderedSets {
            let lib = ExerciseLibrary.find(s.exercise)
            let cardio = s.durationMinutes > 0 || s.distanceKm > 0 || (lib?.isCardio ?? false)
            if let last = result.last, last.exercise == s.exercise, !cardio {
                result[result.count - 1].sets.append(SetRow(reps: s.reps, kg: s.weightKg))
            } else {
                var b = Block(exercise: s.exercise, equipment: lib?.equipment ?? "", isCardio: cardio)
                if cardio { b.minutes = s.durationMinutes; b.km = s.distanceKm } else { b.sets = [SetRow(reps: s.reps, kg: s.weightKg)] }
                result.append(b)
            }
        }
        blocks = result
    }

    private func save() {
        let isNew = log == nil
        let target = log ?? WorkoutLog(name: "", category: category, start: start, durationMinutes: minutes, calories: 0)
        if isNew { context.insert(target) }

        let names = blocks.map(\.exercise)
        let autoName: String = {
            if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
            if names.isEmpty { return category == "Strength" ? "Strength Training" : category }
            return names.count <= 2 ? names.joined(separator: " & ") : "\(names[0]) +\(names.count - 1) more"
        }()
        let weight = HealthKitManager.shared.weightKg > 0 ? HealthKitManager.shared.weightKg : 75
        let met: Double = ["HIIT": 8, "Cardio": 7, "Running": 9, "Cycling": 7, "Yoga": 3, "Walking": 3.5, "Sports": 6, "Functional": 6][category] ?? 5

        target.name = autoName
        target.category = category
        target.start = start
        target.durationMinutes = minutes
        target.calories = Double(calories) ?? (met * weight * minutes / 60).rounded()
        target.notes = notes
        target.sessionType = sessionType
        target.trainerID = sessionType == "Personal Training" ? trainerID : ""

        (target.sets ?? []).forEach { context.delete($0) }
        var order = 0
        for b in blocks {
            if b.isCardio {
                let s = ExerciseSet(exercise: b.exercise, reps: 0, weightKg: 0, order: order)
                s.durationMinutes = b.minutes; s.distanceKm = b.km; s.log = target
                context.insert(s); order += 1
            } else {
                for r in b.sets {
                    let s = ExerciseSet(exercise: b.exercise, reps: r.reps, weightKg: r.kg, order: order)
                    s.log = target
                    context.insert(s); order += 1
                }
            }
        }
        try? context.save()
        if isNew { Task { await HealthKitManager.shared.saveWorkout(target, activity: .from(category: category)) } }
        dismiss()
    }
}

// MARK: - Workout detail

struct WorkoutDetailView: View {
    let log: WorkoutLog
    @Query private var trainers: [Trainer]
    @State private var editing = false

    private var trainer: Trainer? { trainers.first { $0.uid == log.trainerID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(log.start.formatted(date: .complete, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        metric("\(Int(log.durationMinutes))", "min")
                        metric("\(Int(log.calories))", "kcal")
                        if log.avgHeartRate > 0 { metric("\(Int(log.avgHeartRate))", "avg bpm") }
                        metric("\(log.orderedSets.count)", log.orderedSets.count == 1 ? "set" : "sets")
                    }
                    HStack {
                        Label(log.isPT ? "Personal training" : "Self training", systemImage: log.isPT ? "person.2.fill" : "person.fill")
                        if let trainer { Text("with \(trainer.fullName)").foregroundStyle(.secondary) }
                    }
                    .font(.subheadline)
                    Label("Source: \(log.source)", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                .glassCard()

                if log.orderedSets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No exercises recorded").font(.headline)
                        Text("Tap Edit to add the exercises and sets you did.").font(.caption).foregroundStyle(.secondary)
                    }
                    .glassCard()
                }

                ForEach(log.exerciseNames, id: \.self) { ex in
                    let sets = log.orderedSets.filter { $0.exercise == ex }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            ItemThumbnail.exercise(ex, equipment: ExerciseLibrary.find(ex)?.equipment ?? "", size: 48, corner: 10)
                            Text(ex).font(.headline)
                        }
                        ForEach(Array(sets.enumerated()), id: \.offset) { i, s in
                            HStack {
                                Text("Set \(i + 1)").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                                if s.durationMinutes > 0 || s.distanceKm > 0 {
                                    Text("\(Int(s.durationMinutes)) min" + (s.distanceKm > 0 ? " · \(s.distanceKm.clean) km" : ""))
                                } else if s.reps == 0 && s.weightKg == 0 {
                                    Text("Done").foregroundStyle(.secondary)
                                } else {
                                    Text("\(s.reps) reps" + (s.weightKg > 0 ? " × \(s.weightKg.clean) kg" : ""))
                                }
                                Spacer()
                            }
                            .font(.subheadline)
                        }
                        let volume = sets.reduce(0) { $0 + Double($1.reps) * $1.weightKg }
                        if volume > 0 { Text("Volume \(Int(volume)) kg").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .glassCard()
                }

                if !log.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.headline)
                        Text(log.notes).font(.subheadline)
                    }
                    .glassCard()
                }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle(log.name)
        .toolbar { Button("Edit") { editing = true } }
        .sheet(isPresented: $editing) { WorkoutEditorView(log: log) }
    }

    private func metric(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.title3.bold())
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
