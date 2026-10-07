import TaisaStorage

/// One pure reducer result. The first effect is always the durable checkpoint
/// whenever a later effect can touch AVFoundation, disk, network, or UI policy.
public struct VoiceSessionTransition: Sendable, Equatable {
    public let next: VoiceTurnRecord
    public let effects: [VoiceSessionEffect]

    public init(next: VoiceTurnRecord, effects: [VoiceSessionEffect]) {
        self.next = next; self.effects = effects
    }
}
