import Foundation
import MusicKit
import SwiftUI

/// Apple Music: browse library playlists, pick a workout playlist, auto-play when a session starts.
/// Requires an Apple Music subscription and the MusicKit App Service enabled for com.jondhale.ilife.
@MainActor
final class MusicController: ObservableObject {
    static let shared = MusicController()

    @Published var authorization: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @Published var playlists: [Playlist] = []
    @Published var nowPlaying: String?
    @Published var nowPlayingArtist: String?
    @Published var isPlaying = false
    @Published var lastError: String?

    @AppStorage("workoutPlaylistID") var workoutPlaylistID: String = ""
    @AppStorage("autoPlayMusic") var autoPlay: Bool = true

    private let player = ApplicationMusicPlayer.shared

    func requestAccess() async {
        authorization = await MusicAuthorization.request()
        if authorization == .authorized { await loadPlaylists() }
    }

    func loadPlaylists() async {
        guard authorization == .authorized else { return }
        do {
            let request = MusicLibraryRequest<Playlist>()
            playlists = Array(try await request.response().items)
        } catch {
            lastError = "Couldn't load playlists: \(error.localizedDescription)"
        }
    }

    var selectedPlaylist: Playlist? { playlists.first { $0.id.rawValue == workoutPlaylistID } }

    func play(_ playlist: Playlist) async {
        do {
            player.queue = [playlist]
            player.state.shuffleMode = .songs
            try await player.play()
            isPlaying = true
            refreshNowPlaying()
        } catch {
            lastError = "Playback failed: \(error.localizedDescription)"
        }
    }

    /// Called when a workout session starts.
    func startWorkoutMusic() async {
        guard autoPlay, authorization == .authorized else { return }
        if playlists.isEmpty { await loadPlaylists() }
        if let p = selectedPlaylist ?? playlists.first { await play(p) }
    }

    func togglePlayPause() async {
        if player.state.playbackStatus == .playing { player.pause(); isPlaying = false }
        else { try? await player.play(); isPlaying = true }
        refreshNowPlaying()
    }

    func skip() async { try? await player.skipToNextEntry(); refreshNowPlaying() }
    func previous() async { try? await player.skipToPreviousEntry(); refreshNowPlaying() }
    func stop() { player.stop(); isPlaying = false }

    func refreshNowPlaying() {
        nowPlaying = player.queue.currentEntry?.title
        nowPlayingArtist = player.queue.currentEntry?.subtitle
        isPlaying = player.state.playbackStatus == .playing
    }
}
