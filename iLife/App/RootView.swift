import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject var session: WorkoutSessionController
    @EnvironmentObject var health: HealthKitManager
    @Environment(\.modelContext) private var context
    @State private var showSession = false
    @AppStorage("onboarded") private var onboarded = false
    @ObservedObject private var members = MemberStore.shared
    @State private var showMembers = false
    @State private var tab = RootView.initialTab

    /// App Store screenshot runs open a specific tab / screen.
    private static var initialTab: Int {
        guard ScreenshotMode.isOn else { return 0 }
        switch ScreenshotMode.screen {
        case "fitness": return 1
        case "nutrition": return 2
        case "health", "medicines", "injury": return 3
        default: return 0
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                NavigationStack { if ScreenshotMode.isOn && ScreenshotMode.screen == "family" { FamilyView() } else { HomeView() } }
            }
            Tab("Fitness", systemImage: "figure.strengthtraining.traditional", value: 1) { NavigationStack { FitnessView() } }
            Tab("Nutrition", systemImage: "fork.knife", value: 2) { NavigationStack { NutritionView() } }
            Tab("Health", systemImage: "heart.text.square.fill", value: 3) {
                NavigationStack {
                    if ScreenshotMode.isOn && ScreenshotMode.screen == "medicines" { MedicineListView() }
                    else if ScreenshotMode.isOn && ScreenshotMode.screen == "injury" { InjuryListView() }
                    else { HealthHubView() }
                }
            }
            Tab("More", systemImage: "gearshape.fill", value: 4) { NavigationStack { SettingsView() } }
        }
        .tabViewStyle(.sidebarAdaptable)   // tab bar on iPhone, sidebar on iPad
        // Apple Health only holds your data — family members see their manually logged entries.
        .environmentObject(members.isMe ? HealthKitManager.shared : HealthKitManager.blank)
        .id(members.uid)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !members.isMe { ViewingMemberBanner { showMembers = true } }
        }
        .sheet(isPresented: $showMembers) { MemberPickerSheet().presentationDetents([.medium, .large]) }
        .safeAreaInset(edge: .bottom) {
            if session.isActive && !showSession {
                ActiveSessionBar { showSession = true }
                    .padding(.horizontal).padding(.bottom, 56)
            }
        }
        .fullScreenCover(isPresented: $showSession) { ActiveWorkoutView() }
        .onChange(of: session.isActive) { _, active in if active { showSession = true } }
        .sheet(isPresented: .constant(!onboarded)) { OnboardingView { onboarded = true } .interactiveDismissDisabled() }
        .task {
            let all = (try? context.fetch(FetchDescriptor<HealthProfile>())) ?? []
            Member.cacheNames(all)
            if !Member.isMe && !all.contains(where: { $0.memberUID == Member.current }) { members.switchTo("") }
            if health.isAuthorized || UserDefaults.standard.bool(forKey: "healthConnected") {
                await HealthKitManager.shared.refreshToday()
                await HealthKitManager.shared.importWorkouts(into: context, notify: false)
            }
        }
    }
}

struct ActiveSessionBar: View {
    @EnvironmentObject var session: WorkoutSessionController
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "figure.run").font(.title3).foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text(session.name).font(.subheadline.bold())
                    Text(Duration.seconds(session.elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if session.heartRate > 0 { Label("\(session.heartRate)", systemImage: "heart.fill").foregroundStyle(.red) }
                Image(systemName: "chevron.up")
            }
            .glassCard(cornerRadius: 20, padding: 12)
        }
        .buttonStyle(.plain)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var health: HealthKitManager
    @EnvironmentObject var music: MusicController
    var done: () -> Void
    var body: some View {
        ZStack {
            WallpaperView()
            ScrollView {
                VStack(spacing: 18) {
                    ILifeLogo(size: 72).padding(.top, 40)
                    Text("Welcome to iLife").font(.largeTitle.bold())
                    Text("Connect your sources once. iLife does the rest.").foregroundStyle(.secondary)
                    OnboardRow(icon: "heart.fill", color: .red, title: "Apple Health",
                               text: "Steps, sleep, heart rate and every workout from Apple Watch and other fitness apps.") {
                        await health.requestAuthorization()
                    }
                    OnboardRow(icon: "bell.badge.fill", color: .orange, title: "Notifications",
                               text: "Workout-detected alerts and your alarms.") {
                        await NotificationService.requestAuthorization()
                    }
                    OnboardRow(icon: "music.note", color: .pink, title: "Apple Music",
                               text: "Auto-play your workout playlist when a session starts.") {
                        await music.requestAccess()
                    }
                    Button("Get Started", action: done)
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large).padding(.top)
                }
                .padding()
            }
        }
    }
}

struct OnboardRow: View {
    let icon: String, color: Color, title: String, text: String
    let action: () async -> Void
    @State private var done = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(done ? "Done" : "Connect") { Task { await action(); done = true } }
                .buttonStyle(.bordered).disabled(done)
        }
        .glassCard()
    }
}
