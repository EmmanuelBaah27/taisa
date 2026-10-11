import CryptoKit
import Foundation

public protocol StrictStreamEvent: Decodable, Sendable {
    var streamRequestID: UUID { get }
    var streamSequence: Int { get }
    var isTerminalStreamEvent: Bool { get }
}

public enum StrictNDJSONError: Error, Equatable, Sendable {
    case lineTooLarge
    case invalidUTF8
    case malformedEvent
    case requestMismatch
    case sequenceMismatch(expected: Int, actual: Int)
    case conflictingDuplicate(sequence: Int)
    case eventAfterTerminal
    case missingTerminal
}

public struct StrictNDJSONDecoder<Event: StrictStreamEvent>: Sendable {
    private let maximumLineBytes: Int
    private var buffer = Data()
    private var requestID: UUID?
    private var expectedSequence = 0
    private var terminalReceived = false
    private var acceptedLineDigests: [Int: Data] = [:]

    public init(maximumLineBytes: Int) {
        precondition(maximumLineBytes > 0)
        self.maximumLineBytes = maximumLineBytes
    }

    public mutating func append<Chunk: DataProtocol>(_ chunk: Chunk) throws -> [Event] {
        var events: [Event] = []
        for byte in chunk {
            if byte == 0x0A {
                if !buffer.isEmpty, let event = try accept(buffer) { events.append(event) }
                buffer.removeAll(keepingCapacity: true)
            } else {
                guard buffer.count < maximumLineBytes else { throw StrictNDJSONError.lineTooLarge }
                buffer.append(byte)
            }
        }
        return events
    }

    public mutating func finish() throws -> [Event] {
        var events: [Event] = []
        if !buffer.isEmpty {
            guard buffer.count <= maximumLineBytes else { throw StrictNDJSONError.lineTooLarge }
            if let event = try accept(buffer) { events.append(event) }
            buffer.removeAll(keepingCapacity: false)
        }
        guard terminalReceived else { throw StrictNDJSONError.missingTerminal }
        return events
    }

    private mutating func accept(_ line: Data) throws -> Event? {
        guard String(data: line, encoding: .utf8) != nil else { throw StrictNDJSONError.invalidUTF8 }
        let event: Event
        do { event = try JSONDecoder().decode(Event.self, from: line) }
        catch { throw StrictNDJSONError.malformedEvent }

        if let requestID, requestID != event.streamRequestID { throw StrictNDJSONError.requestMismatch }
        if event.streamSequence < expectedSequence {
            let digest = Data(SHA256.hash(data: line))
            guard acceptedLineDigests[event.streamSequence] == digest else {
                throw StrictNDJSONError.conflictingDuplicate(sequence: event.streamSequence)
            }
            return nil
        }
        guard !terminalReceived else { throw StrictNDJSONError.eventAfterTerminal }
        if event.streamSequence != expectedSequence {
            throw StrictNDJSONError.sequenceMismatch(expected: expectedSequence, actual: event.streamSequence)
        }
        requestID = event.streamRequestID
        acceptedLineDigests[event.streamSequence] = Data(SHA256.hash(data: line))
        expectedSequence += 1
        terminalReceived = event.isTerminalStreamEvent
        return event
    }
}
