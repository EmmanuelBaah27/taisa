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
        let prepared = recorder.prepareToRecord()
        print("TAISA_CAPTURE recorder.prepare result=\(prepared)")
        guard prepared else { throw AudioCaptureError.invalidState }
        let started = recorder.record()
        print("TAISA_CAPTURE recorder.start result=\(started) isRecording=\(recorder.isRecording)")
        guard started else { throw AudioCaptureError.invalidState }
        self.recorder = recorder
    }

    public func pause() async {
        print("TAISA_CAPTURE recorder.pause before=\(recorder?.isRecording == true)")
        recorder?.pause()
        print("TAISA_CAPTURE recorder.pause after=\(recorder?.isRecording == true)")
    }

    public func resume() async throws {
        let resumed = recorder?.record() == true
        print("TAISA_CAPTURE recorder.resume result=\(resumed) isRecording=\(recorder?.isRecording == true)")
        guard resumed else { throw AudioCaptureError.invalidState }
    }

    public func stop() async throws -> AudioRecordingSummary {
        guard let recorder else { throw AudioCaptureError.invalidState }
        let duration = recorder.currentTime
        print("TAISA_CAPTURE recorder.stop isRecording=\(recorder.isRecording) durationMS=\(Int(duration * 1_000))")
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
