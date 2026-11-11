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

    func lock() { if lockEnabled { isUnlocked = false } }

    func unlock() async {
        guard lockEnabled else { isUnlocked = true; return }
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
        } catch {
            errorText = "Authentication failed. Tap to try again."
        }
    }
}

struct LockScreenView: View {
    @EnvironmentObject var lock: BiometricLock
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
        .task { await lock.unlock() }
    }
}
