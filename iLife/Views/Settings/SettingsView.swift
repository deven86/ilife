import SwiftUI
import SwiftData
import PhotosUI
import CloudKit

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var lock: BiometricLock
    @EnvironmentObject var health: HealthKitManager
    @EnvironmentObject var music: MusicController
    @Environment(\.modelContext) private var context
    @Query private var profiles: [HealthProfile]
    @AppStorage("userName") private var userName = "Devendra"
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var iCloudStatus = "Checking…"
    @State private var showPlaylists = false

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Your name", text: $userName)
                if let p = profiles.first {
                    NavigationLink("Goals & Targets") { GoalsView(profile: p) }
                } else {
                    Button("Set goals & targets") { context.insert(HealthProfile()) }
                }
            }

            Section("Theme") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AppTheme.allCases) { t in
                            Button {
                                theme.theme = t
                                theme.setWallpaper(nil)
                            } label: {
                                VStack(spacing: 6) {
                                    ThemeWallpaper(theme: t)
                                        .frame(width: 88, height: 130)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14)
                                            .stroke(theme.theme == t && theme.customWallpaper == nil ? t.accent : .clear, lineWidth: 3))
                                    Text(t.title).font(.caption2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                PhotosPicker(selection: $wallpaperItem, matching: .images) {
                    Label("Use my own photo as wallpaper", systemImage: "photo.on.rectangle")
                }
                if theme.customWallpaper != nil {
                    Button("Remove custom wallpaper", role: .destructive) { theme.setWallpaper(nil) }
                }
            }

            Section("Security") {
                Toggle("Lock with \(lock.biometryName)", isOn: $lock.lockEnabled)
                Text("iLife locks every time it goes to the background (except during an active workout).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Connected sources") {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill").foregroundStyle(.red)
                    Spacer()
                    Button(UserDefaults.standard.bool(forKey: "healthConnected") ? "Re-check" : "Connect") {
                        Task {
                            await health.requestAuthorization()
                            await health.refreshToday()
                            await health.importWorkouts(into: context, notify: false)
                        }
                    }
                }
                Label("Apple Watch — via Apple Health, automatic", systemImage: "applewatch")
                NavigationLink { SourcesInfoView() } label: { Label("Google Fit, Garmin, Fitbit & others", systemImage: "point.3.connected.trianglepath.dotted") }
            }

            Section("Apple Music") {
                if music.authorization == .authorized {
                    Button { showPlaylists = true } label: {
                        HStack { Text("Workout playlist"); Spacer(); Text(music.selectedPlaylist?.name ?? "First playlist").foregroundStyle(.secondary) }
                    }
                    Toggle("Auto-play when a workout starts", isOn: $music.autoPlay)
                } else {
                    Button("Connect Apple Music") { Task { await music.requestAccess() } }
                }
                if let e = music.lastError { Text(e).font(.caption).foregroundStyle(.orange) }
            }

            Section("Reminders & alarms") {
                NavigationLink { AlarmsView() } label: { Label("Alarms", systemImage: "alarm.fill") }
            }

            Section("iCloud") {
                HStack { Label("iCloud sync", systemImage: "icloud.fill"); Spacer(); Text(iCloudStatus).foregroundStyle(.secondary) }
                Text("All iLife data is stored in your private iCloud database and syncs between your iPhone and iPad.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack { Text("Version"); Spacer(); Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "").foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .background { WallpaperView() }
        .navigationTitle("More")
        .sheet(isPresented: $showPlaylists) { PlaylistPicker() }
        .onChange(of: wallpaperItem) { _, item in
            Task {
                if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) { theme.setWallpaper(img) }
            }
        }
        .task {
            let status = try? await CKContainer(identifier: "iCloud.com.jondhale.ilife").accountStatus()
            iCloudStatus = status == .available ? "On" : "Sign in to iCloud"
        }
    }
}

struct GoalsView: View {
    @Bindable var profile: HealthProfile
    var body: some View {
        Form {
            Section("Daily targets (shown in the widget)") {
                Stepper("Steps: \(Int(profile.stepGoal).formatted())", value: $profile.stepGoal, in: 2000...40000, step: 500)
                Stepper("Active calories: \(Int(profile.activeCalorieGoal)) kcal", value: $profile.activeCalorieGoal, in: 100...2000, step: 50)
                Stepper("Exercise: \(Int(profile.exerciseMinuteGoal)) min", value: $profile.exerciseMinuteGoal, in: 10...240, step: 5)
                Stepper("Water: \(profile.waterGoalLitres.clean) L", value: $profile.waterGoalLitres, in: 1...6, step: 0.25)
            }
            Section("Diet") {
                Stepper("Calories eaten: \(Int(profile.calorieIntakeGoal)) kcal", value: $profile.calorieIntakeGoal, in: 1000...5000, step: 50)
                Stepper("Protein: \(Int(profile.proteinGoal)) g", value: $profile.proteinGoal, in: 30...300, step: 5)
            }
            Section("Weight goal") {
                Stepper("Start weight: \(profile.startWeightKg.clean) kg", value: $profile.startWeightKg, in: 0...250, step: 0.5)
                Stepper("Target weight: \(profile.targetWeightKg.clean) kg", value: $profile.targetWeightKg, in: 0...250, step: 0.5)
                DatePicker("Target date", selection: $profile.targetDate, displayedComponents: .date)
                Stepper("Height: \(profile.heightCm.clean) cm", value: $profile.heightCm, in: 0...230, step: 1)
            }
        }
        .navigationTitle("Goals")
    }
}

struct SourcesInfoView: View {
    var body: some View {
        List {
            Section {
                Text("On iPhone, every fitness device reaches iLife through Apple Health. If a device's app writes to Apple Health, iLife sees its workouts, steps, sleep and heart rate automatically.")
            }
            Section("How to connect") {
                Label("Apple Watch — automatic", systemImage: "applewatch")
                Label("Garmin — Garmin Connect app → Settings → Health app", systemImage: "figure.run")
                Label("Strava / Nike Run Club — enable Apple Health in each app", systemImage: "figure.outdoor.cycle")
                Label("Fitbit / Google — use a sync app that writes Fitbit data into Apple Health", systemImage: "arrow.triangle.2.circlepath")
                Label("Smart scales (InBody, Withings, Mi) — enable Apple Health in the scale's app", systemImage: "scalemass")
            }
            Section("Google Fit") {
                Text("Google has retired the Google Fit APIs, and its replacement (Health Connect) only runs on Android. There is no way for an iPhone app to read Google Fit directly, so Apple Health is the bridge.")
                    .font(.callout)
            }
        }
        .navigationTitle("Other Devices")
    }
}

struct AlarmsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AppAlarm.hour) private var alarms: [AppAlarm]
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(alarms) { a in
                HStack {
                    VStack(alignment: .leading) {
                        Text(a.timeText).font(.system(size: 34, weight: .light, design: .rounded))
                        Text("\(a.label) · \(days(a))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { a.isOn }, set: { a.isOn = $0; AlarmService.schedule(a) })).labelsHidden()
                }
            }
            .onDelete { idx in idx.forEach { AlarmService.cancel(alarms[$0]); context.delete(alarms[$0]) } }
        }
        .navigationTitle("Alarms")
        .toolbar { Button("Add", systemImage: "plus") { showAdd = true } }
        .sheet(isPresented: $showAdd) { AddAlarmSheet() }
        .overlay { if alarms.isEmpty { ContentUnavailableView("No alarms", systemImage: "alarm", description: Text("Add workout, water, meal or medicine alarms.")) } }
    }

    private func days(_ a: AppAlarm) -> String {
        if a.weekdays.isEmpty || a.weekdays.count == 7 { return "Every day" }
        return a.weekdays.map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: " ")
    }
}

struct AddAlarmSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var label = "Workout"
    @State private var time = Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: .now)!
    @State private var weekdays: Set<Int> = []
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute).datePickerStyle(.wheel)
                Picker("Type", selection: $label) {
                    ForEach(["Workout", "Drink water", "Breakfast", "Lunch", "Dinner", "Medicine", "Sleep"], id: \.self) { Text($0) }
                }
                Section("Repeat (none = every day)") {
                    ForEach(1...7, id: \.self) { d in
                        Button {
                            if weekdays.contains(d) { weekdays.remove(d) } else { weekdays.insert(d) }
                        } label: {
                            HStack { Text(Calendar.current.weekdaySymbols[d - 1]); Spacer(); if weekdays.contains(d) { Image(systemName: "checkmark") } }
                        }
                    }
                }
            }
            .navigationTitle("New Alarm")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                        let a = AppAlarm(label: label, hour: c.hour ?? 6, minute: c.minute ?? 30, weekdays: weekdays.sorted())
                        context.insert(a)
                        Task {
                            await NotificationService.requestAuthorization()
                            AlarmService.schedule(a)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
