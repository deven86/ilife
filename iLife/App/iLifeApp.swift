import SwiftUI
import SwiftData

@main
struct iLifeApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var lock = BiometricLock()
    @StateObject private var health = HealthKitManager.shared
    @StateObject private var session = WorkoutSessionController.shared
    @StateObject private var music = MusicController.shared
    @StateObject private var account = Account.shared
    @StateObject private var data = AppData.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Each Apple ID has its own database (Account.swift). Nothing opens until someone signs in.
        MainActor.assumeIsolated {
            if ScreenshotMode.isOn {
                ScreenshotMode.prepareDefaults()
                AppData.shared.openScreenshots()
            } else {
                AppData.shared.openIfSignedIn()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let c = data.container {
                    RootView().modelContainer(c).id(data.generation)
                } else {
                    SignInFlow()
                }
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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Keep unlocked during an active workout so the session screen stays usable.
                if !session.isActive { lock.lock() }
            case .active:
                Task {
                    if !ScreenshotMode.isOn { await account.checkStillAuthorized() }
                    await health.refreshToday()
                    if lock.isUnlocked || !lock.lockEnabled { await AICoordinator.shared.appBecameActive() }
                }
            default: break
            }
        }
    }
}
