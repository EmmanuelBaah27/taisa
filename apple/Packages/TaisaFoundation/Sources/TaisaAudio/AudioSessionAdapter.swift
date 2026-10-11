import Foundation

public protocol AudioSessionAdapting: Sendable {
    func requestRecordPermission() async -> Bool
    func activate() async throws
    func deactivate() async
}

public protocol AudioSessionLifecycleObserving: Sendable {
    func events() -> AsyncStream<AudioCaptureLifecycleEvent>
}

public struct AudioSessionNotificationMapper: Sendable {
    public let interruption: Notification.Name
    public let routeChange: Notification.Name
    public let mediaServicesReset: Notification.Name
    public let interruptionTypeKey: String
    public let routeChangeReasonKey: String
    public let interruptionBeganValue: UInt
    public let oldDeviceUnavailableValue: UInt

    public init(
        interruption: Notification.Name,
        routeChange: Notification.Name,
        mediaServicesReset: Notification.Name,
        interruptionTypeKey: String,
        routeChangeReasonKey: String,
        interruptionBeganValue: UInt,
        oldDeviceUnavailableValue: UInt
    ) {
        self.interruption = interruption
        self.routeChange = routeChange
        self.mediaServicesReset = mediaServicesReset
        self.interruptionTypeKey = interruptionTypeKey
        self.routeChangeReasonKey = routeChangeReasonKey
        self.interruptionBeganValue = interruptionBeganValue
        self.oldDeviceUnavailableValue = oldDeviceUnavailableValue
    }

    public func event(for notification: Notification) -> AudioCaptureLifecycleEvent? {
        switch notification.name {
        case interruption:
            guard let value = (notification.userInfo?[interruptionTypeKey] as? NSNumber)?.uintValue else {
                return nil
            }
            return value == interruptionBeganValue ? .interruptionBegan : .interruptionEnded
        case routeChange:
            guard let value = (notification.userInfo?[routeChangeReasonKey] as? NSNumber)?.uintValue,
                  value == oldDeviceUnavailableValue else { return nil }
            return .routeLost
        case mediaServicesReset:
            return .mediaServicesReset
        default:
            return nil
        }
    }
}

private final class AudioSessionObserverTokens: @unchecked Sendable {
    private let center: NotificationCenter
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter) { self.center = center }

    func append(_ token: NSObjectProtocol) {
        lock.lock()
        tokens.append(token)
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let current = tokens
        tokens.removeAll()
        lock.unlock()
        for token in current { center.removeObserver(token) }
    }
}

#if os(iOS)
import AVFoundation
import UIKit

public actor SystemAudioSessionAdapter: AudioSessionAdapting {
    public static let captureCategory: AVAudioSession.Category = .playAndRecord
    public static let captureMode: AVAudioSession.Mode = .voiceChat

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
        try session.setCategory(
            Self.captureCategory,
            mode: Self.captureMode,
            options: [.allowBluetoothHFP]
        )
        try session.setActive(true)
    }

    public func deactivate() async {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

public struct SystemAudioSessionLifecycleSource: AudioSessionLifecycleObserving {
    private let center: NotificationCenter

    public init(center: NotificationCenter = .default) { self.center = center }

    public func events() -> AsyncStream<AudioCaptureLifecycleEvent> {
        let mapper = AudioSessionNotificationMapper(
            interruption: AVAudioSession.interruptionNotification,
            routeChange: AVAudioSession.routeChangeNotification,
            mediaServicesReset: AVAudioSession.mediaServicesWereResetNotification,
            interruptionTypeKey: AVAudioSessionInterruptionTypeKey,
            routeChangeReasonKey: AVAudioSessionRouteChangeReasonKey,
            interruptionBeganValue: AVAudioSession.InterruptionType.began.rawValue,
            oldDeviceUnavailableValue: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        )
        return AsyncStream { continuation in
            let names = [
                mapper.interruption, mapper.routeChange, mapper.mediaServicesReset,
                UIApplication.didEnterBackgroundNotification,
            ]
            let tokens = AudioSessionObserverTokens(center: center)
            for name in names {
                let token = center.addObserver(forName: name, object: nil, queue: nil) { notification in
                    if notification.name == UIApplication.didEnterBackgroundNotification {
                        continuation.yield(.appBackgrounded)
                    } else if let event = mapper.event(for: notification) {
                        continuation.yield(event)
                    }
                }
                tokens.append(token)
            }
            continuation.onTermination = { @Sendable _ in
                tokens.cancel()
            }
        }
    }
}
#else
public actor SystemAudioSessionAdapter: AudioSessionAdapting {
    public init() {}
    public func requestRecordPermission() async -> Bool { false }
    public func activate() async throws { throw AudioCaptureError.unsupportedPlatform }
    public func deactivate() async {}
}

public struct SystemAudioSessionLifecycleSource: AudioSessionLifecycleObserving {
    public init(center: NotificationCenter = .default) {}
    public func events() -> AsyncStream<AudioCaptureLifecycleEvent> {
        AsyncStream { $0.finish() }
    }
}
#endif
