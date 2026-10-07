import Foundation

public protocol AudioRecorderAdapting: Sendable {
    func start(at url: URL) async throws
    func pause() async
    func resume() async throws
    func stop() async throws -> AudioRecordingSummary
    func cancel() async
    func meter() async -> AudioMeterSample
}

#if canImport(AVFoundation)
@preconcurrency import AVFoundation

public actor SystemAudioRecorderAdapter: AudioRecorderAdapting {
    private var recorder: AVAudioRecorder?

    public init() {}

    public func start(at url: URL) async throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw AudioCaptureError.invalidState }
        self.recorder = recorder
    }

    public func pause() async {
        recorder?.pause()
    }

    public func resume() async throws {
        guard recorder?.record() == true else { throw AudioCaptureError.invalidState }
    }

    public func stop() async throws -> AudioRecordingSummary {
        guard let recorder else { throw AudioCaptureError.invalidState }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        return AudioRecordingSummary(duration: duration)
    }

    public func cancel() async {
        recorder?.stop()
        recorder = nil
    }

    public func meter() async -> AudioMeterSample {
        guard let recorder else { return .init(averagePower: -160, peakPower: -160) }
        recorder.updateMeters()
        return .init(averagePower: recorder.averagePower(forChannel: 0), peakPower: recorder.peakPower(forChannel: 0))
    }
}
#else
public actor SystemAudioRecorderAdapter: AudioRecorderAdapting {
    public init() {}
    public func start(at url: URL) async throws { throw AudioCaptureError.unsupportedPlatform }
    public func pause() async {}
    public func resume() async throws { throw AudioCaptureError.unsupportedPlatform }
    public func stop() async throws -> AudioRecordingSummary { throw AudioCaptureError.unsupportedPlatform }
    public func cancel() async {}
    public func meter() async -> AudioMeterSample { .init(averagePower: -160, peakPower: -160) }
}
#endif
