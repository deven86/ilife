import SwiftUI
import SwiftData
import MusicKit

struct ActiveWorkoutView: View {
    @EnvironmentObject var session: WorkoutSessionController
    @EnvironmentObject var music: MusicController
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmEnd = false
    @State private var showPlaylists = false

    var body: some View {
        ZStack {
            WallpaperView()
            VStack(spacing: 20) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3.bold()) }
                    Spacer()
                    Text(session.name).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down").opacity(0)
                }
                .padding(.horizontal)

                Text(Duration.seconds(session.elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.green)
                    .contentTransition(.numericText())

                HStack(spacing: 12) {
                    MetricTile(title: "Heart Rate", value: session.heartRate > 0 ? "\(session.heartRate)" : "–", unit: "bpm", icon: "heart.fill", color: .red)
                    MetricTile(title: "Calories", value: "\(Int(session.calories))", unit: "kcal", icon: "flame.fill", color: .orange)
                }
                .padding(.horizontal)

                if !session.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exercise \(session.exerciseIndex + 1) of \(session.exercises.count)").font(.caption).foregroundStyle(.secondary)
                        Text(session.currentExercise).font(.title2.bold())
                        if session.exerciseIndex + 1 < session.exercises.count {
                            Text("Next: \(session.exercises[session.exerciseIndex + 1])").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Next exercise", systemImage: "forward.fill") { session.nextExercise() }
                            .buttonStyle(.bordered)
                            .disabled(session.exerciseIndex + 1 >= session.exercises.count)
                    }
                    .glassCard().padding(.horizontal)
                }

                musicCard.padding(.horizontal)

                Spacer()

                HStack(spacing: 40) {
                    Button { session.togglePause() } label: {
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill").font(.title)
                            .frame(width: 76, height: 76)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(.green)

                    Button { confirmEnd = true } label: {
                        Image(systemName: "stop.fill").font(.title).frame(width: 76, height: 76)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(.red)
                }
                .padding(.bottom, 30)
            }
            .padding(.top)
        }
        .confirmationDialog("End workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Save workout") { Task { await session.finish(context: context, save: true); dismiss() } }
            Button("Discard", role: .destructive) { Task { await session.finish(context: context, save: false); dismiss() } }
        }
        .sheet(isPresented: $showPlaylists) { PlaylistPicker() }
    }

    private var musicCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note").font(.title2).foregroundStyle(.pink)
                .frame(width: 44, height: 44).background(.pink.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading) {
                Text(music.nowPlaying ?? (music.authorization == .authorized ? "Pick a playlist" : "Apple Music not connected"))
                    .font(.subheadline.bold()).lineLimit(1)
                Text(music.nowPlayingArtist ?? "Tap to choose music").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .onTapGesture { showPlaylists = true }
            Spacer()
            Button { Task { await music.previous() } } label: { Image(systemName: "backward.fill") }
            Button { Task { await music.togglePlayPause() } } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.title3) }
            Button { Task { await music.skip() } } label: { Image(systemName: "forward.fill") }
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 18, padding: 12)
    }
}

struct PlaylistPicker: View {
    @EnvironmentObject var music: MusicController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if music.authorization != .authorized {
                    ContentUnavailableView {
                        Label("Connect Apple Music", systemImage: "music.note")
                    } description: {
                        Text("iLife needs access to your Apple Music library to play your workout playlist.")
                    } actions: {
                        Button("Connect") { Task { await music.requestAccess() } }.buttonStyle(.borderedProminent)
                    }
                } else if music.playlists.isEmpty {
                    ContentUnavailableView("No playlists", systemImage: "music.note.list",
                                           description: Text("Create or add playlists in the Music app first."))
                } else {
                    List(music.playlists) { p in
                        Button {
                            music.workoutPlaylistID = p.id.rawValue
                            Task { await music.play(p) }
                            dismiss()
                        } label: {
                            HStack {
                                if let art = p.artwork { ArtworkImage(art, width: 44) .clipShape(RoundedRectangle(cornerRadius: 6)) }
                                Text(p.name)
                                Spacer()
                                if p.id.rawValue == music.workoutPlaylistID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Workout Music")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await music.loadPlaylists() }
        }
    }
}
