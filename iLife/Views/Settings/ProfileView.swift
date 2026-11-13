import SwiftUI
import SwiftData

/// Returns the single HealthProfile, creating it the first time.
@MainActor
func ensureProfile(_ context: ModelContext) -> HealthProfile {
    if let p = try? context.fetch(FetchDescriptor<HealthProfile>()).first { return p }
    let p = HealthProfile()
    context.insert(p)
    try? context.save()
    return p
}

struct ProfileView: View {
    @Bindable var profile: HealthProfile
    @AppStorage("userName") private var legacyName = ""
    @State private var hasDOB = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        PhotoSourceButton(onPick: { profile.avatar = ImageTools.jpeg($0, maxSide: 800) }) {
                            AvatarView(data: profile.avatar, name: profile.fullName, size: 110)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "camera.circle.fill").font(.title).foregroundStyle(.white, .blue)
                                }
                        }
                        .buttonStyle(.plain)
                        if profile.avatar != nil {
                            Button("Remove photo", role: .destructive) { profile.avatar = nil }.font(.caption)
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Name") {
                TextField("First name", text: $profile.firstName).textContentType(.givenName)
                TextField("Last name", text: $profile.lastName).textContentType(.familyName)
            }

            Section("Contact") {
                TextField("Email", text: $profile.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Phone (+91…)", text: $profile.phone)
                    .textContentType(.telephoneNumber).keyboardType(.phonePad)
            }

            Section("About you") {
                Toggle("Date of birth", isOn: $hasDOB)
                if hasDOB {
                    DatePicker("Born", selection: Binding(get: { profile.dateOfBirth ?? Calendar.current.date(byAdding: .year, value: -35, to: .now)! },
                                                          set: { profile.dateOfBirth = $0 }),
                               in: ...Date.now, displayedComponents: .date)
                }
                Picker("Gender", selection: $profile.gender) {
                    ForEach(["", "Male", "Female", "Other"], id: \.self) { Text($0.isEmpty ? "Not set" : $0) }
                }
                Stepper("Height: \(profile.heightCm.clean) cm", value: $profile.heightCm, in: 0...230, step: 1)
            }

            Section {
                Text("Your profile is stored in your private iCloud and never shared.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profile")
        .onAppear {
            hasDOB = profile.dateOfBirth != nil
            // Carry over the name typed in the first version.
            if profile.firstName.isEmpty && !legacyName.isEmpty { profile.firstName = legacyName }
        }
        .onChange(of: hasDOB) { _, on in if !on { profile.dateOfBirth = nil } }
        .onChange(of: profile.firstName) { _, v in legacyName = v }
    }
}
