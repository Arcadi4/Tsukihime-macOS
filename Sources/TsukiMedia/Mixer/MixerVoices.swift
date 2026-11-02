import Foundation

/// The mixer voice slot of every sound source (the layout of `AudioMixer.maxVoices` = 64):
/// PS4 stream numbers 0..25 keep their numbers, system voices sit at 0x2C..0x2F (with the right clip
/// of each pair on 26..29), and movie audio of slot s plays on 0x30 + s.
public enum MixerVoices {
    /// First system voice (0x2C).
    public static let firstSystem = 0x2C

    /// Number of system voices (4, rotating).
    public static let systemCount = 4

    /// First movie voice (0x30).
    public static let firstMovie = 0x30

    /// Number of movie voices (slots 0..15).
    public static let movieCount = AudioMixer.maxVoices - firstMovie

    /// The voice of sound stream (0..25).
    public static func stream(_ stream: Int) -> Int {
        guard stream >= 0 && stream < 26 else {
            fatalError("streams are 0..25, got \(stream)")
        }
        return stream
    }

    /// The voice of system voice (0x2C..0x2F).
    public static func system(_ voice: Int) -> Int {
        guard voice >= firstSystem && voice < firstSystem + systemCount else {
            fatalError("system voices are 0x2C..0x2F, got \(voice)")
        }
        return voice
    }

    /// The mixer voice of the right half of a system sound: SystemSE_Play plays two HE-VAG clips,
    /// the left one hard left on `system(voice)` and the right one hard right on this voice (26..29).
    public static func systemRight(_ voice: Int) -> Int {
        system(voice) - firstSystem + 26
    }

    /// The voice of the audio of movie slot.
    public static func movie(_ slot: Int) -> Int {
        guard slot >= 0 && slot < movieCount else {
            fatalError("movie slots are 0..\(movieCount - 1), got \(slot)")
        }
        return firstMovie + slot
    }
}
