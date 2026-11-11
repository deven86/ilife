import WidgetKit
import SwiftUI
import ActivityKit

@main
struct ILifeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayTargetWidget()
        WorkoutLiveActivity()
    }
}

// MARK: - Today's Target widget

struct TargetEntry: TimelineEntry {
    let date: Date
    let snap: TodaySnapshot
}

struct TargetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TargetEntry {
        TargetEntry(date: .now, snap: TodaySnapshot(steps: 8450, activeCalories: 520, exerciseMinutes: 42, waterLitres: 2.1, caloriesEaten: 1450))
    }
    func getSnapshot(in context: Context, completion: @escaping (TargetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : TargetEntry(date: .now, snap: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TargetEntry>) -> Void) {
        completion(Timeline(entries: [TargetEntry(date: .now, snap: .load())], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct TodayTargetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayTarget", provider: TargetProvider()) { entry in
            TodayTargetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.05, green: 0.15, blue: 0.3), Color(red: 0.05, green: 0.3, blue: 0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Today's Target")
        .description("Steps, calories, workout and water goals at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct TodayTargetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TargetEntry
    private var s: TodaySnapshot { entry.snap }

    private func p(_ v: Double, _ g: Double) -> Double { g > 0 ? min(v / g, 1) : 0 }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: p(s.steps, s.stepGoal)) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text("\(Int(p(s.steps, s.stepGoal) * 100))")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("iLife · Today").font(.caption2.bold())
                Text("\(Int(s.steps).formatted()) steps")
                Text("\(Int(s.activeCalories)) kcal · \(Int(s.exerciseMinutes)) min").font(.caption2)
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's Target").font(.caption.bold()).foregroundStyle(.white.opacity(0.8))
                ZStack {
                    ring(p(s.activeCalories, s.calorieGoal), .orange, 0)
                    ring(p(s.exerciseMinutes, s.exerciseGoal), .green, 12)
                    ring(p(s.steps, s.stepGoal), .cyan, 24)
                }
                .frame(width: 84, height: 84)
                .frame(maxWidth: .infinity)
                Text("\(Int(s.steps).formatted()) steps").font(.caption2.bold()).foregroundStyle(.white)
            }
        default:
            HStack(spacing: 16) {
                ZStack {
                    ring(p(s.activeCalories, s.calorieGoal), .orange, 0)
                    ring(p(s.exerciseMinutes, s.exerciseGoal), .green, 12)
                    ring(p(s.steps, s.stepGoal), .cyan, 24)
                }
                .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's Target").font(.headline).foregroundStyle(.white)
                    row("figure.walk", .cyan, "\(Int(s.steps).formatted()) / \(Int(s.stepGoal).formatted())")
                    row("flame.fill", .orange, "\(Int(s.activeCalories)) / \(Int(s.calorieGoal)) kcal")
                    row("dumbbell.fill", .green, "\(Int(s.exerciseMinutes)) / \(Int(s.exerciseGoal)) min")
                    row("drop.fill", .blue, String(format: "%.1f / %.1f L", s.waterLitres, s.waterGoal))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func ring(_ v: Double, _ c: Color, _ inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(c.opacity(0.2), lineWidth: 9)
            Circle().trim(from: 0, to: v).stroke(c, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }

    private func row(_ icon: String, _ c: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(c).frame(width: 16)
            Text(text).font(.caption).foregroundStyle(.white)
        }
    }
}

// MARK: - Workout Live Activity (Lock Screen + Dynamic Island)

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.workoutName, systemImage: "figure.strengthtraining.traditional")
                        .font(.caption.bold()).foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state).font(.title3.monospacedDigit().bold()).foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.heartRate > 0 { Label("\(context.state.heartRate) bpm", systemImage: "heart.fill").foregroundStyle(.red) }
                        Label("\(context.state.calories) kcal", systemImage: "flame.fill").foregroundStyle(.orange)
                        Spacer()
                        if let song = context.state.songTitle { Label(song, systemImage: "music.note").lineLimit(1) }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "figure.run").foregroundStyle(.green)
            } compactTrailing: {
                timer(context.state).monospacedDigit().frame(width: 52).foregroundStyle(.green)
            } minimal: {
                Image(systemName: "figure.run").foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    func timer(_ s: WorkoutActivityAttributes.ContentState) -> some View {
        if s.isPaused { Text("Paused") } else { Text(s.startedAt, style: .timer) }
    }
}

struct LockScreenWorkoutView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional").font(.title).foregroundStyle(.black)
                .frame(width: 48, height: 48).background(.green, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.workoutName).font(.headline).foregroundStyle(.green)
                Text(context.state.currentExercise).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                HStack(spacing: 10) {
                    if context.state.heartRate > 0 { Label("\(context.state.heartRate)", systemImage: "heart.fill").foregroundStyle(.red) }
                    Label("\(context.state.calories) kcal", systemImage: "flame.fill").foregroundStyle(.orange)
                    if let song = context.state.songTitle { Label(song, systemImage: "music.note").foregroundStyle(.pink).lineLimit(1) }
                }
                .font(.caption2)
            }
            Spacer()
            Group {
                if context.state.isPaused { Text("Paused") } else { Text(context.state.startedAt, style: .timer) }
            }
            .font(.title2.monospacedDigit().bold()).foregroundStyle(.white).frame(width: 90, alignment: .trailing)
        }
        .padding()
    }
}
