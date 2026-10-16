public enum SeniorSelfSyncClassification: String, Sendable, Equatable {
    case encryptedSync
    case localOnly

    public static func classify(_ entityType: String) -> Self? {
        switch entityType {
        case "assistant_response_metadata", "assistant_response_source", "assistant_proposal":
            .encryptedSync
        case "response_feedback", "preference_profile":
            .localOnly
        default:
            nil
        }
    }
}
