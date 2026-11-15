import Foundation
import AVFoundation
import CryptoKit

/// Google Cloud Text-to-Speech (Chirp 3 HD) voices for meditation.
/// Every line is turned into audio once, saved on the phone, and replayed for free after that.
@MainActor
final class NaturalVoice: ObservableObject {
    static let shared = NaturalVoice()

    static let female = ["Aoede", "Achernar", "Leda", "Kore", "Sulafat", "Despina", "Autonoe", "Callirrhoe", "Erinome", "Gacrux",
                         "Laomedeia", "Pulcherrima", "Vindemiatrix", "Zephyr"]
    static let male = ["Charon", "Iapetus", "Achird", "Algenib", "Algieba", "Alnilam", "Enceladus", "Fenrir", "Orus", "Puck",
                       "Rasalgethi", "Sadachbia", "Sadaltager", "Schedar", "Umbriel", "Zubenelgenubi"]

    @Published var hasKey = !KeychainStore.get("googletts").isEmpty
    @Published var enabled: Bool = (UserDefaults.standard.object(forKey: "ttsEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "ttsEnabled") }
    }
    @Published var voiceEN: String = UserDefaults.standard.string(forKey: "ttsVoice.en") ?? "Aoede" {
        didSet { UserDefaults.standard.set(voiceEN, forKey: "ttsVoice.en") }
    }
    @Published var voiceHI: String = UserDefaults.standard.string(forKey: "ttsVoice.hi") ?? "Leda" {
        didSet { UserDefaults.standard.set(voiceHI, forKey: "ttsVoice.hi") }
    }
    /// 0.75 … 1.1 — meditation sounds best a little slower than normal.
    @Published var rate: Double = (UserDefaults.standard.object(forKey: "ttsRate") as? Double) ?? 0.88 {
        didSet { UserDefaults.standard.set(rate, forKey: "ttsRate") }
    }
    @Published var monthCharacters: Int = NaturalVoice.storedMonthChars()
    @Published var preparing = false
    @Published var progress: Double = 0
    @Published var prepareNote = ""
    @Published var lastError: String?

    var isActive: Bool { enabled && hasKey }

    func saveKey(_ key: String) {
        KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: "googletts")
        hasKey = !KeychainStore.get("googletts").isEmpty
    }

    func voiceName(_ lang: MLang) -> String { lang == .english ? voiceEN : voiceHI }
    func fullName(_ lang: MLang) -> String { "\(lang.locale)-Chirp3-HD-\(voiceName(lang))" }

    // MARK: Cache

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("tts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheURL(_ text: String, _ lang: MLang) -> URL {
        let id = "\(fullName(lang))|\(String(format: "%.2f", rate))|\(text)"
        let hash = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
        return Self.cacheDir.appendingPathComponent("\(hash).mp3")
    }

    func isCached(_ text: String, _ lang: MLang) -> Bool { FileManager.default.fileExists(atPath: cacheURL(text, lang).path) }

    var cacheSizeMB: Double {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.cacheDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return Double(bytes) / 1_048_576
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: Self.cacheDir)
        objectWillChange.send()
    }

    // MARK: Usage (Google's free tier resets monthly)

    private static func monthKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: .now)
        return "ttsChars.\(c.year ?? 0)-\(c.month ?? 0)"
    }
    private static func storedMonthChars() -> Int { UserDefaults.standard.integer(forKey: monthKey()) }
    private func addUsage(_ n: Int) {
        let total = Self.storedMonthChars() + n
        UserDefaults.standard.set(total, forKey: Self.monthKey())
        monthCharacters = total
    }

    // MARK: Synthesis

    /// Audio file for a line — from the cache, or made now (one request) and cached.
    func audio(for text: String, _ lang: MLang) async throws -> URL {
        let url = cacheURL(text, lang)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let key = KeychainStore.get("googletts")
        guard !key.isEmpty else { throw TTSError.noKey }

        var comps = URLComponents(string: "https://texttospeech.googleapis.com/v1/text:synthesize")!
        comps.queryItems = [URLQueryItem(name: "key", value: key)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Lets you restrict the key to this app in Google Cloud.
        req.setValue(Bundle.main.bundleIdentifier ?? "com.jondhale.ilife", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        let body: [String: Any] = [
            "input": ["text": text],
            "voice": ["languageCode": lang.locale, "name": fullName(lang)],
            "audioConfig": ["audioEncoding": "MP3", "speakingRate": rate],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, let b64 = json?["audioContent"] as? String, let audio = Data(base64Encoded: b64) else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "request failed"
            throw TTSError.http(status, msg)
        }
        try audio.write(to: url, options: .atomic)
        addUsage(text.count)
        return url
    }

    /// Every spoken line in every session for the chosen languages.
    static func allLines(_ langs: [MLang]) -> [(String, MLang)] {
        var seen = Set<String>()
        var out: [(String, MLang)] = []
        func add(_ s: String, _ l: MLang) {
            if seen.insert(l.rawValue + s).inserted { out.append((s, l)) }
        }
        for script in MeditationLibrary.all {
            for minutes in script.lengths {
                for step in script.build(minutes) {
                    for l in langs {
                        switch step {
                        case .say(let line): add(line.text(l), l)
                        case .breathe(let p, _), .breatheFill(let p, _): p.phases.forEach { add($0.cue.text(l), l) }
                        default: break
                        }
                    }
                }
            }
        }
        return out
    }

    /// Characters still to generate, so you can see the cost before starting.
    func pendingCharacters(_ langs: [MLang]) -> Int {
        Self.allLines(langs).filter { !isCached($0.0, $0.1) }.reduce(0) { $0 + $1.0.count }
    }

    /// Generates audio for all sessions in advance, so they play instantly and offline.
    func prepareAll(_ langs: [MLang]) async {
        guard isActive, !preparing else { return }
        let lines = Self.allLines(langs).filter { !isCached($0.0, $0.1) }
        guard !lines.isEmpty else { prepareNote = "All sessions are ready."; return }
        preparing = true; progress = 0; lastError = nil
        var failed = 0
        for (i, (text, lang)) in lines.enumerated() {
            do { _ = try await audio(for: text, lang) }
            catch {
                failed += 1
                lastError = error.localizedDescription
                if failed >= 3 { break }       // stop early on a bad key or billing problem
            }
            progress = Double(i + 1) / Double(lines.count)
            prepareNote = "\(i + 1) of \(lines.count) lines"
        }
        preparing = false
        prepareNote = failed == 0 ? "All sessions are ready — they now play instantly, even offline." : "Stopped after errors. Check the message below."
    }
}

enum TTSError: LocalizedError {
    case noKey, http(Int, String)
    var errorDescription: String? {
        switch self {
        case .noKey: "Add your Google Cloud API key first."
        case .http(let code, let msg):
            switch code {
            case 400 where msg.lowercased().contains("api key"), 401: "Google rejected the API key. Check it was copied fully."
            case 403: "Google refused: \(msg) — make sure the Cloud Text-to-Speech API is enabled and billing is on for the project."
            case 429: "Too many requests right now. Try again in a minute."
            default: "Google error \(code): \(msg)"
            }
        }
    }
}

/// Plays one cached clip and lets the caller wait for it to finish.
final class ClipPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?
    private var extra: [AVAudioPlayer] = []

    func play(_ url: URL, volume: Float) async {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        finish()
        p.delegate = self
        p.volume = volume
        player = p
        await withCheckedContinuation { c in
            continuation = c
            if !p.play() { finish() }
        }
    }

    /// Fire-and-forget (breath cues), overlapping allowed.
    func playDetached(_ url: URL, volume: Float) {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = volume
        extra.removeAll { !$0.isPlaying }
        extra.append(p)
        p.play()
    }

    func pause() { player?.pause(); extra.forEach { $0.pause() } }
    func resume() { player?.play() }
    func stop() { player?.stop(); extra.forEach { $0.stop() }; extra.removeAll(); finish() }

    private func finish() { continuation?.resume(); continuation = nil }
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) { if p === player { finish() } }
    func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) { if p === player { finish() } }
}
