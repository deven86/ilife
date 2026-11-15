import Foundation
import LocalAuthentication
import SwiftUI

/// Face ID / Touch ID gate (falls back to device passcode).
@MainActor
final class BiometricLock: ObservableObject {
    @Published var isUnlocked = false
    @Published var errorText: String?
    @AppStorage("lockEnabled") var lockEnabled = true

    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func lock() { if lockEnabled { isUnlocked = false; autoPrompted = false } }

    private var inProgress = false
    /// Face ID is offered automatically once each time the app opens — not again after you cancel.
    private var autoPrompted = false

    func autoUnlock() async {
        guard !autoPrompted, UIApplication.shared.applicationState == .active else { return }
        autoPrompted = true
        await unlock()
    }

    func unlock() async {
        guard lockEnabled else { isUnlocked = true; return }
        guard !inProgress, !isUnlocked else { return }
        // Face ID can only be shown while the app is in front; at launch it may not be yet.
        guard UIApplication.shared.applicationState == .active else { return }
        inProgress = true
        defer { inProgress = false }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // No passcode on device — nothing to authenticate against.
            isUnlocked = true
            return
        }
        do {
            isUnlocked = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your iLife health data")
            errorText = nil
        } catch let e as LAError {
            switch e.code {
            case .systemCancel, .appCancel, .notInteractive:
                errorText = nil                      // interrupted by iOS — try again when the app is active
                autoPrompted = false
            case .userCancel:
                errorText = nil                      // you cancelled — the button stays on screen
            case .biometryLockout:
                errorText = "\(biometryName) is locked after too many tries. Use your passcode."
            default:
                errorText = "\(biometryName) didn't recognise you. Tap to try again."
            }
        } catch {
            errorText = "Couldn't unlock. Tap to try again."
        }
    }
}

struct LockScreenView: View {
    @EnvironmentObject var lock: BiometricLock
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ZStack {
            WallpaperView()
            VStack(spacing: 22) {
                Spacer()
                ILifeLogo(size: 84)
                Text("iLife").font(.system(size: 44, weight: .bold, design: .rounded))
                Text("Live Healthy • Live Strong • Live Better").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: lock.biometryName == "Touch ID" ? "touchid" : "faceid")
                        .font(.headline).padding(.horizontal, 28).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                if let e = lock.errorText { Text(e).font(.footnote).foregroundStyle(.red) }
                Spacer().frame(height: 60)
            }
        }
        .task {
            // Give iOS a moment to finish showing the app, then ask for Face ID.
            try? await Task.sleep(for: .milliseconds(350))
            await lock.autoUnlock()
        }
        .onChange(of: phase) { _, p in
            if p == .active { Task { try? await Task.sleep(for: .milliseconds(250)); await lock.autoUnlock() } }
        }
    }
}
