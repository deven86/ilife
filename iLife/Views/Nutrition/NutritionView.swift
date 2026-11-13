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
        MealType.allCases.filter { $0.isCore || dayFoods.contains(where: { f in f.meal == $0 }) }
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
                    ItemThumbnail(photo: item.photo, illustration: .food(item.name), size: 44, corner: 10)
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

struct FoodPreset: Identifiable {
    let id = UUID()
    let name: String, serving: String, kcal: Double, p: Double, c: Double, f: Double
}

enum FoodLibrary {
    static let items: [FoodPreset] = [
        .init(name: "Chapati / Roti", serving: "1 medium", kcal: 105, p: 3, c: 18, f: 3),
        .init(name: "Steamed Rice", serving: "1 cup", kcal: 205, p: 4, c: 45, f: 0.4),
        .init(name: "Dal (cooked)", serving: "1 bowl", kcal: 180, p: 9, c: 25, f: 5),
        .init(name: "Paneer", serving: "100 g", kcal: 265, p: 18, c: 4, f: 20),
        .init(name: "Chicken Breast (cooked)", serving: "100 g", kcal: 165, p: 31, c: 0, f: 3.6),
        .init(name: "Egg (whole, boiled)", serving: "1 large", kcal: 78, p: 6, c: 0.6, f: 5),
        .init(name: "Egg White", serving: "1 large", kcal: 17, p: 3.6, c: 0.2, f: 0),
        .init(name: "Poha", serving: "1 plate", kcal: 250, p: 5, c: 45, f: 6),
        .init(name: "Idli", serving: "2 pieces", kcal: 120, p: 4, c: 24, f: 0.5),
        .init(name: "Plain Dosa", serving: "1 medium", kcal: 170, p: 4, c: 28, f: 4),
        .init(name: "Upma", serving: "1 bowl", kcal: 230, p: 6, c: 35, f: 7),
        .init(name: "Curd / Dahi", serving: "1 cup", kcal: 100, p: 8, c: 8, f: 4),
        .init(name: "Banana", serving: "1 medium", kcal: 105, p: 1.3, c: 27, f: 0.4),
        .init(name: "Apple", serving: "1 medium", kcal: 95, p: 0.5, c: 25, f: 0.3),
        .init(name: "Oats (dry)", serving: "40 g", kcal: 150, p: 5, c: 27, f: 2.5),
        .init(name: "Whey Protein", serving: "1 scoop", kcal: 120, p: 24, c: 3, f: 1.5),
        .init(name: "Milk (toned)", serving: "1 glass", kcal: 120, p: 6, c: 10, f: 6),
        .init(name: "Almonds", serving: "10 pieces", kcal: 70, p: 2.6, c: 2.5, f: 6),
        .init(name: "Fish (grilled)", serving: "100 g", kcal: 140, p: 25, c: 0, f: 4),
        .init(name: "Sprouts Salad", serving: "1 bowl", kcal: 120, p: 8, c: 18, f: 1.5),
        .init(name: "Vegetable Sabzi", serving: "1 bowl", kcal: 150, p: 4, c: 15, f: 8),
        .init(name: "Tea with milk & sugar", serving: "1 cup", kcal: 70, p: 2, c: 10, f: 2),
        .init(name: "Black Coffee", serving: "1 cup", kcal: 5, p: 0.3, c: 0, f: 0),
        .init(name: "Coffee with milk", serving: "1 cup", kcal: 60, p: 3, c: 6, f: 2.5),
        .init(name: "Green Tea", serving: "1 cup", kcal: 2, p: 0, c: 0, f: 0),
        .init(name: "Black Tea (no sugar)", serving: "1 cup", kcal: 2, p: 0, c: 0.5, f: 0),
        .init(name: "Lemon Water", serving: "1 glass", kcal: 10, p: 0, c: 3, f: 0),
        .init(name: "Coconut Water", serving: "1 glass", kcal: 45, p: 0.5, c: 9, f: 0.5),
        .init(name: "Buttermilk / Chaas", serving: "1 glass", kcal: 40, p: 3, c: 5, f: 1),
        .init(name: "Protein Shake (whey + milk)", serving: "1 glass", kcal: 240, p: 30, c: 13, f: 7.5),
        .init(name: "Fresh Orange Juice", serving: "1 glass", kcal: 110, p: 2, c: 26, f: 0.5),
        .init(name: "Soaked Almonds", serving: "5 pieces", kcal: 35, p: 1.3, c: 1.2, f: 3),
        .init(name: "Paratha (plain)", serving: "1 medium", kcal: 260, p: 5, c: 36, f: 10),
        .init(name: "Brown Bread", serving: "2 slices", kcal: 140, p: 6, c: 24, f: 2),
        .init(name: "Peanut Butter", serving: "1 tbsp", kcal: 95, p: 4, c: 3, f: 8),
        .init(name: "Greek Yogurt", serving: "100 g", kcal: 60, p: 10, c: 4, f: 0.4),
        .init(name: "Rajma (cooked)", serving: "1 bowl", kcal: 210, p: 13, c: 35, f: 1),
        .init(name: "Chole (cooked)", serving: "1 bowl", kcal: 270, p: 12, c: 40, f: 7),
        .init(name: "Khichdi", serving: "1 bowl", kcal: 250, p: 9, c: 40, f: 6),
        .init(name: "Papaya", serving: "1 cup", kcal: 60, p: 0.7, c: 15, f: 0.2),
    ]
}

struct AddFoodSheet: View {
    let date: Date
    @State private var meal: MealType
    @State private var time: Date
    @State private var photo: UIImage?

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
    @State private var search = ""
    @State private var custom = false
    @State private var name = ""
    @State private var qty = ""
    @State private var kcal = ""
    @State private var p = ""
    @State private var c = ""
    @State private var f = ""
    @State private var servings = 1.0

    private var filtered: [FoodPreset] {
        search.isEmpty ? FoodLibrary.items : FoodLibrary.items.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Stepper("Servings: \(servings.clean)", value: $servings, in: 0.5...10, step: 0.5)
                    HStack {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        PhotoSourceButton(onPick: { photo = $0 }) {
                            Label(photo == nil ? "Add a photo of your food" : "Change photo", systemImage: "camera.fill")
                        }
                        if photo != nil { Spacer(); Button("Remove", role: .destructive) { photo = nil }.font(.caption) }
                    }
                } footer: {
                    Text("Log anything at any time — pick the meal it belongs to.")
                }
                Section("Quick add") {
                    ForEach(filtered) { item in
                        Button {
                            save(name: item.name, qty: "\(servings.clean) × \(item.serving)", kcal: item.kcal * servings,
                                 p: item.p * servings, c: item.c * servings, f: item.f * servings)
                        } label: {
                            HStack(spacing: 12) {
                                ItemThumbnail(photo: nil, illustration: .food(item.name), size: 40, corner: 9)
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    Text(item.serving).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int(item.kcal * servings)) kcal").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Custom food") {
                    TextField("Food name", text: $name)
                    TextField("Quantity (e.g. 1 bowl)", text: $qty)
                    TextField("Calories (kcal)", text: $kcal).keyboardType(.decimalPad)
                    TextField("Protein (g)", text: $p).keyboardType(.decimalPad)
                    TextField("Carbs (g)", text: $c).keyboardType(.decimalPad)
                    TextField("Fat (g)", text: $f).keyboardType(.decimalPad)
                    Button("Add custom food") {
                        save(name: name, qty: qty, kcal: Double(kcal) ?? 0, p: Double(p) ?? 0, c: Double(c) ?? 0, f: Double(f) ?? 0)
                    }
                    .disabled(name.isEmpty || (Double(kcal) ?? 0) <= 0)
                }
            }
            .searchable(text: $search, prompt: "Search foods")
            .navigationTitle("Log Food")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func save(name: String, qty: String, kcal: Double, p: Double, c: Double, f: Double) {
        let entry = FoodEntry(name: name, meal: meal, calories: kcal, protein: p, carbs: c, fat: f, quantity: qty, date: time)
        if let photo { entry.photo = ImageTools.jpeg(photo, maxSide: 1200) }
        context.insert(entry)
        try? context.save()
        Task { await HealthKitManager.shared.saveFood(entry) }
        dismiss()
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
                        ItemThumbnail(photo: entry.photo, illustration: .food(entry.name), size: 72, corner: 14)
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
