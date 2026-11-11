import SwiftUI
import SwiftData
import ContactsUI

struct EmergencyView: View {
    @Environment(\.modelContext) private var context
    @Query private var contacts: [EmergencyContact]
    @Query private var profiles: [HealthProfile]
    @State private var showAdd = false
    @State private var showPicker = false

    var body: some View {
        Form {
            Section {
                ForEach(contacts) { c in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(c.name).font(.headline)
                                if c.isPrimary { Text("PRIMARY").font(.caption2.bold()).padding(4).background(.red.opacity(0.2), in: Capsule()) }
                            }
                            Text("\(c.relation) · \(c.phone)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let url = URL(string: "tel://\(c.phone.filter { $0.isNumber || $0 == "+" })") {
                            Link(destination: url) { Image(systemName: "phone.fill").foregroundStyle(.white).padding(10).background(.green, in: Circle()) }
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { context.delete(c) }
                        Button("Primary") { contacts.forEach { $0.isPrimary = false }; c.isPrimary = true }.tint(.orange)
                    }
                }
                Button("Add contact manually", systemImage: "plus") { showAdd = true }
                Button("Pick from Contacts", systemImage: "person.crop.circle.badge.plus") { showPicker = true }
            } header: {
                Text("Emergency Contacts")
            } footer: {
                Text("Tip: also add these in the Health app → Medical ID so they show on the iPhone Lock Screen and in Emergency SOS, even when iLife is locked.")
            }

            if let p = profiles.first {
                MedicalIDSection(profile: p)
            } else {
                Section { Button("Set up Medical ID") { context.insert(HealthProfile()) } }
            }
        }
        .scrollContentBackground(.hidden)
        .background { WallpaperView() }
        .navigationTitle("Emergency")
        .sheet(isPresented: $showAdd) { AddContactSheet() }
        .sheet(isPresented: $showPicker) {
            ContactPicker { name, phone in
                context.insert(EmergencyContact(name: name, relation: "", phone: phone, isPrimary: contacts.isEmpty))
            }
        }
    }
}

struct MedicalIDSection: View {
    @Bindable var profile: HealthProfile
    var body: some View {
        Section("Medical ID") {
            Picker("Blood group", selection: $profile.bloodGroup) {
                ForEach(["", "A+", "A−", "B+", "B−", "AB+", "AB−", "O+", "O−"], id: \.self) { Text($0.isEmpty ? "Not set" : $0) }
            }
            TextField("Allergies", text: $profile.allergies, axis: .vertical)
            TextField("Medical conditions", text: $profile.conditions, axis: .vertical)
            TextField("Current medications", text: $profile.medications, axis: .vertical)
        }
    }
}

struct AddContactSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var contacts: [EmergencyContact]
    @State private var name = ""
    @State private var relation = ""
    @State private var phone = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Relation (e.g. Wife, Brother)", text: $relation)
                TextField("Phone (+91…)", text: $phone).keyboardType(.phonePad)
            }
            .navigationTitle("Emergency Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(EmergencyContact(name: name, relation: relation, phone: phone, isPrimary: contacts.isEmpty))
                        dismiss()
                    }
                    .disabled(name.isEmpty || phone.isEmpty)
                }
            }
        }
    }
}

struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (String, String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.delegate = context.coordinator
        vc.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        return vc
    }
    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (String, String) -> Void
        init(onPick: @escaping (String, String) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.givenName
            onPick(name, contact.phoneNumbers.first?.value.stringValue ?? "")
        }
    }
}
