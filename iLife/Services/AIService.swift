import Foundation
import UIKit
import Security

/// Stores the AI API key in the iPhone Keychain (never in iCloud, never in the code).
enum KeychainStore {
    private static let service = "com.jondhale.ilife.ai"

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum AIError: LocalizedError {
    case noKey, http(Int, String), empty, parse(String)
    var errorDescription: String? {
        switch self {
        case .noKey: "Add your AI key in More → AI Assistant first."
        case .http(let code, let msg): code == 401 ? "The AI key was rejected. Check it in More → AI Assistant." : "AI error \(code): \(msg)"
        case .empty: "The AI returned an empty answer. Try again."
        case .parse(let why): "Couldn't read the AI's answer (\(why)). Try again."
        }
    }
}

// MARK: - Results

struct InBodyAIResult: Codable {
    var testDate: String?
    var weightKg: Double?
    var skeletalMuscleKg: Double?
    var bodyFatKg: Double?
    var bodyFatPercent: Double?
    var bmi: Double?
    var totalBodyWaterL: Double?
    var proteinKg: Double?
    var mineralKg: Double?
    var fatFreeMassKg: Double?
    var visceralFatLevel: Double?
    var bmrKcal: Double?
    var inBodyScore: Double?
    var waistHipRatio: Double?
    var targetWeightKg: Double?
    var weightControlKg: Double?
    var fatControlKg: Double?
    var muscleControlKg: Double?
    var rightArmKg: Double?
    var leftArmKg: Double?
    var trunkKg: Double?
    var rightLegKg: Double?
    var leftLegKg: Double?
    var summary: String?
}

struct MealAIItem: Codable, Identifiable {
    var uid = UUID()
    var id: UUID { uid }
    enum CodingKeys: String, CodingKey { case name, quantity, calories, protein, carbs, fat }
    var name: String
    var quantity: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

struct MealAIResult: Codable {
    var items: [MealAIItem]
    var note: String?
}

// MARK: - Client

@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()
    static let models = ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"]

    @Published var hasKey: Bool = !KeychainStore.get("anthropic").isEmpty
    @Published var model: String = UserDefaults.standard.string(forKey: "aiModel") ?? "claude-sonnet-5-5" {
        didSet { UserDefaults.standard.set(model, forKey: "aiModel") }
    }

    var isReady: Bool { hasKey }

    func saveKey(_ key: String) {
        KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: "anthropic")
        hasKey = !KeychainStore.get("anthropic").isEmpty
    }

    struct Turn { let role: String; let text: String }

    /// One call to the Claude Messages API. Images go with the last user turn.
    func send(system: String, turns: [Turn], images: [UIImage] = [], maxTokens: Int = 1500) async throws -> String {
        let key = KeychainStore.get("anthropic")
        guard !key.isEmpty else { throw AIError.noKey }

        var messages: [[String: Any]] = []
        for (i, turn) in turns.enumerated() {
            var content: [[String: Any]] = []
            if i == turns.count - 1 && turn.role == "user" {
                for img in images {
                    guard let data = ImageTools.jpeg(img, maxSide: 1568, quality: 0.8) else { continue }
                    content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]])
                }
            }
            content.append(["type": "text", "text": turn.text])
            messages.append(["role": turn.role, "content": content])
        }
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "system": system, "messages": messages]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "request failed"
            throw AIError.http(status, msg)
        }
        let blocks = (json?["content"] as? [[String: Any]]) ?? []
        let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard !text.isEmpty else { throw AIError.empty }
        return text
    }

    private func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}"), s < e else { throw AIError.parse("no JSON") }
        let slice = String(text[s...e])
        do { return try JSONDecoder().decode(T.self, from: Data(slice.utf8)) }
        catch { throw AIError.parse("unexpected format") }
    }

    // MARK: Tasks

    func readInBody(_ images: [UIImage]) async throws -> InBodyAIResult {
        let system = """
        You read InBody body-composition result sheets (models 120/270/370/570/770/970, any language) from photos or scans.
        Return ONLY one JSON object, no prose, with these keys (use null when a value is not printed or not readable — never guess):
        testDate (YYYY-MM-DD), weightKg, skeletalMuscleKg, bodyFatKg, bodyFatPercent, bmi, totalBodyWaterL, proteinKg, mineralKg,
        fatFreeMassKg, visceralFatLevel, bmrKcal, inBodyScore, waistHipRatio, targetWeightKg, weightControlKg, fatControlKg, muscleControlKg,
        rightArmKg, leftArmKg, trunkKg, rightLegKg, leftLegKg (segmental LEAN mass in kg), summary.
        Read the measured value, not the normal range next to it. Control values keep their sign (e.g. -6.2).
        "summary" is 3-4 short plain-English sentences for the person: what looks good, what to improve, and one practical focus.
        It is general fitness guidance, not a medical diagnosis.
        """
        let text = try await send(system: system, turns: [.init(role: "user", text: "Read this InBody result sheet and return the JSON.")],
                                  images: Array(images.prefix(3)), maxTokens: 1200)
        return try decode(InBodyAIResult.self, from: text)
    }

    func analyzeMeal(_ image: UIImage, note: String) async throws -> MealAIResult {
        let system = """
        You estimate nutrition from a photo of food, with strong knowledge of Indian home and restaurant food.
        Return ONLY one JSON object: {"items":[{"name":..., "quantity":..., "calories":..., "protein":..., "carbs":..., "fat":...}], "note": ...}.
        One item per distinct food or drink. quantity is a human portion (e.g. "2 medium rotis", "1 bowl ~200 g").
        calories in kcal; protein, carbs, fat in grams, for the portion visible. Be realistic about oil and ghee.
        "note" is one short sentence on how confident the estimate is. If the photo has no food, return {"items":[],"note":"No food found"}.
        """
        let prompt = note.isEmpty ? "Estimate the nutrition of this meal." : "Estimate the nutrition of this meal. Extra detail from me: \(note)"
        let text = try await send(system: system, turns: [.init(role: "user", text: prompt)], images: [image], maxTokens: 1200)
        return try decode(MealAIResult.self, from: text)
    }

    func coach(history: [Turn], context: String) async throws -> String {
        let system = """
        You are iLife Coach: a friendly, direct fitness and nutrition coach inside the user's personal health app.
        Use the user's own data below. Be specific with their numbers, practical, and brief (under 180 words unless asked for a plan).
        Prefer Indian food examples. Give clear next steps. Do not diagnose or prescribe medicine; for symptoms, injuries, or medical
        conditions, tell them to see a doctor. If data is missing, say what to log.

        USER DATA
        \(context)
        """
        return try await send(system: system, turns: history, maxTokens: 900)
    }
}
