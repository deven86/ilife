import SwiftUI
import SwiftData
import AuthenticationServices

/// First screen when nobody is signed in: Sign in with Apple, then where to keep the data.
struct SignInFlow: View {
    @ObservedObject private var account = Account.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var step = 0
    @State private var error: String?
    @State private var checking = false
    @State private var iCloudReady = false

    var body: some View {
        ZStack {
            WallpaperView()
            ScrollView {
                VStack(spacing: 18) {
                    if step == 0 { welcome } else { storage }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange).glassCard()
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            ILifeLogo(size: 84).padding(.top, 40).appear(0)
            Text("Welcome to iLife").font(.largeTitle.bold()).appear(1)
            Text("Your health, workouts, food, medicines and family — private, on your iPhone.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).appear(2)
            feature("figure.run", .green, "Workouts & food", "Plans, live sessions, Apple Watch workouts, meals and water.").appear(3)
            feature("cross.case.fill", .red, "Medicines & records", "Reminders, injuries, reports and bills — for you and your family.").appear(4)
            feature("lock.shield.fill", .purple, "Yours alone", "Each Apple ID gets its own private records. No servers, no ads.").appear(5)
            SignInWithAppleButton(.continue) { req in
                req.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
                    account.signIn(cred)
                    error = nil
                    // Coming back to an account that already chose → open straight away.
                    if UserDefaults.standard.object(forKey: Account.scoped("icloud")) != nil {
                        AppData.shared.open()
                    } else {
                        withAnimation { step = 1 }
                        Task { iCloudReady = await CloudChoice.accountAvailable() }
                    }
                case .failure(let e):
                    if (e as? ASAuthorizationError)?.code != .canceled {
                        error = "Sign in with Apple didn't work: \(e.localizedDescription)"
                    }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(Capsule())
            .padding(.top, 8)
            .appear(6)
            Text("Your Apple ID is your login — no password. iLife never sends your records to any server.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).appear(7)
        }
    }

    private var storage: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.icloud.fill").font(.system(size: 58)).foregroundStyle(.tint).padding(.top, 40)
            Text("Where should your records live?").font(.title2.bold()).multilineTextAlignment(.center)
            choice(icon: "iphone", title: "On this device only",
                   text: "Nothing leaves this iPhone. Included in your encrypted iPhone backup.") {
                CloudChoice.isOn = false
                AppData.shared.open()
            }
            choice(icon: "icloud.fill", title: CloudChoice.serverReady ? "This device + my iCloud" : "This device + my iCloud (coming soon)",
                   text: "Synced to your private iCloud so your iPhone and iPad match, and kept if you change phones. Only your Apple ID can read it.") {
                Task {
                    checking = true
                    defer { checking = false }
                    guard await CloudChoice.accountAvailable() else {
                        error = "Sign in to iCloud in the Settings app first, or choose “On this device only” — you can switch later in More → Account."
                        return
                    }
                    guard !CloudChoice.usedByOther else {
                        error = "Another iLife account on this device already uses its iCloud. Choose “On this device only”."
                        return
                    }
                    CloudChoice.isOn = true
                    AppData.shared.open()
                }
            }
            .disabled(checking || !CloudChoice.serverReady)
            .opacity(CloudChoice.serverReady ? 1 : 0.5)
            if checking { ProgressView() }
            Text("You can change this any time in More → Account.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func choice(icon: String, title: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Color.primary)
                    Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .glassCard()
        }
        .buttonStyle(PressStyle())
    }

    private func feature(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .glassCard()
    }
}

// MARK: - First-run setup (after the database is open)

/// Your profile → Apple Health → notifications. Shown once per account.
struct SetupView: View {
    var done: () -> Void
    @Environment(\.modelContext) private var context
    @EnvironmentObject var health: HealthKitManager
    @EnvironmentObject var music: MusicController
    @AppStorage("userName") private var userName = ""
    @State private var step = 0
    @State private var waitingForICloud = CloudChoice.isOn
    @State private var avatar: Data?
    @State private var first = ""
    @State private var last = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
    @State private var gender = ""
    @State private var height: Double = 0
    @State private var weight: Double = 0
    @State private var target: Double = 0
    @State private var found: HealthProfile?

    var body: some View {
        ZStack {
            WallpaperView()
            ScrollView {
                VStack(spacing: 18) {
                    if waitingForICloud {
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large).padding(.top, 80)
                            Text("Checking your iCloud for existing records…").font(.headline)
                            Text("If you used iLife on another device, your data comes over now.").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if step == 0 { profile } else { connect }
                }
                .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }
        .task { await lookForExisting() }
    }

    private var profile: some View {
        VStack(spacing: 16) {
            Text(found == nil ? "Your profile" : "Welcome back").font(.largeTitle.bold()).padding(.top, 30)
            PhotoSourceButton(onPick: { avatar = ImageTools.jpeg($0, maxSide: 800) }) {
                AvatarView(data: avatar, name: "\(first) \(last)".trimmingCharacters(in: .whitespaces).isEmpty ? "?" : "\(first) \(last)", size: 104)
                    .overlay(alignment: .bottomTrailing) { Image(systemName: "camera.circle.fill").font(.title).foregroundStyle(.white, .blue) }
            }
            .buttonStyle(.plain)
            VStack(spacing: 0) {
                field("First name", text: $first)
                Divider()
                field("Last name", text: $last)
            }
            .glassCard(cornerRadius: 20, padding: 0)
            VStack(spacing: 12) {
                DatePicker("Date of birth", selection: $dob, in: ...Date.now, displayedComponents: .date)
                Picker("Sex", selection: $gender) { ForEach(["", "Male", "Female", "Other"], id: \.self) { Text($0.isEmpty ? "Not set" : $0) } }
                    .pickerStyle(.segmented)
                number("Height", $height, "cm")
                number("Weight now", $weight, "kg")
                number("Goal weight", $target, "kg")
            }
            .glassCard()
            Text("Your details stay in your iLife records. They help set your calorie and water targets.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                saveProfile()
                withAnimation { step = 1 }
            } label: { Text("Continue").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                .disabled(first.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var connect: some View {
        VStack(spacing: 16) {
            Text("Connect").font(.largeTitle.bold()).padding(.top, 30)
            if HealthOwner.allowed {
                OnboardRow(icon: "heart.fill", color: .red, title: "Apple Health",
                           text: "Steps, sleep, heart rate and Apple Watch workouts. Only your account on this iPhone can see it.") {
                    HealthOwner.claim()
                    await health.requestAuthorization()
                }
            } else {
                Label("Apple Health on this iPhone belongs to another iLife account, so it stays private to them. Log your activity by hand here.", systemImage: "heart.slash")
                    .font(.caption).glassCard()
            }
            OnboardRow(icon: "bell.badge.fill", color: .orange, title: "Notifications",
                       text: "Medicine and supplement reminders, alarms and workout alerts.") {
                await NotificationService.requestAuthorization()
            }
            OnboardRow(icon: "music.note", color: .pink, title: "Apple Music",
                       text: "Auto-play your workout playlist when a session starts.") {
                await music.requestAccess()
            }
            Button { done() } label: { Text("Start using iLife").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large).padding(.top)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text).textContentType(title.hasPrefix("First") ? .givenName : .familyName).padding(14)
    }

    private func number(_ title: String, _ value: Binding<Double>, _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(unit, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    /// With iCloud on, give the other devices' records a moment to arrive before asking again.
    private func lookForExisting() async {
        if waitingForICloud {
            for _ in 0..<10 {
                if mine() != nil { break }
                try? await Task.sleep(for: .seconds(1))
            }
            waitingForICloud = false
        }
        let d = UserDefaults.standard
        if let p = mine() {
            found = p
            first = p.firstName; last = p.lastName; avatar = p.avatar; gender = p.gender
            if let b = p.dateOfBirth { dob = b }
            height = p.heightCm; weight = p.startWeightKg; target = p.targetWeightKg
        }
        if first.isEmpty { first = d.string(forKey: Account.scoped("pendingFirst")) ?? "" }
        if last.isEmpty { last = d.string(forKey: Account.scoped("pendingLast")) ?? "" }
    }

    private func mine() -> HealthProfile? {
        ((try? context.fetch(FetchDescriptor<HealthProfile>())) ?? []).filter { $0.memberUID.isEmpty }.sorted { $0.created < $1.created }.first
    }

    private func saveProfile() {
        let p = mine() ?? {
            let n = HealthProfile(); n.memberUID = ""; context.insert(n); return n
        }()
        p.firstName = first.trimmingCharacters(in: .whitespaces); p.lastName = last.trimmingCharacters(in: .whitespaces)
        p.avatar = avatar; p.gender = gender; p.dateOfBirth = dob
        if height > 0 { p.heightCm = height }
        if weight > 0 {
            if p.startWeightKg == 0 { p.startWeightKg = weight }
            let m = BodyMeasurement(date: .now); m.memberUID = ""; m.weightKg = weight; context.insert(m)
        }
        if target > 0 { p.targetWeightKg = target }
        try? context.save()
        userName = p.firstName
    }
}
