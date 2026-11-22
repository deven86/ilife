import SwiftUI
import SwiftData
import CloudKit
import CryptoKit
import AuthenticationServices

/// Who is using iLife on this device — Sign in with Apple, like iTeam.
///
/// Every Apple ID gets its own database file, so two people who share an iPad never see
/// each other's records. Nothing is sent to any server: the Apple ID is only used as a key.
@MainActor
final class Account: ObservableObject {
    static let shared = Account()
    private let d = UserDefaults.standard

    /// Apple's stable user ID for this app ("" = signed out).
    @Published private(set) var userID: String
    @Published private(set) var email: String
    var isSignedIn: Bool { !userID.isEmpty }

    /// Read without touching the main actor (models and intents use it).
    nonisolated static var currentID: String { UserDefaults.standard.string(forKey: "apple.user") ?? "" }

    private init() {
        userID = d.string(forKey: "apple.user") ?? ""
        email = d.string(forKey: "apple.email") ?? ""
    }

    /// Short folder-safe name for this account's data.
    static func key(for user: String) -> String {
        SHA256.hash(data: Data(user.utf8)).map { String(format: "%02x", $0) }.joined().prefix(20).description
    }

    /// A per-account settings key, e.g. scoped("onboarded").
    nonisolated static func scoped(_ name: String) -> String { "\(name).\(currentID)" }

    func signIn(_ cred: ASAuthorizationAppleIDCredential) {
        userID = cred.user
        d.set(cred.user, forKey: "apple.user")
        if let mail = cred.email ?? Self.email(fromIdentityToken: cred.identityToken) {
            email = mail; d.set(mail, forKey: "apple.email")
        }
        // Apple shares the name only on the very first sign-in — keep it for the profile step.
        if let n = cred.fullName {
            let full = PersonNameComponentsFormatter().string(from: n).trimmingCharacters(in: .whitespaces)
            if !full.isEmpty {
                d.set(n.givenName ?? "", forKey: Self.scoped("pendingFirst"))
                d.set(n.familyName ?? "", forKey: Self.scoped("pendingLast"))
            }
        }
        d.set("", forKey: Member.key)        // start on your own records
    }

    func signOut() {
        AppData.shared.close()
        userID = ""; email = ""
        d.removeObject(forKey: "apple.user"); d.removeObject(forKey: "apple.email"); d.removeObject(forKey: "userName")
        d.set("", forKey: Member.key)
    }

    /// Signs out if the person stopped using Sign in with Apple for iLife (Settings → Apple ID).
    func checkStillAuthorized() async {
        guard isSignedIn else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        if state == .revoked || state == .notFound { signOut() }
    }

    static func email(fromIdentityToken token: Data?) -> String? {
        guard let token, let jwt = String(data: token, encoding: .utf8) else { return nil }
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (claims["email"] as? String)?.lowercased()
    }

    /// The email to show (Apple's private relay addresses are hidden).
    var displayEmail: String { email.hasSuffix("privaterelay.appleid.com") ? "Hidden by Apple" : email }
}

// MARK: - iCloud choice

/// iCloud sync is OFF unless the person turns it on. One iLife account per device may use the
/// device's iCloud, so two people sharing an iPad never mix their records in one iCloud.
enum CloudChoice {
    static let containerID = "iCloud.group.com.jondhale.ilife"
    /// Flip to true once the CloudKit schema is deployed to Production (cloudkit-schema workflow +
    /// "Deploy Schema Changes"). Until then iCloud can't store iLife records, so the option stays off.
    static let serverReady = false

    static var isOn: Bool {
        get { serverReady && UserDefaults.standard.bool(forKey: Account.scoped("icloud")) }
        set {
            UserDefaults.standard.set(newValue, forKey: Account.scoped("icloud"))
            if newValue { UserDefaults.standard.set(Account.currentID, forKey: "icloud.owner") }
            else if UserDefaults.standard.string(forKey: "icloud.owner") == Account.currentID { UserDefaults.standard.removeObject(forKey: "icloud.owner") }
        }
    }

    /// Another iLife account on this device already uses this device's iCloud.
    static var usedByOther: Bool {
        let o = UserDefaults.standard.string(forKey: "icloud.owner") ?? ""
        return !o.isEmpty && o != Account.currentID
    }

    static func accountAvailable() async -> Bool {
        (try? await CKContainer(identifier: containerID).accountStatus()) == .available
    }
}

// MARK: - Apple Health owner

/// Apple Health holds the data of the person who owns this iPhone. Only the iLife account that
/// connected Apple Health on this device may read it or write to it.
enum HealthOwner {
    static var owner: String { UserDefaults.standard.string(forKey: "health.owner") ?? "" }
    /// True when the signed-in account may use Apple Health here.
    static var allowed: Bool { owner.isEmpty ? true : owner == Account.currentID }
    static func claim() { if owner.isEmpty, !Account.currentID.isEmpty { UserDefaults.standard.set(Account.currentID, forKey: "health.owner") } }
    static func release() { if owner == Account.currentID { UserDefaults.standard.removeObject(forKey: "health.owner") } }
}

// MARK: - The open database

/// Opens the signed-in account's database (on this device, plus iCloud if they chose it).
@MainActor
final class AppData: ObservableObject {
    static let shared = AppData()
    @Published private(set) var container: ModelContainer?
    /// Changes whenever a different database is opened, so the whole UI starts fresh.
    @Published private(set) var generation = UUID()
    @Published var cloudProblem: String?

    private init() {}

    static var accountsDir: URL {
        URL.applicationSupportDirectory.appending(path: "Accounts", directoryHint: .isDirectory)
    }
    static func folder(for user: String) -> URL { accountsDir.appending(path: Account.key(for: user), directoryHint: .isDirectory) }

    func openIfSignedIn() {
        guard container == nil, Account.shared.isSignedIn else { return }
        open()
    }

    func open() {
        let user = Account.shared.userID
        guard !user.isEmpty else { return }
        let dir = Self.folder(for: user)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Self.claimLegacyStore(into: dir)
        let url = dir.appending(path: "default.store")
        let schema = Schema(ILifeSchema.models)
        var made: ModelContainer?
        cloudProblem = nil
        if CloudChoice.isOn {
            let cfg = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .private(CloudChoice.containerID))
            made = try? ModelContainer(for: schema, configurations: cfg)
            if made == nil { cloudProblem = "iCloud couldn't start — your data is safe on this device. Check that you're signed in to iCloud." }
        }
        if made == nil {
            let cfg = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            made = try? ModelContainer(for: schema, configurations: cfg)
        }
        guard let c = made else { cloudProblem = "Your data couldn't be opened. Restart iLife."; return }
        container = c
        generation = UUID()
        MediaStore.shared.attach(c)
        AICoordinator.shared.attach(c)
        AICoordinator.shared.scheduleNotifications()
        if UserDefaults.standard.bool(forKey: "healthConnected") && HealthOwner.allowed {
            HealthKitManager.shared.enableBackgroundWorkoutDetection(container: c)
        }
    }

    /// Reopen after the iCloud choice changes.
    func reopen() { close(); open() }

    func close() {
        if let c = container { try? c.mainContext.save() }
        container = nil
        generation = UUID()
    }

    /// For App Store screenshots: an in-memory database with sample data.
    func openScreenshots() {
        let schema = Schema(ILifeSchema.models)
        let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let c = try! ModelContainer(for: schema, configurations: mem)
        container = c
        ScreenshotMode.seed(c.mainContext)
        ScreenshotMode.fakeHealth(HealthKitManager.shared)
    }

    /// Before accounts existed, iLife kept one database at Application Support/default.store.
    /// The first person to sign in on this device is the one who used it — move it into their folder.
    private static func claimLegacyStore(into dir: URL) {
        let fm = FileManager.default
        let support = URL.applicationSupportDirectory
        let legacy = support.appending(path: "default.store")
        guard !UserDefaults.standard.bool(forKey: "legacy.claimed"), fm.fileExists(atPath: legacy.path(percentEncoded: false)) else { return }
        UserDefaults.standard.set(true, forKey: "legacy.claimed")
        guard !fm.fileExists(atPath: dir.appending(path: "default.store").path(percentEncoded: false)) else { return }
        for name in ["default.store", "default.store-shm", "default.store-wal", ".default_SUPPORT"] {
            let from = support.appending(path: name)
            if fm.fileExists(atPath: from.path(percentEncoded: false)) { try? fm.moveItem(at: from, to: dir.appending(path: name)) }
        }
        // Their Apple Health connection and finished set-up came with them.
        if UserDefaults.standard.bool(forKey: "healthConnected") { HealthOwner.claim() }
        if UserDefaults.standard.bool(forKey: "onboarded") { UserDefaults.standard.set(true, forKey: Account.scoped("onboarded")) }
    }

    /// Deletes this account's data on this device and, if it was synced, in iCloud.
    func deleteAccountData() async {
        let user = Account.shared.userID
        guard !user.isEmpty else { return }
        let wasCloud = CloudChoice.isOn
        close()
        if wasCloud {
            let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
            _ = try? await CKContainer(identifier: CloudChoice.containerID).privateCloudDatabase.deleteRecordZone(withID: zone)
            CloudChoice.isOn = false
        }
        try? FileManager.default.removeItem(at: Self.folder(for: user))
        HealthOwner.release()
        for k in ["onboarded", "icloud", "pendingFirst", "pendingLast"] { UserDefaults.standard.removeObject(forKey: Account.scoped(k)) }
        Account.shared.signOut()
    }
}
