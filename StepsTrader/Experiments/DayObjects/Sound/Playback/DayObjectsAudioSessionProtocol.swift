import AVFAudio

@MainActor
protocol DayObjectsAudioSessionProtocol: AnyObject {
    func configurePlayback() throws
    func activate() throws
    func deactivate(options: AVAudioSession.SetActiveOptions) throws
}

@MainActor
final class DayObjectsSystemAudioSession: DayObjectsAudioSessionProtocol {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func configurePlayback() throws {
        try session.setCategory(.playback)
    }

    func activate() throws {
        try session.setActive(true)
    }

    func deactivate(options: AVAudioSession.SetActiveOptions) throws {
        try session.setActive(false, options: options)
    }
}
