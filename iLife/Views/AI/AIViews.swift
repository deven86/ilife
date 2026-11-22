import SwiftUI
import SwiftData

// MARK: - Settings

struct AISettingsView: View {
    @ObservedObject private var ai = AIService.shared
    @State private var key = ""
    @State private var testing = false
    @State private var result: String?
    @ObservedObject private var coach = AICoordinator.shared
    @AppStorage("aiShareMedical") private var shareMedical = false

    private func timeRow(_ title: String, _ minutes: Binding<Int>) -> some View {
        DatePicker(title, selection: Binding(
            get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) }),
            displayedComponents: .hourAndMinute)
    }

    var body: some View {
        Form {
            Section {
                Picker("AI engine", selection: $ai.engine) {
                    ForEach(AIService.Engine.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if ai.engine == .apple && !AIService.appleAvailable {
                    Label(AIService.appleUnavailableReason, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
            } header: { Text("AI engine") } footer: {
                Text(ai.engine == .apple
                     ? "Free and private: Apple's on-device model runs on this iPhone, works offline, and nothing is sent anywhere. Photos (meals, reports, InBody) are read on the device first. For harder jobs, Claude is more accurate."
                     : "Claude is more capable, especially with photos, but needs your own Anthropic key and costs a rupee or two per request. Only what a feature needs is sent to Anthropic.")
            }

            Section {
                Label(ai.isOn ? "AI mode is on" : "AI mode is off", systemImage: ai.isOn ? "sparkles" : "moon.zzz")
                    .foregroundStyle(ai.isOn ? Color.green : Color.secondary)
                Toggle("AI mode", isOn: $ai.enabled).disabled(ai.engine == .claude ? !ai.hasKey : !AIService.appleAvailable)
            } footer: {
                Text("With AI mode off, iLife makes no AI requests at all and everything else keeps working.")
            }

            if ai.isOn {
                Section {
                    Toggle("Morning plan", isOn: $coach.autoMorning)
                    if coach.autoMorning { timeRow("Remind me at", $coach.morningMinutes) }
                    Toggle("Night review", isOn: $coach.autoNight)
                    if coach.autoNight { timeRow("Review time", $coach.nightMinutes) }
                    NavigationLink { AIHistoryView() } label: { Label("Plans & reviews history", systemImage: "clock.arrow.circlepath") }
                } header: {
                    Text("Once a day")
                } footer: {
                    Text("To keep cost low, iLife asks the AI only twice a day by itself: one plan in the morning (meals with recipes, workout, supplements, priorities) and one full review at night. Each is written the first time you open iLife after that time — iPhone doesn't let apps run on their own at a set hour — and is then saved, so reopening costs nothing. Snap Meal, InBody reading and Coach chat only run when you tap them.")
                }
                Section {
                    Toggle("Include medicines & medical history", isOn: $shareMedical)
                } header: { Text("Privacy") } footer: {
                    Text("Off by default. When on, the AI sees current medicine names, whether doses were ticked, and active injuries or health events — so it can, for example, avoid exercises that strain an injury. It never changes or advises on doses; always follow your doctor.")
                }
                Section("Usage") {
                    HStack { Text("AI requests today"); Spacer(); Text("\(ai.callsToday)").foregroundStyle(.secondary) }
                }
            }

            if ai.engine == .claude {
            Section {
                SecureField(ai.hasKey ? "Key saved — paste a new one to replace" : "Paste your Anthropic API key (sk-ant-…)", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save key") {
                    ai.saveKey(key); key = ""; result = nil; Haptics.success()
                    Task { await NotificationService.requestAuthorization(); coach.scheduleNotifications() }
                }.disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                if ai.hasKey {
                    Button("Remove key", role: .destructive) { ai.saveKey(""); result = nil }
                }
            } header: {
                Text("Your API key")
            } footer: {
                Text("Create a key at console.anthropic.com → API Keys. It is stored only in this iPhone's Keychain. You pay Anthropic directly for usage — typically a rupee or two per scan or question. Set a monthly spend limit in the console.")
            }

            Section("Model") {
                Picker("Model", selection: $ai.model) {
                    Text("Sonnet — best balance").tag("claude-sonnet-5-5")
                    Text("Haiku — fastest, cheapest").tag("claude-haiku-5-5")
                    Text("Opus — most capable").tag("claude-opus-5-5")
                }
                TextField("Model ID", text: $ai.model).textInputAutocapitalization(.never).autocorrectionDisabled().font(.caption)
            }
            }

            Section {
                Button {
                    testing = true; result = nil
                    Task {
                        do {
                            let r = try await ai.send(system: "Reply in five words or fewer.", turns: [.init(role: "user", text: "Say hello to iLife.")], maxTokens: 2000)
                            result = "✓ Working: \(r)"
                        } catch { result = "✗ \(error.localizedDescription)" }
                        testing = false
                    }
                } label: {
                    HStack { Text("Test connection"); if testing { Spacer(); ProgressView() } }
                }
                .disabled(!ai.isOn || testing)
                if let result { Text(result).font(.caption).foregroundStyle(result.hasPrefix("✓") ? .green : .orange) }
            }

            Section {
                Label("“Hey Siri, log water in iLife”", systemImage: "drop.fill")
                Label("“Hey Siri, log my weight in iLife”", systemImage: "scalemass.fill")
                Label("“Hey Siri, how's my day in iLife”", systemImage: "sun.max.fill")
                Label("“Hey Siri, ask iLife coach”", systemImage: "sparkles")
            } header: { Text("Siri") } footer: {
                Text("These work hands-free, on your own records. Find more in the Shortcuts app.")
            }

            Section("Privacy") {
                Text(ai.engine == .apple ? "With Apple Intelligence, everything is worked out on this device — nothing is sent anywhere." : "When you use an AI feature, only what that feature needs is sent to Anthropic's API: the InBody image, the meal photo, or — for Coach — a summary of your recent activity, food totals, weight and goals. Your name, phone, email, medical documents and photos in Transformation are never sent. Nothing is sent unless you tap an AI button.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI Assistant")
    }
}

// MARK: - Meal photo → nutrition

struct MealPhotoAISheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AIService.shared
    @State private var image: UIImage?
    @State private var note = ""
    @State private var meal = MealType.suggested()
    @State private var items: [MealAIItem] = []
    @State private var aiNote = ""
    @State private var working = false
    @State private var error: String?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            Form {
                if !ai.isOn {
                    Section {
                        Label("Turn on AI mode first", systemImage: "key.fill").font(.headline)
                        Text("Snap Meal uses AI to work out calories and macros from a photo or a typed description.").font(.caption).foregroundStyle(.secondary)
                        NavigationLink("Set up AI Assistant") { AISettingsView() }
                    }
                } else {
                    Section {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill().frame(height: 200).frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button(image == nil ? "Take a photo of your meal" : "Retake", systemImage: "camera.fill") { Presenter.camera { image = $0; items = [] } }
                        }
                        PhotoSourceButton(onPick: { image = $0; items = [] }) { Label("Choose from Library", systemImage: "photo.on.rectangle") }
                        TextField("Or just type what you ate (e.g. 2 rotis, dal, 1 bowl rice, chaas)", text: $note, axis: .vertical)
                    } footer: {
                        Text("Use a photo, words, or both.")
                    }
                    if (image != nil || !note.trimmingCharacters(in: .whitespaces).isEmpty) && items.isEmpty {
                        Section {
                            Button { analyze() } label: {
                                HStack { Label("Estimate nutrition", systemImage: "sparkles").font(.headline); if working { Spacer(); ProgressView() } }
                            }
                            .disabled(working)
                        }
                    }
                    if let error { Section { Text(error).font(.caption).foregroundStyle(.orange) } }
                    if !items.isEmpty {
                        Section {
                            Picker("Meal", selection: $meal) { ForEach(MealType.allCases) { Label($0.title, systemImage: $0.icon).tag($0) } }
                        }
                        Section {
                            ForEach($items) { $item in
                                VStack(alignment: .leading, spacing: 6) {
                                    TextField("Food", text: $item.name).font(.headline)
                                    TextField("Quantity", text: $item.quantity).font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        num("kcal", $item.calories); num("P", $item.protein); num("C", $item.carbs); num("F", $item.fat)
                                    }
                                }
                            }
                            .onDelete { items.remove(atOffsets: $0) }
                        } header: {
                            Text("Found \(items.count) item\(items.count == 1 ? "" : "s") · \(Int(items.reduce(0) { $0 + $1.calories })) kcal")
                        } footer: {
                            Text((aiNote.isEmpty ? "" : aiNote + " ") + "These are estimates from a photo — correct anything that looks off before saving.")
                        }
                    }
                }
            }
            .navigationTitle("Snap Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !items.isEmpty { ToolbarItem(placement: .confirmationAction) { Button("Log all", action: save) } }
            }
        }
    }

    private func num(_ label: String, _ v: Binding<Double>) -> some View {
        VStack(spacing: 0) {
            TextField("0", value: v, format: .number.precision(.fractionLength(0))).keyboardType(.decimalPad).multilineTextAlignment(.center).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func analyze() {
        working = true; error = nil
        Task {
            do {
                let r: MealAIResult
                if let image { r = try await ai.analyzeMeal(image, note: note) } else { r = try await ai.describeMeal(note) }
                items = r.items
                aiNote = r.note ?? ""
                if items.isEmpty { error = image == nil ? "Couldn't find any food in that description." : "No food found in that photo. Try a closer, brighter shot." }
                Haptics.success()
            } catch { self.error = error.localizedDescription; Haptics.warning() }
            working = false
        }
    }

    private func save() {
        let photo = image.flatMap { ImageTools.jpeg($0, maxSide: 1200) }
        for (i, item) in items.enumerated() {
            let e = FoodEntry(name: item.name, meal: meal, calories: item.calories, protein: item.protein, carbs: item.carbs, fat: item.fat, quantity: item.quantity)
            if i == 0 { e.photo = photo }
            context.insert(e)
            Task { await HealthKitManager.shared.saveFood(e) }
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Coach chat

struct CoachView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var health: HealthKitManager
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject private var ai = AIService.shared
    @MemberQuery(sort: \CoachMessage.date) private var messages: [CoachMessage]
    @MemberQuery(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @MemberQuery(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @MemberQuery(sort: \InBodyScan.date, order: .reverse) private var scans: [InBodyScan]
    @MemberQuery(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @MemberQuery private var profiles: [HealthProfile]
    @State private var draft = ""
    @State private var thinking = false
    @State private var error: String?

    private let starters = ["Review my last 7 days", "What should I eat for dinner to hit my protein?", "Plan my workouts for this week",
                            "Explain my latest InBody result", "Why is my weight not moving?"]

    var body: some View {
        VStack(spacing: 0) {
            if !ai.isOn {
                ContentUnavailableView {
                    Label("Meet your Coach", systemImage: "sparkles")
                } description: {
                    Text("Ask anything about your training, food and progress — answered using your own iLife data. Needs your AI key.")
                } actions: {
                    NavigationLink("Set up AI Assistant") { AISettingsView() }.buttonStyle(.borderedProminent)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty {
                                Text("Ask me anything about your training, food or progress.").font(.subheadline).foregroundStyle(.secondary)
                                ForEach(starters, id: \.self) { s in
                                    Button { send(s) } label: {
                                        Text(s).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).glassCard(cornerRadius: 16, padding: 12)
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                            ForEach(messages) { m in bubble(m).id(m.persistentModelID) }
                            if thinking {
                                HStack(spacing: 8) { ProgressView(); Text("Coach is thinking…").font(.caption).foregroundStyle(.secondary) }.id("thinking")
                            }
                            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.persistentModelID, anchor: .bottom) } }
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask your coach…", text: $draft, axis: .vertical).lineLimit(1...4)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Button { send(draft) } label: {
                        Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white).frame(width: 40, height: 40)
                            .background(theme.current.gradient, in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking)
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
        }
        .background { WallpaperView() }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            if !messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { messages.forEach { context.delete($0) }; try? context.save() }
                }
            }
        }
    }

    private func bubble(_ m: CoachMessage) -> some View {
        let mine = m.role == "user"
        return HStack {
            if mine { Spacer(minLength: 40) }
            Text(LocalizedStringKey(m.text))
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(mine ? AnyShapeStyle(theme.current.gradient) : AnyShapeStyle(.ultraThinMaterial),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(mine ? Color.white : Color.primary)
                .textSelection(.enabled)
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        draft = ""; error = nil
        context.insert(CoachMessage(role: "user", text: q))
        try? context.save()
        var history = messages.suffix(12).map { AIService.Turn(role: $0.role, text: $0.text) }
        if history.last?.text != q { history.append(.init(role: "user", text: q)) }
        if history.first?.role == "assistant" { history.removeFirst() }
        let ctx = contextSummary()
        thinking = true
        Task {
            do {
                let reply = try await ai.coach(history: history, context: ctx)
                context.insert(CoachMessage(role: "assistant", text: reply))
                try? context.save()
                Haptics.tap()
            } catch { self.error = error.localizedDescription }
            thinking = false
        }
    }

    /// Compact, numbers-only summary of the last week — no name, contact details, documents or photos.
    private func contextSummary() -> String {
        let cal = Calendar.current
        let p = profiles.first ?? HealthProfile()
        var lines: [String] = []
        lines.append("Today: \(Date.now.formatted(date: .complete, time: .shortened))")
        lines.append("Goals: steps \(Int(p.stepGoal)), active \(Int(p.activeCalorieGoal)) kcal, exercise \(Int(p.exerciseMinuteGoal)) min, water \(p.waterGoalLitres) L, eat \(Int(p.calorieIntakeGoal)) kcal, protein \(Int(p.proteinGoal)) g" + (p.targetWeightKg > 0 ? ", target weight \(p.targetWeightKg) kg" : ""))
        if p.heightCm > 0 { lines.append("Height \(Int(p.heightCm)) cm" + (p.gender.isEmpty ? "" : ", \(p.gender)")) }
        lines.append("Today so far: steps \(Int(health.steps)), active \(Int(health.activeCalories)) kcal, sleep last night \(String(format: "%.1f", health.sleepHours)) h, resting HR \(Int(health.restingHeartRate)), HRV \(Int(health.hrv)) ms")
        let w = measurements.first(where: { $0.weightKg > 0 })?.weightKg ?? scans.first?.weightKg ?? health.weightKg
        if w > 0 { lines.append("Current weight \(w) kg") }
        if let s = scans.first {
            lines.append("Latest InBody (\(s.date.formatted(date: .abbreviated, time: .omitted))): weight \(s.weightKg) kg, muscle \(s.skeletalMuscleKg) kg, fat \(s.bodyFatPercent)% (\(s.bodyFatKg) kg), BMI \(s.bmi), visceral \(s.visceralFatLevel), BMR \(Int(s.bmrKcal)), score \(Int(s.inBodyScore))")
            if scans.count > 1 { let o = scans[1]; lines.append("Previous InBody (\(o.date.formatted(date: .abbreviated, time: .omitted))): weight \(o.weightKg), muscle \(o.skeletalMuscleKg), fat \(o.bodyFatPercent)%") }
        }
        lines.append("Food, last 7 days (kcal / protein / carbs / fat):")
        for offset in 0..<7 {
            let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now))!
            let items = foods.filter { cal.isDate($0.date, inSameDayAs: day) }
            guard !items.isEmpty else { continue }
            let k = Int(items.reduce(0) { $0 + $1.calories }), pr = Int(items.reduce(0) { $0 + $1.protein })
            let c = Int(items.reduce(0) { $0 + $1.carbs }), f = Int(items.reduce(0) { $0 + $1.fat })
            let names = items.prefix(8).map(\.name).joined(separator: ", ")
            lines.append("- \(day.formatted(.dateTime.weekday(.abbreviated).day())): \(k) / \(pr) / \(c) / \(f) — \(names)")
        }
        lines.append("Workouts, last 14 days:")
        for log in logs.filter({ $0.start > Date.now.addingTimeInterval(-14 * 86400) }).prefix(14) {
            let ex = log.exerciseNames.prefix(6).joined(separator: ", ")
            lines.append("- \(log.start.formatted(.dateTime.weekday(.abbreviated).day())): \(log.name), \(Int(log.durationMinutes)) min, \(Int(log.calories)) kcal, \(log.isPT ? "with trainer" : "self")\(ex.isEmpty ? "" : " — \(ex)")")
        }
        return lines.joined(separator: "\n")
    }
}
