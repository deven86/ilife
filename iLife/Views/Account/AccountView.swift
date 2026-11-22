import SwiftUI
import SwiftData

/// More → Account & iCloud: who is signed in, where the records live, sign out, delete.
struct AccountView: View {
    @ObservedObject private var account = Account.shared
    @ObservedObject private var data = AppData.shared
    @Query private var profiles: [HealthProfile]
    @State private var cloud = CloudChoice.isOn
    @State private var message: String?
    @State private var confirmCloudOff = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleting = false

    private var me: HealthProfile? { profiles.first { $0.memberUID.isEmpty } }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AvatarView(data: me?.avatar, name: me?.fullName ?? "?", size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(me?.fullName.isEmpty == false ? me!.fullName : "Your account").font(.headline)
                        Label("Signed in with Apple", systemImage: "apple.logo").font(.caption).foregroundStyle(.secondary)
                        if !account.email.isEmpty { Text(account.displayEmail).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            } footer: {
                Text("Your Apple ID is your iLife login. Each Apple ID has its own separate records on this device.")
            }

            Section {
                Toggle(isOn: Binding(get: { cloud }, set: { newValue in
                    if newValue { Task { await turnOn() } } else { confirmCloudOff = true }
                })) {
                    Label("Sync with my iCloud", systemImage: "icloud.fill")
                }
                if let p = data.cloudProblem { Text(p).font(.caption).foregroundStyle(.orange) }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            } header: { Text("Storage") } footer: {
                Text(cloud
                     ? "Your records are on this device and in your private iCloud, so your iPhone and iPad stay in step. Only your Apple ID can read them; there is no iLife server."
                     : "Your records stay only on this device (and in your encrypted iPhone backup). Turn on iCloud to sync your iPhone and iPad and keep your data when you change phones.")
            }

            Section {
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { confirmSignOut = true }
                Button("Delete my account and data", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    .disabled(deleting)
                if deleting { ProgressView() }
            } footer: {
                Text("Signing out keeps your records on this device for when you sign in again. Deleting removes them from this device\(cloud ? " and from your iCloud" : "") for good. To also stop using your Apple ID with iLife: iPhone Settings → your name → Sign in with Apple → iLife.")
            }
        }
        .navigationTitle("Account & iCloud")
        .confirmationDialog("Stop syncing with iCloud? Your records stay on this device; the copy in iCloud is kept until you delete your account.", isPresented: $confirmCloudOff, titleVisibility: .visible) {
            Button("Stop syncing") { CloudChoice.isOn = false; cloud = false; AppData.shared.reopen() }
        }
        .confirmationDialog("Sign out of iLife?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { account.signOut() }
        }
        .confirmationDialog("Delete your account? All your iLife records, photos, reports and family members are removed\(cloud ? " from this device and iCloud" : " from this device"). This can't be undone.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                deleting = true
                Task { await AppData.shared.deleteAccountData() }
            }
        }
    }

    private func turnOn() async {
        message = nil
        guard await CloudChoice.accountAvailable() else {
            message = "Sign in to iCloud in the Settings app first (Settings → your name → iCloud)."
            return
        }
        guard !CloudChoice.usedByOther else {
            message = "Another iLife account on this device already syncs with this device's iCloud."
            return
        }
        CloudChoice.isOn = true
        cloud = true
        AppData.shared.reopen()
    }
}
