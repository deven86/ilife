import SwiftUI
import SwiftData
import Charts

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var health: HealthKitManager
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waters: [WaterEntry]
    @Query private var profiles: [HealthProfile]

    @State private var day = Date.now
    @State private var addMeal: MealType?
    @State private var editing: FoodEntry?

    private var profile: HealthProfile { profiles.first ?? HealthProfile() }
    private var dayFoods: [FoodEntry] { foods.filter { Calendar.current.isDate($0.date, inSameDayAs: day) } }
    private var dayWaterL: Double { waters.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.millilitres } / 1000 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(Calendar.current.isDateInToday(day) ? "Today" : day.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                    Spacer()
                    Button { day = Calendar.current.date(byAdding: .day, value: 1, to: day)! } label: { Image(systemName: "chevron.right") }
                        .disabled(Calendar.current.isDateInToday(day))
                }
                .glassCard(cornerRadius: 16, padding: 12)

                breakdown
                water
                ForEach(visibleMeals) { meal in mealSection(meal) }
                Spacer(minLength: 70)
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Nutrition & Diet")
        .sheet(item: $addMeal) { AddFoodSheet(meal: $0, date: day) }
        .sheet(item: $editing) { EditFoodSheet(entry: $0) }
        .overlay(alignment: .bottomTrailing) {
            Button { addMeal = Calendar.current.isDateInToday(day) ? MealType.suggested() : .other } label: {
                Label("Log Food", systemImage: "plus").font(.headline).padding(.horizontal, 20).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .padding(.trailing, 20).padding(.bottom, 12)
        }
    }

    private var breakdown: some View {
        let kcal = dayFoods.reduce(0) { $0 + $1.calories }
        let p = dayFoods.reduce(0) { $0 + $1.protein }, c = dayFoods.reduce(0) { $0 + $1.carbs }, f = dayFoods.reduce(0) { $0 + $1.fat }
        let macroKcal = max(p * 4 + c * 4 + f * 9, 1)
        let parts: [(String, Double, Color)] = [("Protein", p * 4 / macroKcal, .cyan), ("Carbs", c * 4 / macroKcal, .yellow), ("Fats", f * 9 / macroKcal, .pink)]
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Nutrition Breakdown", trailing: "\(Int(kcal)) / \(Int(profile.calorieIntakeGoal)) kcal")
            HStack(spacing: 20) {
                ZStack {
                    if kcal > 0 {
                        Chart(parts, id: \.0) { part in
                            SectorMark(angle: .value("Share", part.1), innerRadius: .ratio(0.68), angularInset: 2)
                                .foregroundStyle(part.2).cornerRadius(4)
                        }
                    } else {
                        Circle().stroke(.secondary.opacity(0.3), lineWidth: 14)
                    }
                    VStack(spacing: 0) {
                        Text("\(Int(kcal / max(profile.calorieIntakeGoal, 1) * 100))%").font(.title3.bold())
                        Text("of goal").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(parts, id: \.0) { part in
                        HStack {
                            Circle().fill(part.2).frame(width: 10, height: 10)
                            Text(part.0).font(.subheadline)
                            Spacer()
                            Text("\(Int(part.1 * 100))%").font(.subheadline.bold())
                        }
                    }
                    Text("Protein \(Int(p)) / \(Int(profile.proteinGoal)) g").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .glassCard()
    }

    private var water: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Hydration", trailing: String(format: "%.1f / %.1f L", dayWaterL, profile.waterGoalLitres))
            ProgressView(value: min(dayWaterL / max(profile.waterGoalLitres, 0.1), 1)).tint(.blue)
            HStack {
                ForEach([150.0, 250, 500], id: \.self) { ml in
                    Button("+\(Int(ml)) ml") {
                        context.insert(WaterEntry(millilitres: ml, date: Calendar.current.isDateInToday(day) ? .now : day))
                        try? context.save()
                        Task { await health.saveWater(ml: ml) }
                    }
                    .buttonStyle(.bordered).tint(.blue)
                }
            }
        }
        .glassCard()
    }

    /// Core meals always show; extra types (Early Morning, Drinks, Pre/Post-Workout, Other) show once used.
    private var visibleMeals: [MealType] {
        MealType.allCases.filter { m in m.isCore || dayFoods.contains { $0.meal == m } }
    }

    private func mealSection(_ meal: MealType) -> some View {
        let items = dayFoods.filter { $0.meal == meal }.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 10) {
            Button { addMeal = meal } label: {
                HStack {
                    Label(meal.title, systemImage: meal.icon).font(.headline)
                    Spacer()
                    Text("\(Int(items.reduce(0) { $0 + $1.calories })) kcal").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(items) { item in
                HStack(spacing: 12) {
                    ItemThumbnail.food(item.name, photo: item.photo, size: 44, corner: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.subheadline)
                        Text("\(item.date.formatted(date: .omitted, time: .shortened)) · P \(Int(item.protein))g · C \(Int(item.carbs))g · F \(Int(item.fat))g\(item.quantity.isEmpty ? "" : " · \(item.quantity)")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(item.calories))").font(.subheadline.bold())
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = item }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editing = item }
                    Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) }
                }
            }
        }
        .glassCard()
    }
}

struct AddFoodSheet: View {
    let date: Date
    @State private var meal: MealType
    @State private var time: Date

    init(meal: MealType, date: Date) {
        self.date = date
        _meal = State(initialValue: meal)
        let cal = Calendar.current
        let t = cal.isDateInToday(date) ? Date.now
            : cal.date(bySettingHour: cal.component(.hour, from: .now), minute: cal.component(.minute, from: .now), second: 0, of: date) ?? date
        _time = State(initialValue: t)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomFood.name) private var myFoods: [CustomFood]
    @Query(sort: \FoodEntry.date, order: .reverse) private var history: [FoodEntry]
    @State private var search = ""
    @State private var category = "All"
    @State private var servings = 1.0
    @State private var showCustom = false

    private var allFoods: [FoodPreset] {
        myFoods.map { FoodPreset(name: $0.name, serving: $0.serving, kcal: $0.calories, p: $0.protein, c: $0.carbs, f: $0.fat, category: "My Foods") }
            + FoodLibrary.items
    }

    private var recent: [FoodPreset] {
        var seen = Set<String>()
        return history.prefix(80).compactMap { e in
            guard seen.insert(e.name.lowercased()).inserted else { return nil }
            if let preset = allFoods.first(where: { $0.name.caseInsensitiveCompare(e.name) == .orderedSame }) { return preset }
            return FoodPreset(name: e.name, serving: e.quantity.isEmpty ? "1 serving" : e.quantity, kcal: e.calories, p: e.protein, c: e.carbs, f: e.fat, category: "Recent")
        }
        .prefix(15).map { $0 }
    }

    private var filtered: [FoodPreset] {
        let base: [FoodPreset]
        switch category {
        case "All": base = allFoods
        case "Recent": base = recent
        default: base = allFoods.filter { $0.category == category }
        }
        return search.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var chips: [String] { ["All", "Recent", "My Foods"] + FoodLibrary.categories }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Stepper("Servings: \(servings.clean)", value: $servings, in: 0.25...10, step: 0.25)
                } footer: {
                    Text("Tap a food to log it. Tap its picture to add your own photo — it's saved for next time.")
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chips, id: \.self) { c in
                                Button(c) { category = c }
                                    .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(category == c ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.gray.opacity(0.2)), in: Capsule())
                                    .foregroundStyle(category == c ? Color.white : Color.primary)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))

                    Button { showCustom = true } label: {
                        Label(search.isEmpty ? "Create your own food" : "Create \"\(search)\"", systemImage: "plus.circle.fill")
                    }

                    if filtered.isEmpty {
                        Text(category == "My Foods" ? "Foods you create are saved here." : "No match — create it above.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(filtered) { item in
                        HStack(spacing: 12) {
                            SavedPhotoButton(kind: "food", name: item.name, size: 46)
                            Button { log(item) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).foregroundStyle(.primary)
                                        Text("\(item.serving) · P \(item.p.clean) · C \(item.c.clean) · F \(item.f.clean)")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(item.kcal * servings)) kcal").font(.subheadline).foregroundStyle(.secondary)
                                    Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search 190+ foods")
            .navigationTitle("Log Food")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showCustom) {
                CustomFoodSheet(initialName: search) { food, logNow in
                    if logNow { log(FoodPreset(name: food.name, serving: food.serving, kcal: food.calories, p: food.protein, c: food.carbs, f: food.fat)) }
                }
            }
        }
    }

    private func log(_ item: FoodPreset) {
        let qty = servings == 1 ? item.serving : "\(servings.clean) × \(item.serving)"
        let entry = FoodEntry(name: item.name, meal: meal, calories: item.kcal * servings, protein: item.p * servings,
                              carbs: item.c * servings, fat: item.f * servings, quantity: qty, date: time)
        context.insert(entry)
        try? context.save()
        Task { await HealthKitManager.shared.saveFood(entry) }
        dismiss()
    }
}

/// Create a food once; it's saved under "My Foods" with its photo.
struct CustomFoodSheet: View {
    var initialName: String = ""
    let onSave: (CustomFood, Bool) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var serving = "1 serving"
    @State private var kcal = ""
    @State private var p = ""
    @State private var c = ""
    @State private var f = ""
    @State private var photo: UIImage?
    @State private var logNow = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Group {
                            if let photo { Image(uiImage: photo).resizable().scaledToFill() }
                            else { ItemThumbnail(photo: nil, illustration: .food(name), size: 72, corner: 14) }
                        }
                        .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 14))
                        PhotoSourceButton(onPick: { photo = $0 }) { Label(photo == nil ? "Add photo" : "Change photo", systemImage: "camera.fill") }
                    }
                }
                Section("Food") {
                    TextField("Name (e.g. MuscleBlaze Whey shake)", text: $name)
                    TextField("Serving (e.g. 1 scoop, 1 bowl)", text: $serving)
                }
                Section("Per serving") {
                    field("Calories (kcal)", $kcal); field("Protein (g)", $p); field("Carbs (g)", $c); field("Fat (g)", $f)
                }
                Section { Toggle("Also log it now", isOn: $logNow) }
            }
            .navigationTitle("New Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        func n(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
                        let food = CustomFood(name: name.trimmingCharacters(in: .whitespaces), serving: serving, calories: n(kcal), protein: n(p), carbs: n(c), fat: n(f))
                        context.insert(food)
                        try? context.save()
                        if let photo { MediaStore.shared.set("food", food.name, image: photo) }
                        dismiss()
                        onSave(food, logNow)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if name.isEmpty { name = initialName } }
        }
    }

    private func field(_ title: String, _ v: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: v).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
}

struct EditFoodSheet: View {
    @Bindable var entry: FoodEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ItemThumbnail.food(entry.name, photo: entry.photo, size: 72, corner: 14)
                        VStack(alignment: .leading, spacing: 8) {
                            PhotoSourceButton(onPick: { entry.photo = ImageTools.jpeg($0, maxSide: 1200) }) {
                                Label(entry.photo == nil ? "Add photo" : "Change photo", systemImage: "camera.fill")
                            }
                            if entry.photo != nil { Button("Remove photo", role: .destructive) { entry.photo = nil }.font(.caption) }
                        }
                    }
                }
                Section("Food") {
                    TextField("Name", text: $entry.name)
                    TextField("Quantity", text: $entry.quantity)
                    Picker("Meal", selection: Binding(get: { entry.meal }, set: { entry.meal = $0 })) {
                        ForEach(MealType.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    DatePicker("Time", selection: $entry.date)
                }
                Section("Nutrition") {
                    number("Calories (kcal)", $entry.calories)
                    number("Protein (g)", $entry.protein)
                    number("Carbs (g)", $entry.carbs)
                    number("Fat (g)", $entry.fat)
                }
                Section { Button("Delete entry", role: .destructive) { context.delete(entry); dismiss() } }
            }
            .navigationTitle("Edit Food")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { try? context.save(); dismiss() } } }
        }
    }

    private func number(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
}
