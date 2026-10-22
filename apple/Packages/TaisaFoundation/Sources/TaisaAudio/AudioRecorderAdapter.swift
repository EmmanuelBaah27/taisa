import Foundation

public protocol AudioRecorderAdapting: Sendable {
    func start(at url: URL) async throws
    func pause() async
    func resume() async throws
    func stop() async throws -> AudioRecordingSummary
    func cancel() async
    func meter() async -> AudioMeterSample
    func elapsedTime() async -> TimeInterval
    func hasRecordedAudio() async -> Bool
    func frequencyBands() async -> VoiceFrequencyBands
}

public extension AudioRecorderAdapting {
    func frequencyBands() async -> VoiceFrequencyBands { .zero }
}

#if canImport(AVFoundation)
@preconcurrency import AVFoundation

public actor SystemAudioRecorderAdapter: AudioRecorderAdapting {
    private var engine: AVAudioEngine?
    private var pipeline: AudioPCMProcessingPipeline?

    public init() {}

    public func start(at url: URL) async throws {
        guard engine == nil else { throw AudioCaptureError.invalidState }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0,
              hardwareFormat.channelCount > 0,
              let recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: hardwareFormat.sampleRate,
                channels: 1,
                interleaved: false
              ) else {
            throw AudioCaptureError.invalidState
        }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: recordingFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let pipeline = try AudioPCMProcessingPipeline(
            file: file,
            sourceFormat: hardwareFormat,
            recordingFormat: recordingFormat
        )
        input.installTap(onBus: 0, bufferSize: 1_024, format: hardwareFormat) { buffer, _ in
            pipeline.enqueue(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        pipeline.setCapturing(true)
        self.engine = engine
        self.pipeline = pipeline
    }

    public func pause() async {
        pipeline?.setCapturing(false)
        engine?.pause()
    }

    public func resume() async throws {
        guard let engine, let pipeline else { throw AudioCaptureError.invalidState }
        try engine.start()
        pipeline.setCapturing(true)
    }

    public func stop() async throws -> AudioRecordingSummary {
        guard let engine, let pipeline else { throw AudioCaptureError.invalidState }
        pipeline.setCapturing(false)
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        defer {
            self.engine = nil
            self.pipeline = nil
        }
        let duration = try pipeline.finish()
        return AudioRecordingSummary(duration: duration)
    }

    public func cancel() async {
        pipeline?.setCapturing(false)
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        pipeline?.cancel()
        engine = nil
        pipeline = nil
    }

    public func meter() async -> AudioMeterSample {
        pipeline?.meter ?? .init(averagePower: -160, peakPower: -160)
    }

    public func elapsedTime() async -> TimeInterval { pipeline?.duration ?? 0 }
    public func hasRecordedAudio() async -> Bool { pipeline?.hasAudio ?? false }
    public func frequencyBands() async -> VoiceFrequencyBands { pipeline?.frequencyBands ?? .zero }
}

private final class AudioPCMProcessingPipeline: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.taisa.audio.capture-pcm", qos: .userInitiated)
    private let lock = NSLock()
    private let file: AVAudioFile
    private let recordingFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let sampleRate: Double
    private var analyzer = VoiceSpectrumAnalyzer()
    private var isCapturing = false
    private var queuedBuffers = 0
    private var writtenFrames: AVAudioFramePosition = 0
    private var latestMeter = AudioMeterSample(averagePower: -160, peakPower: -160)
    private var latestBands = VoiceFrequencyBands.zero
    private var writeFailed = false

    init(file: AVAudioFile, sourceFormat: AVAudioFormat, recordingFormat: AVAudioFormat) throws {
        self.file = file
        self.recordingFormat = recordingFormat
        sampleRate = recordingFormat.sampleRate
        if sourceFormat == recordingFormat {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: sourceFormat, to: recordingFormat) else {
                throw AudioCaptureError.invalidState
            }
            self.converter = converter
        }
    }

    func setCapturing(_ value: Bool) {
        lock.withLock { isCapturing = value }
    }

    func enqueue(_ source: AVAudioPCMBuffer) {
        let shouldCopy = lock.withLock { () -> Bool in
            guard isCapturing else { return false }
            guard queuedBuffers < 32 else {
                writeFailed = true
                return false
            }
            queuedBuffers += 1
            return true
        }
        guard shouldCopy else { return }
        guard let copy = Self.copy(source) else {
            lock.withLock {
                queuedBuffers -= 1
                writeFailed = true
            }
            return
        }
        queue.async { [self] in
            defer { lock.withLock { queuedBuffers -= 1 } }
            process(copy)
        }
    }

    var meter: AudioMeterSample { lock.withLock { latestMeter } }
    var frequencyBands: VoiceFrequencyBands { lock.withLock { latestBands } }
    var duration: TimeInterval { lock.withLock { Double(writtenFrames) / sampleRate } }
    var hasAudio: Bool { lock.withLock { writtenFrames > 0 } }

    func finish() throws -> TimeInterval {
        queue.sync {}
        let result = lock.withLock { (writeFailed, Double(writtenFrames) / sampleRate) }
        guard !result.0 else { throw AudioCaptureError.invalidState }
        return result.1
    }

    func cancel() {
        queue.sync {}
        lock.withLock {
            latestMeter = .init(averagePower: -160, peakPower: -160)
            latestBands = .zero
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        let recordingBuffer: AVAudioPCMBuffer
        do {
            recordingBuffer = try convertedBuffer(from: buffer)
        } catch {
            lock.withLock { writeFailed = true }
            return
        }
        do {
            try file.write(from: recordingBuffer)
        } catch {
            lock.withLock { writeFailed = true }
            return
        }
        let frames = Int(recordingBuffer.frameLength)
        guard frames > 0, let channels = recordingBuffer.floatChannelData else { return }
        var samples = [Float](repeating: 0, count: frames)
        let channelCount = Int(recordingBuffer.format.channelCount)
        for channel in 0..<channelCount {
            for frame in 0..<frames { samples[frame] += channels[channel][frame] / Float(channelCount) }
        }
        let squares = samples.reduce(0.0) { $0 + Double($1 * $1) }
        let rms = sqrt(squares / Double(frames))
        let peak = samples.reduce(0.0) { max($0, abs(Double($1))) }
        let meter = AudioMeterSample(
            averagePower: Float(max(20 * log10(max(rms, 1e-8)), -160)),
            peakPower: Float(max(20 * log10(max(peak, 1e-8)), -160))
        )
        let bands = analyzer.analyze(
            samples: samples,
            sampleRate: sampleRate,
            delta: .seconds(Double(frames) / sampleRate)
        )
        lock.withLock {
            writtenFrames += AVAudioFramePosition(recordingBuffer.frameLength)
            latestMeter = meter
            latestBands = bands
        }
    }

    private func convertedBuffer(from source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter else { return source }
        let ratio = recordingFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio)) + 1
        guard let destination = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: capacity) else {
            throw AudioCaptureError.invalidState
        }
        let inputState = AudioConverterInputState()
        var conversionError: NSError?
        let status = converter.convert(to: destination, error: &conversionError) { _, inputStatus in
            if inputState.supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputState.supplied = true
            inputStatus.pointee = .haveData
            return source
        }
        if let conversionError { throw conversionError }
        guard status == .haveData || status == .inputRanDry else {
            throw AudioCaptureError.invalidState
        }
        return destination
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let destination = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameLength
        ) else { return nil }
        destination.frameLength = source.frameLength
        guard let sourceChannels = source.floatChannelData,
              let destinationChannels = destination.floatChannelData else { return nil }
        let byteCount = Int(source.frameLength) * MemoryLayout<Float>.size
        for channel in 0..<Int(source.format.channelCount) {
            memcpy(destinationChannels[channel], sourceChannels[channel], byteCount)
        }
        return destination
    }
}

private final class AudioConverterInputState: @unchecked Sendable {
    var supplied = false
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
    public func elapsedTime() async -> TimeInterval { 0 }
    public func hasRecordedAudio() async -> Bool { false }
    public func frequencyBands() async -> VoiceFrequencyBands { .zero }
}
#endif
