import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

// MARK: - Background sound

enum Soundscape: String, CaseIterable, Identifiable {
    case none, rain, ocean, drone, bowls, binaural, appleMusic, myFile
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Voice only"
        case .rain: "Rain"
        case .ocean: "Ocean waves"
        case .drone: "Soft drone"
        case .bowls: "Singing bowls"
        case .binaural: "Binaural calm"
        case .appleMusic: "Apple Music"
        case .myFile: "My audio file"
        }
    }
    var icon: String {
        switch self {
        case .none: "speaker.slash.fill"
        case .rain: "cloud.rain.fill"
        case .ocean: "water.waves"
        case .drone: "waveform"
        case .bowls: "bell.circle.fill"
        case .binaural: "headphones"
        case .appleMusic: "music.note"
        case .myFile: "folder.fill"
        }
    }
    var isGenerated: Bool { [.rain, .ocean, .drone, .bowls, .binaural].contains(self) }
}

/// Synthesises ambience in real time — nothing to download, no licensing.
final class AmbienceGenerator {
    var kind: Soundscape = .none
    let sampleRate: Double
    private var t: Double = 0
    // pink noise state (Paul Kellet)
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0
    private var brown = 0.0
    private var lp = 0.0
    private var drops: [(amp: Double, decay: Double, pan: Double)] = []
    private var strikes: [(start: Double, base: Double)] = []
    private var nextStrike = 2.0
    private var phases = [Double](repeating: 0, count: 8)
    private var rng = SystemRandomNumberGenerator()

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    private func white() -> Double { Double.random(in: -1...1, using: &rng) }
    private func pink() -> Double {
        let w = white()
        b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759; b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856; b4 = 0.55000 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.0168980
        let p = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return p * 0.11
    }

    private func sine(_ i: Int, _ freq: Double) -> Double {
        phases[i] += 2 * .pi * freq / sampleRate
        if phases[i] > 2 * .pi { phases[i] -= 2 * .pi }
        return sin(phases[i])
    }

    /// Fills one stereo frame.
    func next() -> (Double, Double) {
        t += 1 / sampleRate
        switch kind {
        case .rain:
            let base = pink() * 0.55
            lp += 0.08 * (base - lp)
            if Double.random(in: 0...1, using: &rng) < 0.0009 { drops.append((Double.random(in: 0.05...0.25, using: &rng), 0.9985, Double.random(in: 0...1, using: &rng))) }
            var l = lp * 0.6 + base * 0.4, r = l
            for i in drops.indices.reversed() {
                let s = drops[i].amp * white()
                l += s * (1 - drops[i].pan); r += s * drops[i].pan
                drops[i].amp *= drops[i].decay
                if drops[i].amp < 0.001 { drops.remove(at: i) }
            }
            return (l, r)
        case .ocean:
            brown = (brown + white() * 0.02) / 1.02
            let swell = 0.25 + 0.75 * (0.5 - 0.5 * cos(2 * .pi * t / 9.5))
            let s = brown * 3.2 * swell
            lp += 0.15 * (pink() * swell * 0.25 - lp)
            return (s + lp, s * 0.9 + lp * 1.1)
        case .drone:
            let lfo = 0.6 + 0.4 * sin(2 * .pi * t / 14)
            let v = (sine(0, 110) * 0.5 + sine(1, 164.8) * 0.3 + sine(2, 220.4) * 0.25 + sine(3, 329.6) * 0.08) * lfo * 0.22
            return (v, v)
        case .bowls:
            if t >= nextStrike {
                strikes.append((t, [174.6, 196.0, 220.0, 261.6, 293.7].randomElement(using: &rng)!))
                nextStrike = t + Double.random(in: 11...18, using: &rng)
            }
            var v = sine(5, 87.3) * 0.04
            for (start, base) in strikes {
                let age = t - start
                let env = exp(-age / 7) * min(1, age * 40)
                v += env * (sin(2 * .pi * base * age) * 0.35 + sin(2 * .pi * base * 2.71 * age) * 0.15 + sin(2 * .pi * base * 5.15 * age) * 0.05)
            }
            strikes.removeAll { t - $0.start > 30 }
            return (v * 0.6, v * 0.6)
        case .binaural:
            let n = pink() * 0.08
            return (sine(6, 200) * 0.18 + n, sine(7, 206) * 0.18 + n)
        default:
            return (0, 0)
        }
    }
}

/// Plays generated ambience, bells and your own file through one audio engine.
final class SoundEngine {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let bellPlayer = AVAudioPlayerNode()
    private let filePlayer = AVAudioPlayerNode()
    private var generator: AmbienceGenerator?
    private var format: AVAudioFormat?
    private var bell: AVAudioPCMBuffer?
    private var softBell: AVAudioPCMBuffer?
    private var tick: AVAudioPCMBuffer?
    private(set) var running = false

    var ambienceVolume: Float = 0.5 { didSet { source?.volume = ambienceVolume; filePlayer.volume = ambienceVolume } }

    func start(kind: Soundscape, fileURL: URL?) throws {
        stop()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate > 0 ? engine.outputNode.outputFormat(forBus: 0).sampleRate : 44_100
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        format = fmt
        let gen = AmbienceGenerator(sampleRate: rate)
        gen.kind = kind.isGenerated ? kind : .none
        generator = gen
        let node = AVAudioSourceNode(format: fmt) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for i in 0..<Int(frameCount) {
                let (a, b) = gen.next()
                l[i] = Float(max(-1, min(1, a))); r[i] = Float(max(-1, min(1, b)))
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.attach(bellPlayer)
        engine.attach(filePlayer)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        engine.connect(bellPlayer, to: engine.mainMixerNode, format: fmt)
        node.volume = ambienceVolume

        bell = makeBell(base: 329.6, seconds: 7, gain: 0.5, rate: rate)
        softBell = makeBell(base: 523.3, seconds: 4, gain: 0.25, rate: rate)
        tick = makeTick(rate: rate)

        if kind == .myFile, let fileURL, let file = try? AVAudioFile(forReading: fileURL),
           let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) {
            try? file.read(into: buffer)
            engine.connect(filePlayer, to: engine.mainMixerNode, format: file.processingFormat)
            filePlayer.volume = ambienceVolume
            filePlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        } else {
            engine.connect(filePlayer, to: engine.mainMixerNode, format: fmt)
        }
        engine.prepare()
        try engine.start()
        bellPlayer.play()
        if kind == .myFile { filePlayer.play() }
        running = true
    }

    func pause() { if running { engine.pause() } }
    func resume() { if running { try? engine.start(); bellPlayer.play() } }

    func stop() {
        guard running || source != nil else { return }
        filePlayer.stop(); bellPlayer.stop()
        engine.stop()
        if let source { engine.detach(source) }
        engine.detach(bellPlayer); engine.detach(filePlayer)
        source = nil
        running = false
    }

    func playBell(soft: Bool = false) {
        guard running, let b = soft ? softBell : bell else { return }
        bellPlayer.scheduleBuffer(b, at: nil, options: .interrupts)
        if !bellPlayer.isPlaying { bellPlayer.play() }
    }

    func playTick() {
        guard running, let tick else { return }
        bellPlayer.scheduleBuffer(tick, at: nil, options: .interrupts)
        if !bellPlayer.isPlaying { bellPlayer.play() }
    }

    /// Slowly brings the background sound to silence (sleep sessions).
    func fadeOut(over seconds: Double) async {
        let start = ambienceVolume
        let steps = 40
        for i in 1...steps {
            try? await Task.sleep(for: .seconds(seconds / Double(steps)))
            let v = start * Float(1 - Double(i) / Double(steps))
            source?.volume = v; filePlayer.volume = v
        }
    }

    private func makeBell(base: Double, seconds: Double, gain: Double, rate: Double) -> AVAudioPCMBuffer? {
        guard let format, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * rate)) else { return nil }
        buf.frameLength = buf.frameCapacity
        let partials: [(Double, Double, Double)] = [(1, 1, 1), (2.76, 0.45, 0.6), (5.4, 0.2, 0.35), (8.9, 0.08, 0.2)]
        for i in 0..<Int(buf.frameLength) {
            let t = Double(i) / rate
            var v = 0.0
            for (ratio, amp, decayScale) in partials {
                v += amp * sin(2 * .pi * base * ratio * t) * exp(-t / (seconds * 0.35 * decayScale))
            }
            let s = Float(v * gain * min(1, t * 200))
            buf.floatChannelData![0][i] = s
            buf.floatChannelData![1][i] = s
        }
        return buf
    }

    private func makeTick(rate: Double) -> AVAudioPCMBuffer? {
        guard let format, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(0.08 * rate)) else { return nil }
        buf.frameLength = buf.frameCapacity
        for i in 0..<Int(buf.frameLength) {
            let t = Double(i) / rate
            let s = Float(sin(2 * .pi * 880 * t) * exp(-t / 0.015) * 0.3)
            buf.floatChannelData![0][i] = s; buf.floatChannelData![1][i] = s
        }
        return buf
    }
}

// MARK: - Voice

final class SpeechWaiter: NSObject, AVSpeechSynthesizerDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(for synth: AVSpeechSynthesizer, _ u: AVSpeechUtterance) async {
        await withCheckedContinuation { c in
            continuation = c
            synth.speak(u)
        }
    }
    private func finish() { continuation?.resume(); continuation = nil }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { finish() }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { finish() }
}

enum Voices {
    /// Best installed voices for a language, premium first.
    static func available(_ lang: MLang) -> [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        var list = all.filter { $0.language == lang.locale }
        if list.isEmpty { list = all.filter { $0.language.hasPrefix(lang.rawValue) } }
        return list.sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    static func qualityName(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Standard"
        }
    }

    static func chosen(_ lang: MLang) -> AVSpeechSynthesisVoice? {
        let saved = UserDefaults.standard.string(forKey: "medVoice.\(lang.rawValue)") ?? ""
        return AVSpeechSynthesisVoice(identifier: saved) ?? available(lang).first ?? AVSpeechSynthesisVoice(language: lang.locale)
    }
}

// MARK: - Session player

@MainActor
final class MeditationPlayer: ObservableObject {
    static let shared = MeditationPlayer()

    enum State { case idle, running, paused, finished }
    @Published var state: State = .idle
    @Published var script: MeditationScript?
    @Published var caption = ""
    @Published var breath: BreathKind?
    @Published var breathSeconds: Double = 4
    @Published var breathLabel = ""
    @Published var pulseCount = 0
    @Published var elapsed: Double = 0
    @Published var total: Double = 600
    @Published var startedAt: Date?
    @Published var lang: MLang = .english

    @Published var voiceVolume: Float = (UserDefaults.standard.object(forKey: "medVoiceVol") as? Float) ?? 0.9 {
        didSet { UserDefaults.standard.set(voiceVolume, forKey: "medVoiceVol") }
    }
    @Published var musicVolume: Float = (UserDefaults.standard.object(forKey: "medMusicVol") as? Float) ?? 0.45 {
        didSet { UserDefaults.standard.set(musicVolume, forKey: "medMusicVol"); sound.ambienceVolume = musicVolume }
    }
    @Published var voiceRate: Float = (UserDefaults.standard.object(forKey: "medRate") as? Float) ?? 0.42 {
        didSet { UserDefaults.standard.set(voiceRate, forKey: "medRate") }
    }

    private let sound = SoundEngine()
    private let synth = AVSpeechSynthesizer()
    private let waiter = SpeechWaiter()
    private var runTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var usedAppleMusic = false

    init() { synth.delegate = waiter }

    var paused: Bool { state == .paused }

    func start(_ s: MeditationScript, minutes: Int, language: MLang, soundscape: Soundscape, fileURL: URL?) {
        stop()
        script = s; lang = language
        total = Double(minutes * 60)
        elapsed = 0; caption = ""; breath = nil; pulseCount = 0
        startedAt = .now
        state = .running

        let session = AVAudioSession.sharedInstance()
        let opts: AVAudioSession.CategoryOptions = soundscape == .appleMusic ? [.mixWithOthers, .duckOthers] : []
        try? session.setCategory(.playback, mode: .spokenAudio, options: opts)
        try? session.setActive(true)

        sound.ambienceVolume = musicVolume
        try? sound.start(kind: soundscape, fileURL: fileURL)
        usedAppleMusic = soundscape == .appleMusic
        if usedAppleMusic { Task { await MusicController.shared.startWorkoutMusic(force: true) } }

        setUpRemote()
        UIApplication.shared.isIdleTimerDisabled = true
        let steps = s.build(minutes)
        clockTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.state == .running || self.state == .paused {
                try? await Task.sleep(for: .milliseconds(250))
                if self.state == .running { self.elapsed += 0.25 }
                if Int(self.elapsed * 4) % 20 == 0 { self.updateNowPlaying() }
            }
        }
        runTask = Task { [weak self] in await self?.run(steps, sleepMode: s.sleepMode) }
    }

    func togglePause() {
        if state == .running {
            state = .paused
            synth.pauseSpeaking(at: .word)
            sound.pause()
            if usedAppleMusic { MusicController.shared.pauseIfPlaying() }
        } else if state == .paused {
            state = .running
            synth.continueSpeaking()
            sound.resume()
            if usedAppleMusic { Task { await MusicController.shared.togglePlayPause() } }
        }
        updateNowPlaying()
        Haptics.tap()
    }

    func stop() {
        runTask?.cancel(); clockTask?.cancel()
        runTask = nil; clockTask = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        sound.stop()
        if usedAppleMusic { MusicController.shared.stop(); usedAppleMusic = false }
        UIApplication.shared.isIdleTimerDisabled = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if state != .finished { state = .idle }
        breath = nil
    }

    func reset() { stop(); state = .idle; script = nil }

    // MARK: Running the steps

    private func waitSeconds(_ s: Double) async {
        var left = s
        while left > 0 && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            if state == .running { left -= 0.1 }
        }
    }

    private func estimate(_ step: MStep) -> Double {
        switch step {
        case .say(let line): return Double(line.text(lang).count) / (lang == .english ? 13 : 11) + 0.6
        case .wait(let s): return s
        case .breathe(let p, let c): return p.cycleSeconds * Double(c)
        case .pulses(let n, let i): return Double(n) * i
        case .bell: return 4
        case .softBell: return 2
        default: return 0
        }
    }

    private func weight(_ step: MStep) -> Double {
        switch step {
        case .pause(let w): return w
        case .breatheFill(_, let w): return w
        default: return 0
        }
    }

    private func run(_ steps: [MStep], sleepMode: Bool) async {
        for (i, step) in steps.enumerated() {
            if Task.isCancelled { return }
            // Share of the remaining time this flexible step gets.
            func allocation() -> Double {
                let rest = steps[(i + 1)...]
                let fixedAfter = rest.map(estimate).reduce(0, +)
                let weightLeft = steps[i...].map(weight).reduce(0, +)
                let spare = total - elapsed - fixedAfter
                return weightLeft > 0 ? max(0, spare) * weight(step) / weightLeft : 0
            }
            switch step {
            case .say(let line):
                await say(line.text(lang))
            case .wait(let s):
                await waitSeconds(s)
            case .pause:
                let secs = max(3, allocation())
                caption = ""
                if sleepMode && i >= steps.count - 1 {
                    Task { await self.sound.fadeOut(over: max(20, secs * 0.8)) }
                }
                await waitSeconds(secs)
            case .breathe(let p, let cycles):
                await breathe(p, cycles: cycles)
            case .breatheFill(let p, _):
                let cycles = max(2, Int((allocation() / p.cycleSeconds).rounded()))
                await breathe(p, cycles: cycles)
            case .pulses(let n, let interval):
                breath = nil
                for k in 1...n {
                    if Task.isCancelled { return }
                    pulseCount = k
                    sound.playTick()
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    await waitSeconds(interval)
                }
                pulseCount = 0
            case .bell:
                if !(sleepMode && i == steps.count - 1) { sound.playBell() }
                await waitSeconds(3)
            case .softBell:
                sound.playBell(soft: true)
                await waitSeconds(1.5)
            }
        }
        if Task.isCancelled { return }
        if sleepMode { await sound.fadeOut(over: 15) }
        finish()
    }

    private func finish() {
        caption = ""
        breath = nil
        state = .finished
        clockTask?.cancel()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        sound.stop()
        if usedAppleMusic { MusicController.shared.stop(); usedAppleMusic = false }
        UIApplication.shared.isIdleTimerDisabled = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        Haptics.success()
    }

    private func say(_ text: String) async {
        caption = text
        let u = AVSpeechUtterance(string: text)
        u.voice = Voices.chosen(lang)
        u.rate = voiceRate
        u.pitchMultiplier = 0.95
        u.volume = voiceVolume
        u.postUtteranceDelay = 0.35
        await waiter.wait(for: synth, u)
    }

    private func breathe(_ p: BreathPattern, cycles: Int) async {
        for c in 0..<cycles {
            if Task.isCancelled { return }
            // Spoken cues for the first three cycles, then every fourth — the circle and haptics guide the rest.
            let speak = c < 3 || c % 4 == 0
            for phase in p.phases {
                if Task.isCancelled { return }
                breathSeconds = phase.seconds
                breathLabel = phase.cue.text(lang)
                withAnimation(.easeInOut(duration: phase.seconds)) { breath = phase.kind }
                UIImpactFeedbackGenerator(style: phase.kind == .inhale ? .medium : .light).impactOccurred()
                if speak {
                    let u = AVSpeechUtterance(string: phase.cue.text(lang))
                    u.voice = Voices.chosen(lang); u.rate = voiceRate; u.volume = voiceVolume * 0.9
                    synth.speak(u)
                }
                await waitSeconds(phase.seconds)
            }
        }
        withAnimation(.easeInOut(duration: 1.5)) { breath = nil }
        breathLabel = ""
    }

    // MARK: Lock screen

    private func setUpRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.removeTarget(nil); c.pauseCommand.removeTarget(nil); c.togglePlayPauseCommand.removeTarget(nil)
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.state == .paused { self?.togglePause() } }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.state == .running { self?.togglePause() } }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePause() }; return .success }
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let script, !usedAppleMusic else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: script.title(lang),
            MPMediaItemPropertyArtist: "iLife Meditation",
            MPMediaItemPropertyPlaybackDuration: total,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state == .running ? 1.0 : 0.0,
        ]
    }
}
