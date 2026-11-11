import SwiftUI
import SwiftData

@main
struct iLifeApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var lock = BiometricLock()
    @StateObject private var health = HealthKitManager.shared
    @StateObject private var session = WorkoutSessionController.shared
    @StateObject private var music = MusicController.shared
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer

    init() {
        let schema = Schema(ILifeSchema.models)
        // Private iCloud database — syncs iPhone ⇄ iPad automatically.
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.jondhale.ilife"))
        if let c = try? ModelContainer(for: schema, configurations: cloud) {
            container = c
        } else {
            // iCloud unavailable (signed out / first launch issues): keep working locally.
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            container = try! ModelContainer(for: schema, configurations: local)
        }
        if UserDefaults.standard.bool(forKey: "healthConnected") {
            HealthKitManager.shared.enableBackgroundWorkoutDetection(container: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                if lock.lockEnabled && !lock.isUnlocked {
                    LockScreenView().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: lock.isUnlocked)
            .environmentObject(theme)
            .environmentObject(lock)
            .environmentObject(health)
            .environmentObject(session)
            .environmentObject(music)
            .tint(theme.theme.accent)
            .preferredColorScheme(theme.theme.colorScheme)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Keep unlocked during an active workout so the session screen stays usable.
                if !session.isActive { lock.lock() }
            case .active:
                Task { await health.refreshToday() }
            default: break
            }
        }
    }
}
