import CryptoKit
import Foundation
import TaisaContracts
import TaisaStorage

public enum VoiceAssistantResponseWrite {
    public static func make(
        message: MessageRecord,
        response: CoachingResponse,
        receipt: String
    ) throws -> AssistantResponseWrite {
        let proposalData = try response.proposal.map { try JSONEncoder().encode($0) }
        let proposal = response.proposal.map { value in
            AssistantProposalRecord(
                id: derivedUUID(from: message.id, salt: 30),
                responseMessageID: message.id,
                kind: proposalKind(value),
                canonicalPayload: proposalData!,
                payloadDigest: SHA256.hash(data: proposalData!)
                    .map { String(format: "%02x", $0) }.joined(),
                state: .pending,
                targetType: nil,
                targetID: nil,
                targetVersionID: nil,
                decisionReceipt: nil,
                createdAtMS: message.createdAtMS,
                resolvedAtMS: nil
            )
        }
        return AssistantResponseWrite(
            message: message,
            metadata: .init(
                responseMessageID: message.id,
                requestID: response.requestId.uuidString.lowercased(),
                idempotencyReceipt: receipt,
                mode: AssistantResponseMode(rawValue: response.mode.rawValue)!,
                relevance: response.relevance.rawValue,
                contextSufficiency: response.contextSufficiency.rawValue,
                stance: response.stance?.rawValue,
                inference: response.explanation.inference,
                confidence: response.explanation.confidence.rawValue,
                approach: response.explanation.approach,
                createdAtMS: message.createdAtMS
            ),
            sources: response.explanation.evidence.enumerated().map { index, source in
                .init(
                    id: derivedUUID(from: message.id, salt: UInt8(index + 40)),
                    responseMessageID: message.id,
                    ordinal: index,
                    sourceID: source.sourceId,
                    sourceType: source.sourceType.rawValue,
                    excerpt: source.excerpt
                )
            },
            proposal: proposal
        )
    }

    private static func proposalKind(_ proposal: CoachingProposal) -> String {
        switch proposal {
        case .goal: "goal"
        case .action: "action"
        case .weeklyWork: "weekly_work"
        case .evidence: "evidence"
        case .memory: "memory"
        case .insight: "insight"
        }
    }

    private static func derivedUUID(from source: String, salt: UInt8) -> String {
        guard var uuid = UUID(uuidString: source)?.uuid else {
            return UUID().uuidString.lowercased()
        }
        uuid.15 ^= salt
        return UUID(uuid: uuid).uuidString.lowercased()
    }
}
