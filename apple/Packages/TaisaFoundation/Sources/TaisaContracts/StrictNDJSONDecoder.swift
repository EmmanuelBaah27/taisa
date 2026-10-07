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
    case eventAfterTerminal
    case missingTerminal
}

public struct StrictNDJSONDecoder<Event: StrictStreamEvent>: Sendable {
    private let maximumLineBytes: Int
    private var buffer = Data()
    private var requestID: UUID?
    private var expectedSequence = 0
    private var terminalReceived = false

    public init(maximumLineBytes: Int) {
        precondition(maximumLineBytes > 0)
        self.maximumLineBytes = maximumLineBytes
    }

    public mutating func append<Chunk: DataProtocol>(_ chunk: Chunk) throws -> [Event] {
        buffer.append(contentsOf: chunk)
        if buffer.count > maximumLineBytes && !buffer.contains(0x0A) {
            throw StrictNDJSONError.lineTooLarge
        }

        var events: [Event] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard line.count <= maximumLineBytes else { throw StrictNDJSONError.lineTooLarge }
            if line.isEmpty { continue }
            events.append(try accept(line))
        }
        return events
    }

    public mutating func finish() throws -> [Event] {
        var events: [Event] = []
        if !buffer.isEmpty {
            guard buffer.count <= maximumLineBytes else { throw StrictNDJSONError.lineTooLarge }
            events.append(try accept(buffer))
            buffer.removeAll(keepingCapacity: false)
        }
        guard terminalReceived else { throw StrictNDJSONError.missingTerminal }
        return events
    }

    private mutating func accept(_ line: Data) throws -> Event {
        guard String(data: line, encoding: .utf8) != nil else { throw StrictNDJSONError.invalidUTF8 }
        guard !terminalReceived else { throw StrictNDJSONError.eventAfterTerminal }
        let event: Event
        do { event = try JSONDecoder().decode(Event.self, from: line) }
        catch { throw StrictNDJSONError.malformedEvent }

        if let requestID, requestID != event.streamRequestID { throw StrictNDJSONError.requestMismatch }
        if event.streamSequence != expectedSequence {
            throw StrictNDJSONError.sequenceMismatch(expected: expectedSequence, actual: event.streamSequence)
        }
        requestID = event.streamRequestID
        expectedSequence += 1
        terminalReceived = event.isTerminalStreamEvent
        return event
    }
}
