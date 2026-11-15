import SwiftUI

// MARK: - Building blocks

enum MLang: String, CaseIterable, Identifiable, Codable {
    case english = "en", hindi = "hi"
    var id: String { rawValue }
    var title: String { self == .english ? "English" : "हिन्दी" }
    var locale: String { self == .english ? "en-IN" : "hi-IN" }
}

/// One line of guidance in both languages.
struct Line: Hashable, Codable {
    let en: String
    let hi: String
    init(_ en: String, _ hi: String) { self.en = en; self.hi = hi }
    func text(_ l: MLang) -> String { l == .english ? en : hi }
}

enum BreathKind: String, Codable { case inhale, hold, exhale, rest }

struct BreathPhase: Hashable {
    let kind: BreathKind
    let seconds: Double
    let cue: Line
}

struct BreathPattern: Hashable {
    let name: String
    let phases: [BreathPhase]
    var cycleSeconds: Double { phases.reduce(0) { $0 + $1.seconds } }

    static let inhaleCue = Line("Breathe in", "साँस लें")
    static let holdCue = Line("Hold", "रोकें")
    static let exhaleCue = Line("Breathe out", "साँस छोड़ें")

    static func simple(_ name: String, inhale: Double, hold1: Double = 0, exhale: Double, hold2: Double = 0) -> BreathPattern {
        var p: [BreathPhase] = [BreathPhase(kind: .inhale, seconds: inhale, cue: inhaleCue)]
        if hold1 > 0 { p.append(BreathPhase(kind: .hold, seconds: hold1, cue: holdCue)) }
        p.append(BreathPhase(kind: .exhale, seconds: exhale, cue: exhaleCue))
        if hold2 > 0 { p.append(BreathPhase(kind: .rest, seconds: hold2, cue: holdCue)) }
        return BreathPattern(name: name, phases: p)
    }

    static let box = simple("Box 4-4-4-4", inhale: 4, hold1: 4, exhale: 4, hold2: 4)
    static let fourSevenEight = simple("4-7-8", inhale: 4, hold1: 7, exhale: 8)
    static let calm = simple("Calm 4-6", inhale: 4, exhale: 6)
    static let slow = simple("Slow 5-7", inhale: 5, exhale: 7)
    static let energise = simple("Energise 4-2", inhale: 4, exhale: 2)
    static let anulomVilom = BreathPattern(name: "Anulom Vilom", phases: [
        BreathPhase(kind: .inhale, seconds: 4, cue: Line("In through the left", "बाईं नासिका से साँस लें")),
        BreathPhase(kind: .hold, seconds: 2, cue: Line("Switch", "बदलें")),
        BreathPhase(kind: .exhale, seconds: 6, cue: Line("Out through the right", "दाहिनी नासिका से छोड़ें")),
        BreathPhase(kind: .inhale, seconds: 4, cue: Line("In through the right", "दाहिनी नासिका से साँस लें")),
        BreathPhase(kind: .hold, seconds: 2, cue: Line("Switch", "बदलें")),
        BreathPhase(kind: .exhale, seconds: 6, cue: Line("Out through the left", "बाईं नासिका से छोड़ें")),
    ])
    static let bhramari = BreathPattern(name: "Bhramari", phases: [
        BreathPhase(kind: .inhale, seconds: 4, cue: inhaleCue),
        BreathPhase(kind: .exhale, seconds: 8, cue: Line("Hum softly as you breathe out", "धीरे से गुंजन करते हुए छोड़ें")),
        BreathPhase(kind: .rest, seconds: 2, cue: Line("Rest", "विश्राम")),
    ])
}

/// One step of a session. "Flexible" steps stretch so the session fits the length you pick.
enum MStep: Hashable {
    case say(Line)
    case pause(Double)                           // flexible silence; the number is its share of spare time
    case wait(Double)                            // fixed silence in seconds
    case breathe(BreathPattern, cycles: Int)     // fixed number of cycles
    case breatheFill(BreathPattern, Double)      // as many cycles as fit in its share of spare time
    case pulses(count: Int, interval: Double)    // e.g. Kapalbhati strokes, with a soft tick each
    case bell
    case softBell
}

enum MCategory: String, CaseIterable, Identifiable {
    case breathing = "Breathing", calm = "Calm & Stress", sleep = "Sleep", fitness = "Fitness", morning = "Morning", focus = "Focus", timer = "Timer"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .breathing: "wind"
        case .calm: "leaf.fill"
        case .sleep: "moon.stars.fill"
        case .fitness: "figure.cooldown"
        case .morning: "sunrise.fill"
        case .focus: "scope"
        case .timer: "timer"
        }
    }
}

struct MeditationScript: Identifiable {
    let id: String
    let title: String
    let hiTitle: String
    let category: MCategory
    let icon: String
    let colors: [Color]
    let summary: String
    let lengths: [Int]
    var sleepMode = false
    /// Set for AI-written sessions, which exist in one language only.
    var fixedLang: MLang? = nil
    let build: (Int) -> [MStep]

    var defaultLength: Int { lengths.count > 1 ? lengths[1] : lengths[0] }
    func title(_ l: MLang) -> String { l == .english ? title : hiTitle }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

private func L(_ en: String, _ hi: String) -> MStep { .say(Line(en, hi)) }

// MARK: - Shared openings and closings

private let settle: [MStep] = [
    .bell,
    .wait(3),
    L("Find a comfortable position. Let your hands rest, and gently close your eyes.",
      "आराम से बैठ जाइए। हाथों को ढीला छोड़ दीजिए और धीरे से आँखें बंद कर लीजिए।"),
    .wait(4),
    L("Take a deep breath in… and let it go slowly.", "एक गहरी साँस लीजिए… और धीरे-धीरे छोड़ दीजिए।"),
    .wait(5),
]

private func closing(_ extra: Line? = nil) -> [MStep] {
    var s: [MStep] = []
    if let extra { s.append(.say(extra)); s.append(.wait(4)) }
    s += [
        L("Slowly bring your attention back to the room. Notice the sounds around you.",
          "धीरे-धीरे अपना ध्यान वापस कमरे में लाइए। आसपास की आवाज़ों को महसूस कीजिए।"),
        .wait(4),
        L("Move your fingers and toes. When you're ready, open your eyes.",
          "उँगलियों को हल्का सा हिलाइए। जब आप तैयार हों, आँखें खोल लीजिए।"),
        .wait(3),
        .bell,
    ]
    return s
}

// MARK: - Library

enum MeditationLibrary {
    static let all: [MeditationScript] = [
        // ---------- Breathing ----------
        MeditationScript(id: "box", title: "Box Breathing", hiTitle: "बॉक्स ब्रीदिंग", category: .breathing, icon: "square",
                         colors: [.cyan, .blue], summary: "4 in · 4 hold · 4 out · 4 hold. Steadies the mind fast.", lengths: [3, 5, 10, 15]) { _ in
            settle + [
                L("We'll breathe in a square. In for four, hold for four, out for four, hold for four. Follow the circle and my voice.",
                  "हम एक चौकोर में साँस लेंगे। चार गिनती तक साँस लें, चार तक रोकें, चार तक छोड़ें, और चार तक रोकें। गोले और मेरी आवाज़ के साथ चलिए।"),
                .wait(2),
                .breatheFill(.box, 1),
                L("Let your breath return to its natural rhythm.", "अब साँस को अपनी सामान्य लय में आने दीजिए।"),
                .wait(8),
            ] + closing()
        },
        MeditationScript(id: "478", title: "4-7-8 Relax", hiTitle: "4-7-8 विश्राम", category: .breathing, icon: "wind",
                         colors: [.indigo, .purple], summary: "Long exhale breathing that calms the body. Great before sleep.", lengths: [3, 5, 10]) { _ in
            settle + [
                L("Breathe in quietly through the nose for four, hold for seven, and breathe out slowly through the mouth for eight.",
                  "नाक से चार तक साँस लें, सात तक रोकें, और मुँह से आठ तक धीरे-धीरे छोड़ें।"),
                .wait(2),
                .breatheFill(.fourSevenEight, 1),
                L("Rest now. Feel how much softer your body has become.", "अब आराम कीजिए। महसूस कीजिए कि शरीर कितना शांत हो गया है।"),
                .wait(10),
            ] + closing()
        },
        MeditationScript(id: "anulom", title: "Anulom Vilom", hiTitle: "अनुलोम विलोम", category: .breathing, icon: "arrow.left.arrow.right",
                         colors: [.teal, .green], summary: "Guided alternate-nostril breathing for balance and calm.", lengths: [5, 10, 15]) { _ in
            settle + [
                L("Sit tall with your spine straight. Bring your right hand up. Use the thumb to close the right nostril and the ring finger to close the left.",
                  "रीढ़ सीधी रखकर बैठिए। दाहिना हाथ ऊपर लाइए। अंगूठे से दाहिनी नासिका और अनामिका उँगली से बाईं नासिका बंद करनी है।"),
                .wait(4),
                L("Breathe out completely. Close the right nostril. We begin.", "पूरी साँस बाहर छोड़ दीजिए। दाहिनी नासिका बंद कीजिए। हम शुरू करते हैं।"),
                .wait(2),
                .breatheFill(.anulomVilom, 1),
                L("Lower your hand. Breathe normally through both nostrils.", "हाथ नीचे कर लीजिए। दोनों नासिकाओं से सामान्य साँस लीजिए।"),
                .wait(10),
            ] + closing()
        },
        MeditationScript(id: "bhramari", title: "Bhramari", hiTitle: "भ्रामरी प्राणायाम", category: .breathing, icon: "waveform",
                         colors: [.orange, .pink], summary: "Humming bee breath. Quietens a busy mind.", lengths: [3, 5, 10]) { _ in
            settle + [
                L("Gently close your ears with your thumbs, and rest your fingers lightly over your eyes.",
                  "अंगूठों से धीरे से कान बंद कीजिए और बाकी उँगलियाँ हल्के से आँखों पर रखिए।"),
                .wait(3),
                L("Breathe in through the nose. As you breathe out, make a soft humming sound, like a bee. Feel the vibration in your head.",
                  "नाक से साँस लीजिए। साँस छोड़ते समय मधुमक्खी जैसी हल्की गुंजन की आवाज़ कीजिए। सिर में कंपन महसूस कीजिए।"),
                .wait(2),
                .breatheFill(.bhramari, 1),
                L("Release your hands. Sit in the silence that follows.", "हाथ नीचे कर लीजिए। इसके बाद की शांति में बैठे रहिए।"),
                .pause(0.15),
            ] + closing()
        },
        MeditationScript(id: "kapalbhati", title: "Kapalbhati", hiTitle: "कपालभाति", category: .breathing, icon: "bolt.heart.fill",
                         colors: [.red, .orange], summary: "Three counted rounds of skull-shining breath. Avoid if pregnant, or with high BP or heart conditions.",
                         lengths: [5, 10]) { minutes in
            let strokes = minutes >= 10 ? 60 : 30
            var s = settle + [
                L("Sit tall. Breathe in deeply. Then breathe out sharply through the nose by pulling the belly in. Let the inhale happen by itself. Follow the ticks.",
                  "सीधे बैठिए। गहरी साँस लीजिए। फिर पेट को अंदर खींचते हुए नाक से झटके से साँस छोड़िए। साँस लेना अपने आप होने दीजिए। टिक की आवाज़ के साथ चलिए।"),
                .wait(3),
            ]
            for round in 1...3 {
                s += [L("Round \(round). Breathe in deeply… begin.", "राउंड \(round)। गहरी साँस लीजिए… शुरू कीजिए।"),
                      .pulses(count: strokes, interval: 1.0),
                      L("Stop. Breathe in fully, hold gently… and release.", "रुकिए। पूरी साँस लीजिए, हल्का सा रोकिए… और छोड़ दीजिए।"),
                      .wait(8),
                      L("Breathe normally and rest.", "सामान्य साँस लीजिए और आराम कीजिए।"),
                      .pause(1)]
            }
            return s + closing(Line("Notice the energy and stillness together.", "ऊर्जा और शांति को एक साथ महसूस कीजिए।"))
        },

        // ---------- Calm & stress ----------
        MeditationScript(id: "hearing", title: "Calm Before a Big Moment", hiTitle: "बड़े पल से पहले शांति", category: .calm, icon: "building.columns.fill",
                         colors: [.blue, .indigo], summary: "Before a hearing, meeting or presentation. Steady breath, clear head, confident voice.", lengths: [3, 5, 10]) { _ in
            settle + [
                L("You have prepared for this. Right now, the only task is to breathe.", "आपने इसकी तैयारी की है। इस समय आपका काम सिर्फ़ साँस लेना है।"),
                .wait(3),
                .breathe(.calm, cycles: 4),
                L("Notice your shoulders. Let them drop. Unclench your jaw. Soften your hands.",
                  "अपने कंधों पर ध्यान दीजिए। उन्हें ढीला छोड़िए। जबड़े को ढीला कीजिए। हाथों को नरम कीजिए।"),
                .pause(0.4),
                L("Picture yourself walking in calm and steady. You speak slowly. You listen fully. You answer clearly.",
                  "कल्पना कीजिए कि आप शांत और स्थिर होकर अंदर जा रहे हैं। आप धीरे बोलते हैं, पूरा सुनते हैं, और साफ़ जवाब देते हैं।"),
                .pause(0.6),
                L("Say to yourself: I am prepared. I am calm. I am clear.", "मन ही मन कहिए: मैं तैयार हूँ। मैं शांत हूँ। मेरा मन साफ़ है।"),
                .wait(6),
            ] + closing()
        },
        MeditationScript(id: "letgo", title: "After a Tough Day", hiTitle: "थके हुए दिन के बाद", category: .calm, icon: "cloud.sun.fill",
                         colors: [.purple, .pink], summary: "Let the day go, release tension, come back to yourself.", lengths: [5, 10, 15]) { _ in
            settle + [
                L("The day is done. Whatever happened, you don't have to carry it right now.", "दिन पूरा हो गया। जो भी हुआ, उसका बोझ अभी उठाने की ज़रूरत नहीं।"),
                .wait(4),
                .breathe(.slow, cycles: 4),
                L("Bring to mind one thing that weighed on you today. Just notice it, without judging.",
                  "आज की कोई एक बात याद कीजिए जो भारी लगी। बिना किसी फ़ैसले के बस उसे देखिए।"),
                .pause(0.3),
                L("With each breath out, imagine setting it down, like putting down a heavy bag.",
                  "हर बार साँस छोड़ते हुए कल्पना कीजिए कि आप उसे नीचे रख रहे हैं, जैसे कोई भारी थैला।"),
                .pause(0.4),
                L("Now think of one small thing that went well today. Stay with it for a moment.",
                  "अब आज की कोई एक छोटी अच्छी बात सोचिए। एक पल उसके साथ रहिए।"),
                .pause(0.3),
            ] + closing(Line("You did enough today. Rest is part of the work.", "आज आपने काफ़ी किया। आराम भी काम का हिस्सा है।"))
        },
        MeditationScript(id: "reset", title: "3-Minute Reset", hiTitle: "3 मिनट रीसेट", category: .calm, icon: "arrow.counterclockwise",
                         colors: [.mint, .teal], summary: "A quick reset between tasks. Eyes open is fine.", lengths: [3, 5]) { _ in
            [.softBell,
             L("Pause whatever you're doing. Feel your feet on the floor.", "जो भी कर रहे हैं, एक पल रुकिए। पैरों को ज़मीन पर महसूस कीजिए।"),
             .wait(3),
             L("Three slow breaths, longer out than in.", "तीन धीमी साँसें, छोड़ना लेने से लंबा।"),
             .breathe(.calm, cycles: 3),
             L("Now just notice: what do you hear? What do you feel in your body?", "अब बस ध्यान दीजिए: क्या सुनाई दे रहा है? शरीर में क्या महसूस हो रहा है?"),
             .pause(1),
             L("Choose the one next thing you'll do. Then begin it, calmly.", "अगला एक काम चुनिए जो आप करेंगे। फिर शांति से शुरू कीजिए।"),
             .wait(3),
             .softBell]
        },
        MeditationScript(id: "kindness", title: "Kindness", hiTitle: "मैत्री भावना", category: .calm, icon: "heart.fill",
                         colors: [.pink, .red], summary: "Loving-kindness for yourself, family and others.", lengths: [5, 10, 15]) { _ in
            settle + [
                L("Place a hand on your heart. Silently say: May I be healthy. May I be peaceful. May I be strong.",
                  "हाथ को दिल पर रखिए। मन में कहिए: मैं स्वस्थ रहूँ। मैं शांत रहूँ। मैं मज़बूत रहूँ।"),
                .pause(0.25),
                L("Now think of someone you love. May you be healthy. May you be peaceful. May you be happy.",
                  "अब किसी प्रिय व्यक्ति को याद कीजिए। तुम स्वस्थ रहो। तुम शांत रहो। तुम खुश रहो।"),
                .pause(0.25),
                L("Think of someone you find difficult. As best you can: may you find peace too.",
                  "अब किसी ऐसे व्यक्ति को याद कीजिए जिनसे निभाना मुश्किल है। जितना हो सके: तुम्हें भी शांति मिले।"),
                .pause(0.25),
                L("And finally, everyone everywhere. May all beings be well.", "और अंत में, सभी के लिए। सर्वे भवन्तु सुखिनः। सब सुखी रहें।"),
                .pause(0.25),
            ] + closing()
        },

        // ---------- Sleep ----------
        MeditationScript(id: "bodyscan", title: "Body Scan for Sleep", hiTitle: "नींद के लिए बॉडी स्कैन", category: .sleep, icon: "bed.double.fill",
                         colors: [.indigo, .blue], summary: "Relax each part of the body, from feet to head.", lengths: [10, 15, 20], sleepMode: true) { _ in
            let parts: [(String, String)] = [("your feet", "अपने पैरों के पंजों"), ("your calves and knees", "पिंडलियों और घुटनों"), ("your thighs and hips", "जाँघों और कूल्हों"),
                                              ("your belly", "पेट"), ("your chest", "सीने"), ("your back", "पीठ"), ("your hands and arms", "हाथों और बाँहों"),
                                              ("your shoulders and neck", "कंधों और गर्दन"), ("your face, jaw and eyes", "चेहरे, जबड़े और आँखों"), ("the top of your head", "सिर के ऊपरी हिस्से")]
            var s: [MStep] = [.softBell, .wait(3),
                              L("Lie down comfortably. Let the bed hold your whole weight.", "आराम से लेट जाइए। अपने पूरे शरीर का भार बिस्तर पर छोड़ दीजिए।"),
                              .wait(4), .breathe(.slow, cycles: 3)]
            for (en, hi) in parts {
                s += [L("Bring your attention to \(en). Let them become heavy and warm.", "अब ध्यान \(hi) पर लाइए। उन्हें भारी और गर्म होने दीजिए।"), .pause(1)]
            }
            return s + [L("Your whole body is heavy, warm and still. There is nothing to do now. Just rest, and drift.",
                          "आपका पूरा शरीर भारी, गर्म और शांत है। अब कुछ करने की ज़रूरत नहीं। बस आराम कीजिए और नींद में उतर जाइए।"),
                        .pause(2)]
        },
        MeditationScript(id: "nidra", title: "Yoga Nidra", hiTitle: "योग निद्रा", category: .sleep, icon: "moon.zzz.fill",
                         colors: [.purple, .indigo], summary: "Deep guided relaxation lying down — sankalpa, body rotation, breath and visualisation.",
                         lengths: [15, 20, 30]) { _ in
            let rotation: [(String, String)] = [("right hand thumb", "दाहिने हाथ का अँगूठा"), ("right palm", "दाहिनी हथेली"), ("right elbow", "दाहिनी कोहनी"),
                                                 ("right shoulder", "दाहिना कंधा"), ("right hip", "दाहिना कूल्हा"), ("right knee", "दाहिना घुटना"), ("right foot", "दाहिना पैर"),
                                                 ("left hand thumb", "बाएँ हाथ का अँगूठा"), ("left palm", "बाईं हथेली"), ("left elbow", "बाईं कोहनी"),
                                                 ("left shoulder", "बायाँ कंधा"), ("left hip", "बायाँ कूल्हा"), ("left knee", "बायाँ घुटना"), ("left foot", "बायाँ पैर"),
                                                 ("the back", "पीठ"), ("the belly", "पेट"), ("the chest", "सीना"), ("the forehead", "माथा"), ("the whole body", "पूरा शरीर")]
            var s: [MStep] = [.bell, .wait(3),
                              L("Lie on your back in shavasana, arms a little away from the body, palms facing up. Stay awake, and simply listen.",
                                "शवासन में पीठ के बल लेट जाइए, हाथ शरीर से थोड़ा दूर, हथेलियाँ ऊपर की ओर। जागते रहिए और बस सुनते रहिए।"),
                              .wait(5),
                              L("Make a short positive resolve — your sankalpa. Repeat it three times in your mind.",
                                "एक छोटा सा सकारात्मक संकल्प लीजिए। उसे मन में तीन बार दोहराइए।"),
                              .wait(12),
                              L("Now move your awareness through the body as I name each part. Just feel it.",
                                "अब जैसे-जैसे मैं शरीर के अंगों का नाम लूँ, वहाँ ध्यान ले जाइए। बस उसे महसूस कीजिए।"),
                              .wait(3)]
            for (en, hi) in rotation { s += [L(en, hi), .wait(4)] }
            s += [L("Now watch the natural breath. Count backwards from twenty-seven: breathing in, twenty-seven; breathing out, twenty-seven.",
                    "अब स्वाभाविक साँस को देखिए। सत्ताईस से उल्टी गिनती कीजिए: साँस अंदर, सत्ताईस; साँस बाहर, सत्ताईस।"),
                  .pause(1.5),
                  L("Imagine a calm lake at sunrise. Still water. Soft light. You are resting by the water.",
                    "सूर्योदय के समय एक शांत झील की कल्पना कीजिए। ठहरा हुआ पानी, हल्की रोशनी। आप पानी के पास आराम कर रहे हैं।"),
                  .pause(1.5),
                  L("Remember your sankalpa. Repeat it three times with full feeling.", "अपना संकल्प याद कीजिए। उसे पूरे भाव के साथ तीन बार दोहराइए।"),
                  .wait(12)]
            return s + closing(Line("Yoga Nidra is complete.", "योग निद्रा पूर्ण हुई।"))
        },
        MeditationScript(id: "drift", title: "Drift to Sleep", hiTitle: "धीरे-धीरे नींद", category: .sleep, icon: "sparkles",
                         colors: [.blue, .black], summary: "Slow breathing and soft sound that fades out as you fall asleep. No bell at the end.",
                         lengths: [10, 20, 30, 45], sleepMode: true) { _ in
            [.softBell, .wait(3),
             L("Settle into bed. Let tonight's thoughts pass like clouds.", "बिस्तर में आराम से लेट जाइए। आज के विचारों को बादलों की तरह गुज़र जाने दीजिए।"),
             .wait(5),
             L("Breathe in for four, out for six. You don't need to do it perfectly.", "चार तक साँस लीजिए, छह तक छोड़िए। इसे परफ़ेक्ट करने की ज़रूरत नहीं।"),
             .breathe(.calm, cycles: 6),
             L("Now let the breath go on its own. Listen to the sound. Let it carry you.", "अब साँस को अपने आप चलने दीजिए। आवाज़ को सुनिए। उसे आपको बहा ले जाने दीजिए।"),
             .pause(1)]
        },

        // ---------- Fitness ----------
        MeditationScript(id: "preworkout", title: "Pre-Workout Focus", hiTitle: "वर्कआउट से पहले फोकस", category: .fitness, icon: "bolt.fill",
                         colors: [.orange, .red], summary: "Energising breath and intention before you train.", lengths: [3, 5]) { _ in
            [.bell, .wait(2),
             L("Stand or sit tall. Feel strong through your spine.", "सीधे खड़े या बैठ जाइए। रीढ़ में मज़बूती महसूस कीजिए।"),
             .wait(3),
             L("Quick, strong breaths: in deep, out fast.", "तेज़ और मज़बूत साँसें: गहरी साँस अंदर, तेज़ी से बाहर।"),
             .breathe(.energise, cycles: 8),
             L("Picture today's main lift or run. See yourself doing it with perfect form, controlled and strong.",
               "आज की मुख्य एक्सरसाइज़ की कल्पना कीजिए। खुद को सही फ़ॉर्म में, नियंत्रण और ताकत के साथ करते हुए देखिए।"),
             .pause(1),
             L("Set one intention for this session: one word. Hold it. Now go and train.",
               "इस सेशन के लिए एक शब्द का इरादा तय कीजिए। उसे पकड़े रखिए। अब जाइए और ट्रेन कीजिए।"),
             .wait(2), .bell]
        },
        MeditationScript(id: "recovery", title: "Post-Workout Recovery", hiTitle: "वर्कआउट के बाद रिकवरी", category: .fitness, icon: "figure.cooldown",
                         colors: [.green, .teal], summary: "Bring the heart rate down and let the muscles recover.", lengths: [5, 10]) { _ in
            settle + [
                L("Great work. Let your heart rate come down now. Longer breaths out than in.", "बहुत बढ़िया। अब धड़कन को धीमा होने दीजिए। साँस छोड़ना लेने से लंबा रखिए।"),
                .breatheFill(.slow, 0.5),
                L("Scan the muscles you trained. Breathe into them and let them soften.", "जिन मांसपेशियों पर काम किया, उन पर ध्यान दीजिए। उनमें साँस भेजिए और उन्हें ढीला होने दीजिए।"),
                .pause(0.5),
                L("Remember: water, protein, and good sleep tonight. That's when you get stronger.",
                  "याद रखिए: पानी, प्रोटीन, और आज रात अच्छी नींद। मज़बूती तभी आती है।"),
                .wait(4),
            ] + closing()
        },

        // ---------- Morning ----------
        MeditationScript(id: "gratitude", title: "Gratitude & Intention", hiTitle: "कृतज्ञता और संकल्प", category: .morning, icon: "sun.max.fill",
                         colors: [.yellow, .orange], summary: "Start the day grateful and with a clear intention.", lengths: [5, 10]) { _ in
            settle + [
                L("Good morning. Think of three things you are grateful for today. Take your time with each.",
                  "सुप्रभात। आज की तीन ऐसी चीज़ें सोचिए जिनके लिए आप आभारी हैं। हर एक पर थोड़ा समय दीजिए।"),
                .pause(0.4),
                L("Now think about the day ahead. What is the one most important thing you will do?", "अब आने वाले दिन के बारे में सोचिए। आज का सबसे ज़रूरी एक काम क्या है?"),
                .pause(0.3),
                L("How do you want to be today? Calm? Patient? Focused? Choose one word.", "आज आप कैसे रहना चाहते हैं? शांत? धैर्यवान? केंद्रित? एक शब्द चुनिए।"),
                .pause(0.3),
            ] + closing(Line("Carry that word with you through the day.", "उस शब्द को पूरे दिन अपने साथ रखिए।"))
        },
        MeditationScript(id: "energise", title: "Morning Energiser", hiTitle: "सुबह की ऊर्जा", category: .morning, icon: "sunrise.fill",
                         colors: [.orange, .yellow], summary: "Wake up the body with breath and gentle movement.", lengths: [3, 5]) { _ in
            [.bell, .wait(2),
             L("Sit up tall. Stretch your arms overhead, and breathe in.", "सीधे बैठिए। हाथों को ऊपर फैलाइए और साँस लीजिए।"),
             .wait(4),
             L("Breathe out and bring them down. Again: arms up, breathe in. Arms down, breathe out.", "साँस छोड़ते हुए हाथ नीचे लाइए। फिर से: हाथ ऊपर, साँस अंदर। हाथ नीचे, साँस बाहर।"),
             .breathe(.energise, cycles: 6),
             L("Roll your shoulders back. Turn gently left… and right.", "कंधों को पीछे घुमाइए। धीरे से बाईं ओर मुड़िए… और दाईं ओर।"),
             .pause(1),
             L("Three deep breaths to finish. You're awake and ready.", "अंत में तीन गहरी साँसें। आप जाग चुके हैं और तैयार हैं।"),
             .breathe(.calm, cycles: 3),
             .bell]
        },

        // ---------- Focus ----------
        MeditationScript(id: "mindful", title: "Mindful Breathing", hiTitle: "सजग श्वास", category: .focus, icon: "circle.dotted",
                         colors: [.teal, .cyan], summary: "The basic practice: rest attention on the breath, return when the mind wanders.",
                         lengths: [5, 10, 15, 20]) { _ in
            settle + [
                L("Feel the breath where it's easiest: the nose, the chest, or the belly.", "साँस को वहाँ महसूस कीजिए जहाँ सबसे आसान हो: नाक, सीना, या पेट।"),
                .pause(0.3),
                L("When the mind wanders, and it will, gently notice where it went, and come back to the breath. That coming back is the practice.",
                  "जब मन भटके, और वह भटकेगा, तो धीरे से देखिए कि वह कहाँ गया, और साँस पर लौट आइए। यही लौटना ही अभ्यास है।"),
                .pause(0.4),
                L("Still here. Breathing in… breathing out.", "अब भी यहीं। साँस अंदर… साँस बाहर।"),
                .pause(0.3),
            ] + closing()
        },
        MeditationScript(id: "deepwork", title: "Focus for Deep Work", hiTitle: "गहरे काम के लिए फोकस", category: .focus, icon: "brain.head.profile",
                         colors: [.blue, .cyan], summary: "Clear the mind before reading, drafting or study.", lengths: [3, 5, 10]) { _ in
            [.softBell,
             L("Close your eyes. Notice everything still on your mind. Name each thing in one word, and set it aside for now.",
               "आँखें बंद कीजिए। मन में चल रही हर बात को देखिए। हर एक को एक शब्द में नाम दीजिए और अभी के लिए अलग रख दीजिए।"),
             .pause(0.4),
             .breathe(.box, cycles: 4),
             L("Now bring to mind the one task in front of you. What does finished look like?", "अब सामने वाले एक काम को याद कीजिए। पूरा होने पर वह कैसा दिखेगा?"),
             .pause(0.3),
             L("For the next block of time, that's all there is. Open your eyes and begin.", "अगले कुछ समय के लिए बस यही काम है। आँखें खोलिए और शुरू कीजिए।"),
             .wait(2), .softBell]
        },

        // ---------- Timer ----------
        MeditationScript(id: "silent", title: "Silent Timer", hiTitle: "मौन टाइमर", category: .timer, icon: "bell.fill",
                         colors: [.gray, .black], summary: "Bells only. A soft chime every 5 minutes.", lengths: [5, 10, 15, 20, 30, 45, 60]) { minutes in
            var s: [MStep] = [.bell]
            let blocks = max(1, minutes / 5)
            for i in 0..<blocks {
                s.append(.pause(1))
                if i < blocks - 1 { s.append(.softBell) }
            }
            s.append(.bell)
            return s
        },
    ]

    static func find(_ id: String) -> MeditationScript? { all.first { $0.id == id } }

    /// Turns an AI-written custom session into a script.
    static func custom(id: String, title: String, steps: [CustomStep], lang: MLang) -> MeditationScript {
        let seconds = steps.reduce(0.0) { $0 + $1.pauseAfter + Double($1.say.count) / 13 }
        return MeditationScript(id: id, title: title, hiTitle: title, category: .calm, icon: "sparkles", colors: [.purple, .cyan],
                         summary: "Written for you by AI", lengths: [max(1, Int((seconds / 60).rounded()))], fixedLang: lang) { _ in
            var s: [MStep] = [.bell, .wait(2)]
            for step in steps {
                if !step.say.isEmpty { s.append(.say(Line(step.say, step.say))) }
                if step.pauseAfter > 0 { s.append(.wait(step.pauseAfter)) }
            }
            return s + [.bell]
        }
    }
}

struct CustomStep: Codable, Hashable {
    var say: String
    var pauseAfter: Double
}
