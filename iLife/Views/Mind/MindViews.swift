import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Mind section (Fitness → Mind)

struct MindSection: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var theme: ThemeManager
    @Query(sort: \MeditationLog.date, order: .reverse) private var logs: [MeditationLog]
    @Query(sort: \CustomMeditation.created, order: .reverse) private var custom: [CustomMeditation]
    @ObservedObject private var ai = AIService.shared
    @State private var category: MCategory?
    @State private var chosen: MeditationScript?
    @State private var showAI = false

    private var streak: Int { InsightsEngine.workoutStreak(logs.map(\.date)) }
    private var weekMinutes: Double {
        let start = Date.now.addingTimeInterval(-7 * 86400)
        return logs.filter { $0.date > start }.reduce(0) { $0 + $1.minutes }
    }
    private var todayMinutes: Double { logs.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.minutes } }

    /// Suggestion for right now, by time of day.
    private var suggested: MeditationScript {
        let id: String
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<9: id = "gratitude"
        case 9..<12: id = "deepwork"
        case 12..<16: id = "reset"
        case 16..<20: id = "letgo"
        case 20..<23: id = "478"
        default: id = "drift"
        }
        return MeditationLibrary.find(id)!
    }

    private var list: [MeditationScript] {
        guard let category else { return MeditationLibrary.all }
        return MeditationLibrary.all.filter { $0.category == category }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Stats
            HStack {
                stat("\(Int(todayMinutes))", "min today")
                Spacer()
                stat("\(streak)🔥", "day streak")
                Spacer()
                stat("\(Int(weekMinutes))", "min this week")
                Spacer()
                NavigationLink { MindHistoryView() } label: {
                    Image(systemName: "clock.arrow.circlepath").font(.title3)
                }
                NavigationLink { MindSettingsView() } label: {
                    Image(systemName: "slider.horizontal.3").font(.title3)
                }
            }
            .glassCard()

            // Suggested now
            Button { chosen = suggested } label: {
                HStack(spacing: 14) {
                    Image(systemName: suggested.icon).font(.title).foregroundStyle(.white)
                        .frame(width: 64, height: 64).background(suggested.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SUGGESTED NOW").font(.caption2.bold()).foregroundStyle(theme.current.gradient)
                        Text(suggested.title).font(.headline).foregroundStyle(Color.primary)
                        Text(suggested.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(theme.current.gradient)
                }
                .glassCard()
            }
            .buttonStyle(PressStyle())

            // AI
            if ai.isOn {
                Button { showAI = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(theme.current.gradient)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Make one for me").font(.subheadline.bold()).foregroundStyle(Color.primary)
                            Text("Tell it how you feel — AI writes a session just for now. Uses one AI request.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .glassCard()
                }
                .buttonStyle(PressStyle())
            }

            // Categories
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(nil, "All", "square.grid.2x2.fill")
                    ForEach(MCategory.allCases) { chip($0, $0.rawValue, $0.icon) }
                }
            }

            if category == nil && !custom.isEmpty {
                Text("My sessions").font(.headline)
                ForEach(custom) { c in
                    SessionRow(script: c.script) { chosen = c.script }
                        .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { context.delete(c); try? context.save() } }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                    Button { chosen = s } label: { SessionTile(script: s) }
                        .buttonStyle(PressStyle())
                        .appear(min(i, 8))
                }
            }
        }
        .sheet(item: $chosen) { SessionSetupSheet(script: $0) }
        .sheet(isPresented: $showAI) { AIMeditationSheet { chosen = $0 } }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) { Text(v).font(.title3.bold()); Text(l).font(.caption2).foregroundStyle(.secondary) }
    }

    private func chip(_ c: MCategory?, _ title: String, _ icon: String) -> some View {
        let on = category == c
        return Button { withAnimation(.spring) { category = c } } label: {
            Label(title, systemImage: icon).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                .background(on ? AnyShapeStyle(theme.current.gradient) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct SessionTile: View {
    let script: MeditationScript
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                script.gradient.frame(height: 92)
                Circle().fill(.white.opacity(0.15)).frame(width: 120).offset(x: 70, y: -30)
                Image(systemName: script.icon).font(.title).foregroundStyle(.white).padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(script.title).font(.subheadline.bold()).foregroundStyle(Color.primary).lineLimit(1)
            Text(script.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
            Text(script.lengths.map { "\($0)" }.joined(separator: " · ") + " min").font(.caption2.bold()).foregroundStyle(.tint)
        }
        .glassCard(cornerRadius: 20, padding: 10)
    }
}

struct SessionRow: View {
    let script: MeditationScript
    let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Image(systemName: script.icon).foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(script.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading) {
                    Text(script.title).font(.subheadline.bold()).foregroundStyle(Color.primary)
                    Text("\(script.lengths.first ?? 5) min · \(script.summary)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.fill").foregroundStyle(.tint)
            }
            .glassCard(cornerRadius: 18, padding: 12)
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Setup before starting

struct SessionSetupSheet: View {
    let script: MeditationScript
    @Environment(\.dismiss) private var dismiss
    @AppStorage("medLang") private var langRaw = MLang.english.rawValue
    @AppStorage("medSound") private var soundRaw = Soundscape.rain.rawValue
    @State private var minutes = 10
    @State private var moodBefore = 0
    @State private var showPlayer = false
    @State private var showFile = false
    @State private var showPlaylists = false
    @State private var fileName = UserDefaults.standard.string(forKey: "medFileName") ?? ""
    @ObservedObject private var music = MusicController.shared

    private var lang: MLang { MLang(rawValue: langRaw) ?? .english }
    private var sound: Soundscape { Soundscape(rawValue: soundRaw) ?? .rain }
    private var isCustom: Bool { script.id.hasPrefix("custom-") || script.id.hasPrefix("ai-") }

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("meditation-audio")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: script.icon).font(.largeTitle).foregroundStyle(.white).frame(width: 72, height: 72)
                            .background(script.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(script.title(lang)).font(.title3.bold())
                            Text(script.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !isCustom {
                    Section("Length") {
                        Picker("Minutes", selection: $minutes) { ForEach(script.lengths, id: \.self) { Text("\($0) min").tag($0) } }
                            .pickerStyle(.segmented)
                    }
                    Section("Voice") {
                        Picker("Language", selection: $langRaw) { ForEach(MLang.allCases) { Text($0.title).tag($0.rawValue) } }
                            .pickerStyle(.segmented)
                        if let v = Voices.chosen(lang) {
                            HStack { Text("Voice"); Spacer(); Text("\(v.name) · \(Voices.qualityName(v))").foregroundStyle(.secondary) }
                            if v.quality == .default {
                                NavigationLink { MindSettingsView() } label: { Label("Get a more natural voice", systemImage: "waveform.badge.plus").font(.caption) }
                            }
                        }
                    }
                }
                Section("Background sound") {
                    Picker("Sound", selection: $soundRaw) {
                        ForEach(Soundscape.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
                    }
                    if sound == .appleMusic {
                        if music.authorization != .authorized {
                            Button("Connect Apple Music") { Task { await music.requestAccess() } }
                        } else {
                            Button { showPlaylists = true } label: {
                                HStack { Text("Playlist").foregroundStyle(Color.primary); Spacer(); Text(music.selectedPlaylist?.name ?? "Choose").foregroundStyle(.secondary) }
                            }
                            Text("Apple Music volume follows your phone's volume buttons.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if sound == .myFile {
                        Button(fileName.isEmpty ? "Choose an audio file" : "File: \(fileName)", systemImage: "folder") { showFile = true }
                    }
                    if sound == .binaural { Text("Binaural tones need headphones.").font(.caption2).foregroundStyle(.secondary) }
                }
                Section("How do you feel right now?") {
                    MoodPicker(mood: $moodBefore)
                }
            }
            .navigationTitle("Meditation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Haptics.thump()
                    showPlayer = true
                } label: {
                    Label("Begin \(isCustom ? "" : "· \(minutes) min")", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                .disabled(sound == .myFile && fileName.isEmpty)
                .padding()
            }
            .onAppear { minutes = script.defaultLength }
            .sheet(isPresented: $showPlaylists) { PlaylistPicker() }
            .fullScreenCover(isPresented: $showPlayer, onDismiss: { dismiss() }) {
                MeditationPlayerView(script: script, minutes: isCustom ? (script.lengths.first ?? 5) : minutes, lang: script.fixedLang ?? lang,
                                     sound: sound, moodBefore: moodBefore)
            }
            .fileImporter(isPresented: $showFile, allowedContentTypes: [.audio]) { res in
                guard case .success(let url) = res else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: Self.fileURL)
                if (try? FileManager.default.copyItem(at: url, to: Self.fileURL)) != nil {
                    fileName = url.lastPathComponent
                    UserDefaults.standard.set(fileName, forKey: "medFileName")
                }
            }
        }
    }
}

struct MoodPicker: View {
    @Binding var mood: Int
    private let faces = ["😣", "😕", "😐", "🙂", "😌"]
    var body: some View {
        HStack {
            ForEach(1...5, id: \.self) { i in
                Button { mood = mood == i ? 0 : i; Haptics.tap() } label: {
                    Text(faces[i - 1]).font(.system(size: 34))
                        .scaleEffect(mood == i ? 1.25 : 1).opacity(mood == 0 || mood == i ? 1 : 0.4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: mood)
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Player

struct MeditationPlayerView: View {
    let script: MeditationScript
    let minutes: Int
    let lang: MLang
    let sound: Soundscape
    let moodBefore: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var player = MeditationPlayer.shared
    @State private var moodAfter = 0
    @State private var confirmEnd = false
    @State private var saved = false
    @State private var showControls = false
    @State private var glow = false

    var body: some View {
        ZStack {
            script.gradient.opacity(0.85).ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()
            if player.state == .finished {
                finishedView
            } else {
                running
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            player.start(script, minutes: minutes, language: lang, soundscape: sound,
                         fileURL: sound == .myFile ? SessionSetupSheet.fileURL : nil)
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { glow = true }
        }
        .onDisappear { if player.state != .finished { player.stop() } }
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and save the time so far") { endEarly(save: true) }
            Button("End without saving", role: .destructive) { endEarly(save: false) }
        }
    }

    private var circleScale: CGFloat {
        switch player.breath {
        case .inhale: 1.0
        case .hold: 1.0
        case .exhale, .rest: 0.55
        case nil: glow ? 0.78 : 0.7
        }
    }

    private var running: some View {
        VStack(spacing: 20) {
            HStack {
                Button { confirmEnd = true } label: { Image(systemName: "xmark").font(.headline).padding(12).background(.ultraThinMaterial, in: Circle()) }
                Spacer()
                Text(script.title(lang)).font(.headline)
                Spacer()
                Button { showControls.toggle() } label: { Image(systemName: "slider.horizontal.3").font(.headline).padding(12).background(.ultraThinMaterial, in: Circle()) }
            }
            .padding(.horizontal)

            Spacer()

            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.35 - Double(i) * 0.1), .clear], center: .center, startRadius: 10, endRadius: 170))
                        .frame(width: 300 - CGFloat(i) * 40)
                        .scaleEffect(circleScale + CGFloat(i) * 0.08)
                }
                Circle().stroke(.white.opacity(0.5), lineWidth: 2).frame(width: 220).scaleEffect(circleScale)
                VStack(spacing: 6) {
                    if player.pulseCount > 0 {
                        Text("\(player.pulseCount)").font(.system(size: 54, weight: .bold, design: .rounded)).contentTransition(.numericText())
                    } else if !player.breathLabel.isEmpty {
                        Text(player.breathLabel).font(.title2.weight(.semibold)).multilineTextAlignment(.center).padding(.horizontal, 30)
                            .contentTransition(.opacity)
                    }
                }
            }
            .frame(height: 320)
            .animation(.easeInOut(duration: player.breath == nil ? 3 : player.breathSeconds), value: player.breath)

            Text(player.caption)
                .font(.title3).multilineTextAlignment(.center).padding(.horizontal, 28)
                .frame(minHeight: 90)
                .opacity(player.breathLabel.isEmpty ? 1 : 0.0)
                .animation(.easeInOut(duration: 0.8), value: player.caption)

            Spacer()

            VStack(spacing: 8) {
                ProgressView(value: min(player.elapsed, player.total), total: max(player.total, 1)).tint(.white)
                HStack {
                    Text(Duration.seconds(player.elapsed).formatted(.time(pattern: .minuteSecond)))
                    Spacer()
                    Text("-" + Duration.seconds(max(0, player.total - player.elapsed)).formatted(.time(pattern: .minuteSecond)))
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 30)

            Button { player.togglePause() } label: {
                Image(systemName: player.paused ? "play.fill" : "pause.fill").font(.title).frame(width: 76, height: 76)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(PressStyle())
            .padding(.bottom, 30)
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showControls) { PlayerControlsSheet().presentationDetents([.medium]) }
    }

    private var finishedView: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).symbolEffect(.bounce, value: saved)
            Text("Well done").font(.largeTitle.bold())
            Text("\(Int((player.elapsed / 60).rounded())) minutes of \(script.title(lang))").foregroundStyle(.white.opacity(0.8))
            VStack(spacing: 10) {
                Text("How do you feel now?").font(.headline)
                MoodPicker(mood: $moodAfter)
                if moodBefore > 0 && moodAfter > 0 && moodAfter > moodBefore {
                    Text("Your mood lifted \(moodAfter - moodBefore) step\(moodAfter - moodBefore == 1 ? "" : "s").").font(.caption).foregroundStyle(.green)
                }
            }
            .padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
            Spacer()
            Button {
                save(minutes: player.elapsed / 60, completed: true)
                dismiss()
            } label: {
                Text("Save & close").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large).tint(.white).foregroundStyle(.black)
            .padding()
        }
        .foregroundStyle(.white)
    }

    private func endEarly(save shouldSave: Bool) {
        let mins = player.elapsed / 60
        player.stop()
        if shouldSave && mins >= 0.5 { save(minutes: mins, completed: false) }
        dismiss()
    }

    private func save(minutes mins: Double, completed: Bool) {
        guard !saved else { return }
        saved = true
        let log = MeditationLog(date: player.startedAt ?? .now, sessionID: script.id, title: script.title(lang), minutes: (mins * 10).rounded() / 10)
        log.category = script.category.rawValue; log.language = lang.rawValue; log.soundscape = sound.rawValue
        log.moodBefore = moodBefore; log.moodAfter = moodAfter; log.completed = completed
        context.insert(log)
        try? context.save()
        let start = player.startedAt ?? Date.now.addingTimeInterval(-mins * 60)
        Task { await HealthKitManager.shared.saveMindful(start: start, end: start.addingTimeInterval(mins * 60)) }
        player.reset()
        if completed { Celebration.shared.fire("Meditation complete", subtitle: "\(Int(mins.rounded())) mindful minutes saved to Apple Health", icon: "leaf.fill") }
    }
}

struct PlayerControlsSheet: View {
    @ObservedObject private var player = MeditationPlayer.shared
    var body: some View {
        NavigationStack {
            Form {
                Section("Volume") {
                    HStack { Image(systemName: "person.wave.2.fill"); Slider(value: $player.voiceVolume, in: 0...1) }
                    HStack { Image(systemName: "music.note"); Slider(value: $player.musicVolume, in: 0...1) }
                }
                Section {
                    HStack { Image(systemName: "tortoise.fill"); Slider(value: $player.voiceRate, in: 0.3...0.55); Image(systemName: "hare.fill") }
                } header: { Text("Voice speed") } footer: { Text("Speed changes apply from the next sentence.") }
            }
            .navigationTitle("Sound").navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - AI session

struct AIMeditationSheet: View {
    let onReady: (MeditationScript) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("medLang") private var langRaw = MLang.english.rawValue
    @State private var feeling = ""
    @State private var minutes = 10
    @State private var working = false
    @State private var error: String?
    @State private var keep = true

    private let quick = ["Anxious before tomorrow", "Can't switch off after work", "Tired but restless", "Need focus", "Sore after training", "Angry, want to calm down", "Can't sleep"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("How do you feel, or what do you need right now?", text: $feeling, axis: .vertical).lineLimit(2...5)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(quick, id: \.self) { q in Button(q) { feeling = q }.font(.caption).buttonStyle(.bordered) } }
                    }
                }
                Section {
                    Picker("Length", selection: $minutes) { ForEach([5, 10, 15, 20], id: \.self) { Text("\($0) min").tag($0) } }.pickerStyle(.segmented)
                    Picker("Language", selection: $langRaw) { ForEach(MLang.allCases) { Text($0.title).tag($0.rawValue) } }.pickerStyle(.segmented)
                    Toggle("Save to My sessions", isOn: $keep)
                } footer: {
                    Text("Sends what you typed plus a short summary of today's sleep and activity. Uses one AI request.")
                }
                if let error { Section { Text(error).font(.caption).foregroundStyle(.orange) } }
            }
            .navigationTitle("Make one for me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else { Button("Create") { create() } }
                }
            }
        }
    }

    private func create() {
        working = true; error = nil
        let lang = MLang(rawValue: langRaw) ?? .english
        let h = HealthKitManager.shared
        let ctx = "Sleep last night \(String(format: "%.1f", h.sleepHours)) h; steps today \(Int(h.steps)); exercise \(Int(h.exerciseMinutes)) min; resting HR \(Int(h.restingHeartRate)); time now \(Date.now.formatted(date: .omitted, time: .shortened))"
        Task {
            do {
                let r = try await AIService.shared.makeMeditation(feeling: feeling, minutes: minutes, language: lang, context: ctx)
                guard !r.steps.isEmpty else { throw AIError.empty }
                let json = (try? JSONEncoder().encode(r.steps)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                let script: MeditationScript
                if keep {
                    let c = CustomMeditation(title: r.title, language: lang.rawValue, stepsJSON: json)
                    context.insert(c); try? context.save()
                    script = c.script
                } else {
                    script = MeditationLibrary.custom(id: "ai-\(UUID().uuidString)", title: r.title, steps: r.steps, lang: lang)
                }
                working = false
                dismiss()
                try? await Task.sleep(for: .milliseconds(450))
                onReady(script)
            } catch {
                self.error = error.localizedDescription
                working = false
            }
        }
    }
}

// MARK: - History

struct MindHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MeditationLog.date, order: .reverse) private var logs: [MeditationLog]

    private var byDay: [(Date, Double)] {
        let cal = Calendar.current
        return (0..<14).reversed().map { off in
            let d = cal.date(byAdding: .day, value: -off, to: cal.startOfDay(for: .now))!
            return (d, logs.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.minutes })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last 14 days").font(.headline)
                    WeekChart(title: "Mindful minutes", values: byDay.map(\.1), end: Calendar.current.startOfDay(for: .now), color: .mint, goal: 10)
                    let rated = logs.filter { $0.moodBefore > 0 && $0.moodAfter > 0 }
                    if !rated.isEmpty {
                        let lift = Double(rated.reduce(0) { $0 + ($1.moodAfter - $1.moodBefore) }) / Double(rated.count)
                        Label(String(format: "On average your mood changes by %+.1f after a session", lift), systemImage: "face.smiling")
                            .font(.caption).foregroundStyle(lift >= 0 ? Color.green : Color.orange)
                    }
                    Text("\(logs.count) sessions · \(Int(logs.reduce(0) { $0 + $1.minutes })) minutes in total").font(.caption).foregroundStyle(.secondary)
                }
                .glassCard()

                ForEach(logs.prefix(100)) { l in
                    HStack(spacing: 12) {
                        let s = MeditationLibrary.find(l.sessionID)
                        Image(systemName: s?.icon ?? "sparkles").foregroundStyle(.white).frame(width: 40, height: 40)
                            .background(s?.gradient ?? LinearGradient(colors: [.purple, .cyan], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.title).font(.subheadline.bold())
                            Text(l.date.formatted(date: .abbreviated, time: .shortened) + (l.completed ? "" : " · ended early")).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if l.moodBefore > 0 && l.moodAfter > 0 { Text("\(["😣","😕","😐","🙂","😌"][l.moodBefore-1])→\(["😣","😕","😐","🙂","😌"][l.moodAfter-1])") }
                        Text("\(Int(l.minutes.rounded())) min").font(.subheadline.bold())
                    }
                    .glassCard(cornerRadius: 16, padding: 12)
                    .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { context.delete(l); try? context.save() } }
                }
            }
            .padding()
        }
        .iLifeScreen()
        .navigationTitle("Meditation History")
    }
}

// MARK: - Settings: voices, reminder

struct MindSettingsView: View {
    @AppStorage("medReminderOn") private var reminderOn = false
    @AppStorage("medReminderMinutes") private var reminderMinutes = 21 * 60 + 45
    @State private var refresh = 0
    @State private var preview = AVSpeechSynthesizer()

    var body: some View {
        Form {
            ForEach(MLang.allCases) { lang in
                Section(lang == .english ? "English voice" : "Hindi voice") {
                    let voices = Voices.available(lang)
                    if voices.isEmpty {
                        Text("No voice installed for this language.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(voices, id: \.identifier) { v in
                        let selected = Voices.chosen(lang)?.identifier == v.identifier
                        Button {
                            UserDefaults.standard.set(v.identifier, forKey: "medVoice.\(lang.rawValue)")
                            refresh += 1
                            let u = AVSpeechUtterance(string: lang == .english ? "Take a slow breath in, and let it go." : "धीरे से साँस लीजिए, और छोड़ दीजिए।")
                            u.voice = v; u.rate = MeditationPlayer.shared.voiceRate
                            preview.stopSpeaking(at: .immediate); preview.speak(u)
                        } label: {
                            HStack {
                                Text(v.name).foregroundStyle(Color.primary)
                                Text(Voices.qualityName(v)).font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(v.quality == .default ? Color.gray.opacity(0.25) : Color.green.opacity(0.3), in: Capsule())
                                Spacer()
                                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
            }
            .id(refresh)
            Section {
                Text("For a much more natural voice: iPhone Settings → Accessibility → Spoken Content → Voices → English (India) or Hindi → download a voice marked Enhanced or Premium. Then come back here and pick it. Tap any voice to hear it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Daily meditation reminder", isOn: $reminderOn)
                if reminderOn {
                    DatePicker("Time", selection: Binding(
                        get: { Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now },
                        set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); reminderMinutes = (c.hour ?? 21) * 60 + (c.minute ?? 45) }),
                        displayedComponents: .hourAndMinute)
                }
            } header: { Text("Reminder") }
        }
        .navigationTitle("Meditation Settings")
        .onChange(of: reminderOn) { _, _ in scheduleReminder() }
        .onChange(of: reminderMinutes) { _, _ in scheduleReminder() }
    }

    private func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["ilife.meditation.daily"])
        guard reminderOn else { return }
        Task {
            await NotificationService.requestAuthorization()
            let c = UNMutableNotificationContent()
            c.title = "Time to breathe 🧘"
            c.body = "A few quiet minutes in iLife — your streak is waiting."
            c.sound = .default
            var comps = DateComponents(); comps.hour = reminderMinutes / 60; comps.minute = reminderMinutes % 60
            try? await center.add(UNNotificationRequest(identifier: "ilife.meditation.daily", content: c,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        }
    }
}
