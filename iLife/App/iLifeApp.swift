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
        // On-device only. App Store guideline 5.1.3(ii): apps may not store personal health
        // information in iCloud. Same store file as before, so existing data is kept.
        if ScreenshotMode.isOn {
            ScreenshotMode.prepareDefaults()
            let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            container = try! ModelContainer(for: schema, configurations: mem)
            MainActor.assumeIsolated {
                ScreenshotMode.seed(container.mainContext)
                ScreenshotMode.fakeHealth(HealthKitManager.shared)
            }
            return
        }
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        container = try! ModelContainer(for: schema, configurations: local)
        MediaStore.shared.attach(container)
        AICoordinator.shared.attach(container)
        AICoordinator.shared.scheduleNotifications()
        if UserDefaults.standard.bool(forKey: "healthConnected") {
            HealthKitManager.shared.enableBackgroundWorkoutDetection(container: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                CelebrationOverlay()
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
            .tint(theme.current.accent)
            .preferredColorScheme(theme.current.colorScheme)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Keep unlocked during an active workout so the session screen stays usable.
                if !session.isActive { lock.lock() }
            case .active:
                Task {
                    await health.refreshToday()
                    if lock.isUnlocked || !lock.lockEnabled { await AICoordinator.shared.appBecameActive() }
                }
            default: break
            }
        }
    }
}
