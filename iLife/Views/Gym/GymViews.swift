import SwiftUI
import SwiftData
import MapKit
import QuickLook
import VisionKit
import UniformTypeIdentifiers

func inr(_ v: Double) -> String { v.formatted(.currency(code: "INR").precision(.fractionLength(0))) }

// MARK: - Gym tab (inside Fitness)

struct GymSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GymMembership.endDate, order: .reverse) private var memberships: [GymMembership]
    @Query(sort: \Trainer.firstName) private var trainers: [Trainer]
    @Query(sort: \GymPayment.date, order: .reverse) private var payments: [GymPayment]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]

    @State private var editMembership: GymMembership?
    @State private var newMembership = false
    @State private var editTrainer: Trainer?
    @State private var newTrainer = false
    @State private var editPayment: GymPayment?
    @State private var newPayment = false
    @State private var editExpense: Expense?
    @State private var newExpense = false

    private var monthStart: Date { Calendar.current.dateInterval(of: .month, for: .now)!.start }
    private var yearStart: Date { Calendar.current.dateInterval(of: .year, for: .now)!.start }
    private var monthLogs: [WorkoutLog] { logs.filter { $0.start >= monthStart } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            membershipCard
            trainersCard
            sessionsCard
            moneySummary
            paymentsCard
            expensesCard
        }
        .sheet(isPresented: $newMembership) { MembershipEditor(membership: nil) }
        .sheet(item: $editMembership) { MembershipEditor(membership: $0) }
        .sheet(isPresented: $newTrainer) { TrainerEditor(trainer: nil) }
        .sheet(item: $editTrainer) { TrainerEditor(trainer: $0) }
        .sheet(isPresented: $newPayment) { PaymentEditor(payment: nil) }
        .sheet(item: $editPayment) { PaymentEditor(payment: $0) }
        .sheet(isPresented: $newExpense) { ExpenseEditor(expense: nil) }
        .sheet(item: $editExpense) { ExpenseEditor(expense: $0) }
    }

    // Membership
    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gym Membership").font(.headline)
                Spacer()
                Button { newMembership = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
            if memberships.isEmpty {
                Text("Add your gym — name, branch, location, plan and validity.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(memberships) { m in
                Button { editMembership = m } label: {
                    HStack(spacing: 12) {
                        ItemThumbnail(photo: m.photo, illustration: Illustration(symbol: "building.2.fill", colors: [.indigo, .blue]), size: 56, corner: 12)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.gymName.isEmpty ? "Gym" : m.gymName).font(.headline)
                            if !m.branch.isEmpty { Text(m.branch).font(.caption).foregroundStyle(.secondary) }
                            Text("\(m.planName.isEmpty ? "Membership" : m.planName) · till \(m.endDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(m.isActive ? "\(m.daysLeft)" : "Expired").font(m.isActive ? .title3.bold() : .caption.bold())
                                .foregroundStyle(!m.isActive ? .red : m.daysLeft <= 15 ? .orange : .green)
                            if m.isActive { Text("days left").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if m.isActive {
                    let total = max(1, Calendar.current.dateComponents([.day], from: m.startDate, to: m.endDate).day ?? 1)
                    ProgressView(value: Double(total - m.daysLeft), total: Double(total)).tint(m.daysLeft <= 15 ? .orange : .green)
                }
                HStack(spacing: 10) {
                    if !m.address.isEmpty {
                        Button("Directions", systemImage: "map.fill") { openMaps(m) }.font(.caption).buttonStyle(.bordered)
                    }
                    if let url = URL(string: "tel://\(m.phone.filter { $0.isNumber || $0 == "+" })"), !m.phone.isEmpty {
                        Link(destination: url) { Label("Call", systemImage: "phone.fill") }.font(.caption).buttonStyle(.bordered)
                    }
                }
            }
        }
        .glassCard()
    }

    private func openMaps(_ m: GymMembership) {
        let q = (m.gymName + " " + m.address).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?q=\(q)") { UIApplication.shared.open(url) }
    }

    // Trainers
    private func sessionsDone(_ t: Trainer) -> Int { logs.filter { $0.isPT && $0.trainerID == t.uid }.count }
    private func sessionsPaid(_ t: Trainer) -> Int { payments.filter { $0.kind == .personalTraining && $0.trainerID == t.uid }.reduce(0) { $0 + $1.sessionsIncluded } }

    private var trainersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Personal Trainers").font(.headline)
                Spacer()
                Button { newTrainer = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
            if trainers.isEmpty {
                Text("Add your trainer — photo, name, speciality and fee per session.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(trainers) { t in
                        Button { editTrainer = t } label: {
                            VStack(spacing: 6) {
                                AvatarView(data: t.photo, name: t.fullName, size: 64)
                                Text(t.fullName).font(.caption.bold()).lineLimit(1)
                                if !t.speciality.isEmpty { Text(t.speciality).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                let paid = sessionsPaid(t), done = sessionsDone(t)
                                Text(paid > 0 ? "\(done)/\(paid) sessions" : "\(done) sessions")
                                    .font(.caption2.bold()).foregroundStyle(paid > 0 && done >= paid ? .orange : .green)
                            }
                            .frame(width: 110)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .glassCard()
    }

    // Sessions
    private var sessionsCard: some View {
        let pt = monthLogs.filter(\.isPT).count
        let selfCount = monthLogs.count - pt
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Sessions this month", trailing: Date.now.formatted(.dateTime.month(.wide)))
            HStack {
                stat("\(pt)", "Personal training", .orange)
                Spacer()
                stat("\(selfCount)", "Self training", .cyan)
                Spacer()
                stat("\(monthLogs.count)", "Total", .green)
            }
            Text("Mark a workout as personal or self training when you log or edit it.").font(.caption2).foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func stat(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title2.bold()).foregroundStyle(c)
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // Money summary
    private var moneySummary: some View {
        let payMonth = payments.filter { $0.date >= monthStart }.reduce(0) { $0 + $1.amount }
        let expMonth = expenses.filter { $0.date >= monthStart }.reduce(0) { $0 + $1.amount }
        let payYear = payments.filter { $0.date >= yearStart }.reduce(0) { $0 + $1.amount }
        let expYear = expenses.filter { $0.date >= yearStart }.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Fitness spending").font(.headline)
            HStack {
                VStack(alignment: .leading) {
                    Text("This month").font(.caption).foregroundStyle(.secondary)
                    Text(inr(payMonth + expMonth)).font(.title2.bold())
                    Text("Fees \(inr(payMonth)) · Other \(inr(expMonth))").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("This year").font(.caption).foregroundStyle(.secondary)
                    Text(inr(payYear + expYear)).font(.title3.bold())
                }
            }
        }
        .glassCard()
    }

    // Payments
    private var paymentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fees & Payments").font(.headline)
                Spacer()
                Button { newPayment = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
            if payments.isEmpty { Text("Log gym membership and personal training fees, with the receipt.").font(.caption).foregroundStyle(.secondary) }
            ForEach(payments.prefix(8)) { p in
                Button { editPayment = p } label: {
                    HStack(spacing: 12) {
                        Image(systemName: p.kind.icon).foregroundStyle(.tint).frame(width: 34, height: 34).background(.tint.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paymentTitle(p)).font(.subheadline)
                            Text("\(p.date.formatted(date: .abbreviated, time: .omitted)) · \(p.method)" + (p.sessionsIncluded > 0 ? " · \(p.sessionsIncluded) sessions" : ""))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if p.bill != nil { Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary) }
                        Text(inr(p.amount)).font(.subheadline.bold())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }

    private func paymentTitle(_ p: GymPayment) -> String {
        if p.kind == .personalTraining, let t = trainers.first(where: { $0.uid == p.trainerID }) { return "PT — \(t.fullName)" }
        return p.kind.rawValue
    }

    // Expenses
    private var expensesCard: some View {
        let month = expenses.filter { $0.date >= monthStart }
        let byCat = Dictionary(grouping: month, by: \.category).mapValues { $0.reduce(0) { $0 + $1.amount } }.sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Expenses").font(.headline)
                Spacer()
                Button { newExpense = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
            if expenses.isEmpty { Text("Protein, creatine, supplements, shoes, gear — with bill and photo.").font(.caption).foregroundStyle(.secondary) }
            if !byCat.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(byCat, id: \.key) { cat, total in
                            Label("\(cat.rawValue) \(inr(total))", systemImage: cat.icon).font(.caption2.bold())
                                .padding(.horizontal, 10).padding(.vertical, 6).background(.white.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            ForEach(expenses.prefix(10)) { e in
                Button { editExpense = e } label: {
                    HStack(spacing: 12) {
                        ItemThumbnail(photo: e.photo, illustration: Illustration(symbol: e.category.icon, colors: [.purple, .pink]), size: 40, corner: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title.isEmpty ? e.category.rawValue : e.title).font(.subheadline).lineLimit(1)
                            Text([e.date.formatted(date: .abbreviated, time: .omitted), e.vendor].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if e.bill != nil { Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary) }
                        Text(inr(e.amount)).font(.subheadline.bold())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }
}

// MARK: - Bill attachment (scan, photo, PDF) with viewer

struct BillAttachment: View {
    @Binding var bill: Data?
    @Binding var billType: String
    @State private var showScan = false
    @State private var showFiles = false
    @State private var preview: URL?

    var body: some View {
        if bill != nil {
            HStack {
                Label("Bill attached (\(billType.uppercased()))", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Spacer()
                Button("View") { open() }.buttonStyle(.bordered)
            }
            Button("Remove bill", role: .destructive) { bill = nil; billType = "" }
        }
        Button("Scan bill", systemImage: "doc.viewfinder") { showScan = true }
            .disabled(!VNDocumentCameraViewController.isSupported)
            .fullScreenCover(isPresented: $showScan) {
                DocumentScanner { pages in
                    showScan = false
                    if !pages.isEmpty { bill = AddMedicalDocView.pdf(from: pages); billType = "pdf" }
                }
                .ignoresSafeArea()
            }
        PhotoSourceButton(onPick: { bill = ImageTools.jpeg($0, maxSide: 2000); billType = "jpg" }) {
            Label("Bill photo", systemImage: "camera.fill")
        }
        Button("Attach PDF / file", systemImage: "folder") { showFiles = true }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image]) { res in
                guard case .success(let url) = res else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                bill = try? Data(contentsOf: url)
                billType = url.pathExtension.lowercased() == "pdf" ? "pdf" : "jpg"
            }
            .quickLookPreview($preview)
    }

    private func open() {
        guard let bill else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bills", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("bill.\(billType.isEmpty ? "jpg" : billType)")
        try? bill.write(to: url, options: .completeFileProtection)
        preview = url
    }
}

// MARK: - Editors

struct MembershipEditor: View {
    let membership: GymMembership?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var m = Draft()
    @State private var addPayment = true

    struct Draft {
        var gymName = "", branch = "", address = "", phone = "", memberID = "", planName = "12 Months", notes = ""
        var start = Date.now
        var end = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
        var fee = ""
        var photo: Data?
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ItemThumbnail(photo: m.photo, illustration: Illustration(symbol: "building.2.fill", colors: [.indigo, .blue]), size: 72, corner: 14)
                        PhotoSourceButton(onPick: { m.photo = ImageTools.jpeg($0, maxSide: 1200) }) {
                            Label(m.photo == nil ? "Add gym photo / logo" : "Change photo", systemImage: "camera.fill")
                        }
                    }
                }
                Section("Gym") {
                    TextField("Gym name (e.g. Cult, Gold's Gym)", text: $m.gymName)
                    TextField("Branch / area", text: $m.branch)
                    TextField("Full address", text: $m.address, axis: .vertical)
                    TextField("Gym phone", text: $m.phone).keyboardType(.phonePad)
                    TextField("Member ID", text: $m.memberID)
                }
                Section("Plan") {
                    Picker("Plan", selection: $m.planName) {
                        ForEach(["1 Month", "3 Months", "6 Months", "12 Months", "24 Months", "Pay per visit", "Other"], id: \.self) { Text($0) }
                    }
                    .onChange(of: m.planName) { _, p in
                        let months = ["1 Month": 1, "3 Months": 3, "6 Months": 6, "12 Months": 12, "24 Months": 24][p]
                        if let months { m.end = Calendar.current.date(byAdding: .month, value: months, to: m.start)! }
                    }
                    DatePicker("Start", selection: $m.start, displayedComponents: .date)
                    DatePicker("Valid till", selection: $m.end, in: m.start..., displayedComponents: .date)
                    HStack {
                        Text("Fee")
                        Spacer()
                        Text("₹").foregroundStyle(.secondary)
                        TextField("0", text: $m.fee).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 100)
                    }
                    if membership == nil { Toggle("Also add this fee to Payments", isOn: $addPayment) }
                }
                Section("Notes") { TextField("Timings, locker no., freeze days…", text: $m.notes, axis: .vertical) }
                if let membership {
                    Section { Button("Delete membership", role: .destructive) { context.delete(membership); dismiss() } }
                }
            }
            .navigationTitle(membership == nil ? "Add Membership" : "Membership")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(m.gymName.isEmpty) }
            }
            .onAppear {
                guard let x = membership else { return }
                m = Draft(gymName: x.gymName, branch: x.branch, address: x.address, phone: x.phone, memberID: x.memberID, planName: x.planName,
                          notes: x.notes, start: x.startDate, end: x.endDate, fee: x.fee > 0 ? String(Int(x.fee)) : "", photo: x.photo)
            }
        }
    }

    private func save() {
        let x = membership ?? GymMembership()
        if membership == nil { context.insert(x) }
        x.gymName = m.gymName; x.branch = m.branch; x.address = m.address; x.phone = m.phone; x.memberID = m.memberID
        x.planName = m.planName; x.notes = m.notes; x.startDate = m.start; x.endDate = m.end; x.fee = Double(m.fee) ?? 0; x.photo = m.photo
        if membership == nil && addPayment && x.fee > 0 {
            let p = GymPayment()
            p.kind = .membership; p.amount = x.fee; p.date = m.start; p.validFrom = m.start; p.validTo = m.end
            p.notes = "\(m.gymName) — \(m.planName)"
            context.insert(p)
        }
        try? context.save()
        dismiss()
    }
}

struct TrainerEditor: View {
    let trainer: Trainer?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @State private var first = ""
    @State private var last = ""
    @State private var speciality = ""
    @State private var phone = ""
    @State private var gym = ""
    @State private var fee = ""
    @State private var notes = ""
    @State private var photo: Data?

    private let specialities = ["Strength & Conditioning", "Bodybuilding", "Weight Loss", "Powerlifting", "CrossFit / Functional", "Yoga",
                                "Pilates", "Zumba / Dance", "Calisthenics", "Sports Performance", "Rehab & Mobility", "Nutrition Coach"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotoSourceButton(onPick: { photo = ImageTools.jpeg($0, maxSide: 800) }) {
                            AvatarView(data: photo, name: "\(first) \(last)", size: 100)
                                .overlay(alignment: .bottomTrailing) { Image(systemName: "camera.circle.fill").font(.title).foregroundStyle(.white, .blue) }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Trainer") {
                    TextField("First name", text: $first)
                    TextField("Last name", text: $last)
                    TextField("Speciality", text: $speciality)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(specialities, id: \.self) { s in
                                Button(s) { speciality = s }.font(.caption).buttonStyle(.bordered)
                            }
                        }
                    }
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    TextField("Gym", text: $gym)
                    HStack {
                        Text("Fee per session")
                        Spacer()
                        Text("₹").foregroundStyle(.secondary)
                        TextField("0", text: $fee).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if let trainer {
                    let sessions = logs.filter { $0.isPT && $0.trainerID == trainer.uid }
                    Section("Sessions with \(trainer.firstName) (\(sessions.count))") {
                        if sessions.isEmpty { Text("Log a workout as Personal training and choose this trainer.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(sessions.prefix(20)) { s in
                            HStack {
                                Text(s.start.formatted(date: .abbreviated, time: .shortened))
                                Spacer()
                                Text(s.name).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .font(.caption)
                        }
                    }
                    Section { Button("Delete trainer", role: .destructive) { context.delete(trainer); dismiss() } }
                }
            }
            .navigationTitle(trainer == nil ? "Add Trainer" : "Trainer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let t = trainer ?? Trainer()
                        if trainer == nil { context.insert(t) }
                        t.firstName = first; t.lastName = last; t.speciality = speciality; t.phone = phone
                        t.gymName = gym; t.feePerSession = Double(fee) ?? 0; t.notes = notes; t.photo = photo
                        try? context.save()
                        dismiss()
                    }
                    .disabled(first.isEmpty)
                }
                if let trainer, let url = URL(string: "tel://\(trainer.phone.filter { $0.isNumber || $0 == "+" })"), !trainer.phone.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { Link(destination: url) { Image(systemName: "phone.fill") } }
                }
            }
            .onAppear {
                guard let t = trainer else { return }
                first = t.firstName; last = t.lastName; speciality = t.speciality; phone = t.phone; gym = t.gymName
                fee = t.feePerSession > 0 ? String(Int(t.feePerSession)) : ""; notes = t.notes; photo = t.photo
            }
        }
    }
}

struct PaymentEditor: View {
    let payment: GymPayment?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trainer.firstName) private var trainers: [Trainer]
    @State private var kind: PaymentKind = .membership
    @State private var amount = ""
    @State private var date = Date.now
    @State private var method = "UPI"
    @State private var trainerID = ""
    @State private var sessions = 12
    @State private var hasValidity = false
    @State private var validFrom = Date.now
    @State private var validTo = Calendar.current.date(byAdding: .month, value: 1, to: .now)!
    @State private var reference = ""
    @State private var notes = ""
    @State private var bill: Data?
    @State private var billType = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment") {
                    Picker("For", selection: $kind) { ForEach(PaymentKind.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) } }
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("₹").foregroundStyle(.secondary)
                        TextField("0", text: $amount).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 110)
                    }
                    DatePicker("Paid on", selection: $date, displayedComponents: .date)
                    Picker("Method", selection: $method) {
                        ForEach(["UPI", "Cash", "Card", "Net Banking", "Cheque", "EMI"], id: \.self) { Text($0) }
                    }
                    TextField("Reference / UTR (optional)", text: $reference)
                }
                if kind == .personalTraining {
                    Section("Personal training") {
                        Picker("Trainer", selection: $trainerID) {
                            Text("Not set").tag("")
                            ForEach(trainers) { Text($0.fullName).tag($0.uid) }
                        }
                        Stepper("Sessions in package: \(sessions)", value: $sessions, in: 0...200)
                        if let t = trainers.first(where: { $0.uid == trainerID }), t.feePerSession > 0 {
                            Button("Use \(sessions) × \(inr(t.feePerSession))") { amount = String(Int(t.feePerSession) * sessions) }.font(.caption)
                        }
                    }
                }
                Section("Validity") {
                    Toggle("Covers a period", isOn: $hasValidity)
                    if hasValidity {
                        DatePicker("From", selection: $validFrom, displayedComponents: .date)
                        DatePicker("To", selection: $validTo, in: validFrom..., displayedComponents: .date)
                    }
                }
                Section("Receipt / bill") { BillAttachment(bill: $bill, billType: $billType) }
                Section("Notes") { TextField("Notes", text: $notes, axis: .vertical) }
                if let payment {
                    Section { Button("Delete payment", role: .destructive) { context.delete(payment); dismiss() } }
                }
            }
            .navigationTitle(payment == nil ? "Add Payment" : "Payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let p = payment ?? GymPayment()
                        if payment == nil { context.insert(p) }
                        p.kind = kind; p.amount = Double(amount) ?? 0; p.date = date; p.method = method
                        p.trainerID = kind == .personalTraining ? trainerID : ""
                        p.sessionsIncluded = kind == .personalTraining ? sessions : 0
                        p.validFrom = hasValidity ? validFrom : nil; p.validTo = hasValidity ? validTo : nil
                        p.reference = reference; p.notes = notes; p.bill = bill; p.billType = billType
                        try? context.save()
                        dismiss()
                    }
                    .disabled((Double(amount) ?? 0) <= 0)
                }
            }
            .onAppear {
                guard let p = payment else { return }
                kind = p.kind; amount = String(Int(p.amount)); date = p.date; method = p.method; trainerID = p.trainerID
                sessions = p.sessionsIncluded; hasValidity = p.validFrom != nil
                validFrom = p.validFrom ?? .now; validTo = p.validTo ?? .now
                reference = p.reference; notes = p.notes; bill = p.bill; billType = p.billType
            }
        }
    }
}

struct ExpenseEditor: View {
    let expense: Expense?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category: ExpenseCategory = .protein
    @State private var amount = ""
    @State private var date = Date.now
    @State private var vendor = ""
    @State private var quantity = ""
    @State private var notes = ""
    @State private var bill: Data?
    @State private var billType = ""
    @State private var photo: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ItemThumbnail(photo: photo, illustration: Illustration(symbol: category.icon, colors: [.purple, .pink]), size: 72, corner: 14)
                        VStack(alignment: .leading, spacing: 6) {
                            PhotoSourceButton(onPick: { photo = ImageTools.jpeg($0, maxSide: 1200) }) {
                                Label(photo == nil ? "Add product photo" : "Change photo", systemImage: "camera.fill")
                            }
                            if photo != nil { Button("Remove", role: .destructive) { photo = nil }.font(.caption) }
                        }
                    }
                }
                Section("Expense") {
                    Picker("Category", selection: $category) { ForEach(ExpenseCategory.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) } }
                    TextField("Item (e.g. ON Gold Standard Whey 2 kg)", text: $title)
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("₹").foregroundStyle(.secondary)
                        TextField("0", text: $amount).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 110)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Shop / website (e.g. Amazon, HealthKart)", text: $vendor)
                    TextField("Quantity (e.g. 2 kg, 60 servings)", text: $quantity)
                }
                Section("Bill") { BillAttachment(bill: $bill, billType: $billType) }
                Section("Notes") { TextField("Notes", text: $notes, axis: .vertical) }
                if let expense {
                    Section { Button("Delete expense", role: .destructive) { context.delete(expense); dismiss() } }
                }
            }
            .navigationTitle(expense == nil ? "Add Expense" : "Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let e = expense ?? Expense()
                        if expense == nil { context.insert(e) }
                        e.title = title; e.category = category; e.amount = Double(amount) ?? 0; e.date = date
                        e.vendor = vendor; e.quantity = quantity; e.notes = notes; e.bill = bill; e.billType = billType; e.photo = photo
                        try? context.save()
                        dismiss()
                    }
                    .disabled((Double(amount) ?? 0) <= 0)
                }
            }
            .onAppear {
                guard let e = expense else { return }
                title = e.title; category = e.category; amount = String(Int(e.amount)); date = e.date; vendor = e.vendor
                quantity = e.quantity; notes = e.notes; bill = e.bill; billType = e.billType; photo = e.photo
            }
        }
    }
}
