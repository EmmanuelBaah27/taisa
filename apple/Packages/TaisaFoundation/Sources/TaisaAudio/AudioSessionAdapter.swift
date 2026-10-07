import Foundation

public protocol AudioSessionAdapting: Sendable {
    func requestRecordPermission() async -> Bool
    func activate() async throws
    func deactivate() async
}

#if os(iOS)
import AVFoundation

public actor SystemAudioSessionAdapter: AudioSessionAdapting {
    public init() {}

    public func requestRecordPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public func activate() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio, options: [.allowBluetoothHFP])
        try session.setActive(true)
    }

    public func deactivate() async {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
#else
public actor SystemAudioSessionAdapter: AudioSessionAdapting {
    public init() {}
    public func requestRecordPermission() async -> Bool { false }
    public func activate() async throws { throw AudioCaptureError.unsupportedPlatform }
    public func deactivate() async {}
}
#endif
