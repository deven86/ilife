import SwiftUI
import SwiftData

struct PlanEditorView: View {
    let plan: WorkoutPlan?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var focus = "Full Body"
    @State private var level = "Intermediate"
    @State private var minutes = 45
    @State private var weekdays: Set<Int> = []
    @State private var items: [DraftExercise] = []
    @State private var cover: Data?

    struct DraftExercise: Identifiable {
        let id = UUID()
        var name: String; var sets: Int; var reps: String; var rest: Int
        var equipment: String = ""
        var photo: Data? = nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ItemThumbnail(photo: cover, illustration: .exercise(focus), size: 72, corner: 14)
                        VStack(alignment: .leading, spacing: 6) {
                            PhotoSourceButton(onPick: { cover = ImageTools.jpeg($0, maxSide: 1400) }) {
                                Label(cover == nil ? "Add cover photo" : "Change cover photo", systemImage: "photo")
                            }
                            if cover != nil { Button("Remove", role: .destructive) { cover = nil }.font(.caption) }
                        }
                    }
                }
                Section("Plan") {
                    TextField("Name (e.g. Push Day)", text: $name)
                    Picker("Focus", selection: $focus) {
                        ForEach(["Full Body", "Push", "Pull", "Legs", "Upper Body", "Core", "HIIT", "Cardio", "Yoga"], id: \.self) { Text($0) }
                    }
                    Picker("Level", selection: $level) {
                        ForEach(["Beginner", "Intermediate", "Advanced"], id: \.self) { Text($0) }
                    }
                    Stepper("Duration: \(minutes) min", value: $minutes, in: 10...180, step: 5)
                }
                Section("Repeat on") {
                    HStack {
                        ForEach(1...7, id: \.self) { d in
                            let on = weekdays.contains(d)
                            Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) {
                                if on { weekdays.remove(d) } else { weekdays.insert(d) }
                            }
                            .font(.caption.bold()).frame(width: 34, height: 34)
                            .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.gray.opacity(0.2)), in: Circle())
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Exercises") {
                    ForEach($items) { $item in
                        VStack(alignment: .leading) {
                            HStack(spacing: 12) {
                                PhotoSourceButton(onPick: { item.photo = ImageTools.jpeg($0, maxSide: 1000) }) {
                                    ItemThumbnail(photo: item.photo, illustration: .exercise(item.name, equipment: item.equipment), size: 56, corner: 12)
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: "camera.circle.fill").font(.callout).foregroundStyle(.white, .black.opacity(0.6)).offset(x: 4, y: 4)
                                        }
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("Exercise", text: $item.name).font(.headline)
                                    Picker("Equipment", selection: $item.equipment) {
                                        ForEach(Equipment.all, id: \.self) { e in
                                            Label(e.isEmpty ? "No equipment" : e, systemImage: Equipment.symbol(e)).tag(e)
                                        }
                                    }
                                    .pickerStyle(.menu).labelsHidden().font(.caption)
                                }
                            }
                            HStack {
                                Stepper("\(item.sets) sets", value: $item.sets, in: 1...10)
                                TextField("Reps", text: $item.reps).frame(width: 60).textFieldStyle(.roundedBorder)
                            }
                            Stepper("Rest \(item.rest)s", value: $item.rest, in: 0...300, step: 15).font(.caption)
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add exercise", systemImage: "plus") { items.append(.init(name: "", sets: 3, reps: "12", rest: 60)) }
                }
                if let plan {
                    Section { Button("Delete plan", role: .destructive) { context.delete(plan); dismiss() } }
                }
            }
            .navigationTitle(plan == nil ? "New Plan" : "Edit Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.isEmpty) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let plan else { return }
        name = plan.name; focus = plan.focus; level = plan.level; minutes = plan.estimatedMinutes
        weekdays = Set(plan.weekdays)
        cover = plan.coverPhoto
        items = plan.orderedExercises.map { .init(name: $0.name, sets: $0.sets, reps: $0.reps, rest: $0.restSeconds, equipment: $0.equipment, photo: $0.photo) }
    }

    private func save() {
        let target = plan ?? WorkoutPlan(name: name, focus: focus, level: level, estimatedMinutes: minutes, weekdays: [])
        if plan == nil { context.insert(target) }
        target.name = name; target.focus = focus; target.level = level
        target.estimatedMinutes = minutes; target.weekdays = weekdays.sorted()
        target.coverPhoto = cover
        (target.exercises ?? []).forEach { context.delete($0) }
        for (i, d) in items.enumerated() where !d.name.isEmpty {
            let e = PlanExercise(name: d.name, sets: d.sets, reps: d.reps, restSeconds: d.rest, order: i)
            e.equipment = d.equipment
            e.photo = d.photo
            e.plan = target
            context.insert(e)
        }
        try? context.save()
        dismiss()
    }
}

enum PlanTemplates {
    static func seed(into context: ModelContext) {
        let templates: [(String, String, String, Int, [Int], [(String, Int, String)])] = [
            ("Push Day", "Push", "Intermediate", 50, [2, 5], [("Bench Press", 4, "8-10"), ("Incline Dumbbell Press", 3, "10"),
              ("Overhead Press", 3, "8-10"), ("Lateral Raises", 3, "15"), ("Tricep Pushdown", 3, "12"), ("Push-ups", 2, "Max")]),
            ("Pull Day", "Pull", "Intermediate", 50, [3, 6], [("Deadlift", 3, "5"), ("Lat Pulldown", 4, "10"),
              ("Seated Cable Row", 3, "10"), ("Face Pulls", 3, "15"), ("Barbell Curl", 3, "10"), ("Hammer Curl", 3, "12")]),
            ("Leg Day", "Legs", "Intermediate", 55, [4, 7], [("Back Squat", 4, "6-8"), ("Romanian Deadlift", 3, "10"),
              ("Leg Press", 3, "12"), ("Walking Lunges", 3, "12 each"), ("Leg Curl", 3, "12"), ("Calf Raises", 4, "15")]),
            ("Full Body Burn", "Full Body", "Beginner", 40, [], [("Goblet Squat", 3, "12"), ("Dumbbell Row", 3, "12"),
              ("Push-ups", 3, "10"), ("Kettlebell Swing", 3, "15"), ("Plank", 3, "45s")]),
            ("HIIT Blast", "HIIT", "Advanced", 25, [], [("Burpees", 4, "40s"), ("Mountain Climbers", 4, "40s"),
              ("Jump Squats", 4, "40s"), ("High Knees", 4, "40s"), ("Rest", 4, "20s")]),
            ("Morning Yoga Flow", "Yoga", "Beginner", 30, [1], [("Sun Salutation A", 3, "5 rounds"), ("Warrior II", 2, "45s"),
              ("Triangle Pose", 2, "45s"), ("Downward Dog", 3, "60s"), ("Savasana", 1, "5 min")])
        ]
        for t in templates {
            let p = WorkoutPlan(name: t.0, focus: t.1, level: t.2, estimatedMinutes: t.3, weekdays: t.4)
            context.insert(p)
            for (i, e) in t.5.enumerated() {
                let ex = PlanExercise(name: e.0, sets: e.1, reps: e.2, restSeconds: 60, order: i)
                ex.equipment = Equipment.guess(for: e.0)
                ex.plan = p
                context.insert(ex)
            }
        }
        try? context.save()
    }
}

enum Equipment {
    static let all = ["", "Barbell", "Dumbbells", "Kettlebell", "Cable Machine", "Machine", "Smith Machine", "Bench",
                      "Pull-up Bar", "Resistance Band", "Medicine Ball", "TRX", "Yoga Mat", "Treadmill", "Cycle", "Rowing Machine", "Skipping Rope"]

    static func symbol(_ e: String) -> String {
        switch e {
        case "Barbell", "Dumbbells", "Smith Machine": "dumbbell.fill"
        case "Kettlebell": "figure.cross.training"
        case "Cable Machine", "Machine": "gearshape.2.fill"
        case "Bench": "bed.double.fill"
        case "Pull-up Bar": "figure.play"
        case "Resistance Band", "TRX": "point.topleft.down.to.point.bottomright.curvepath"
        case "Medicine Ball": "basketball.fill"
        case "Yoga Mat": "rectangle.portrait.fill"
        case "Treadmill": "figure.run"
        case "Cycle": "bicycle"
        case "Rowing Machine": "figure.rower"
        case "Skipping Rope": "figure.jumprope"
        default: "figure.stand"
        }
    }

    static func guess(for exercise: String) -> String {
        let n = exercise.lowercased()
        if n.contains("dumbbell") || n.contains("hammer") || n.contains("goblet") || n.contains("lateral") { return "Dumbbells" }
        if n.contains("kettlebell") { return "Kettlebell" }
        if n.contains("cable") || n.contains("pushdown") || n.contains("face pull") || n.contains("pulldown") || n.contains("row") && n.contains("seated") { return "Cable Machine" }
        if n.contains("leg press") || n.contains("leg curl") || n.contains("calf") { return "Machine" }
        if n.contains("bench") || n.contains("squat") || n.contains("deadlift") || n.contains("press") || n.contains("barbell") || n.contains("curl") { return "Barbell" }
        if n.contains("yoga") || n.contains("salutation") || n.contains("pose") || n.contains("dog") || n.contains("warrior") || n.contains("savasana") || n.contains("plank") { return "Yoga Mat" }
        return ""
    }
}
