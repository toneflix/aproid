import Foundation

public enum PairState: Sendable {
    case notPaired, requested, requestedByPeer, paired
}

/// What the caller should do after the state machine handles an event.
public enum PairAction: Equatable, Sendable {
    case none
    case send(NetworkPacket)
    /// Ask the user to accept or reject the peer's request.
    case askUser
    case paired
    case unpaired
}

/// Pairing for one peer, following KDE Connect protocol v8. Mirrors the Kotlin
/// PairingStateMachine so both apps behave the same. Time is passed in for testing.
/// With `allowed` false, this side never asks to pair and refuses every request.
public final class PairingStateMachine {
    public private(set) var state: PairState
    /// Unix time in seconds of the last pair request. Both sides use it for the verification code.
    public private(set) var requestTimestamp: Int64 = 0
    private var requestedAt: Int64 = 0
    private let timeoutSeconds: Int64
    private let maxClockSkewSeconds: Int64
    private let allowed: Bool

    public init(state: PairState = .notPaired, timeoutSeconds: Int64 = 30, maxClockSkewSeconds: Int64 = 1800, allowed: Bool = true) {
        self.state = allowed ? state : .notPaired
        self.timeoutSeconds = timeoutSeconds
        self.maxClockSkewSeconds = maxClockSkewSeconds
        self.allowed = allowed
    }

    public func requestPair(now: Int64) -> PairAction {
        guard allowed else { return .none }

        switch state {
        case .paired, .requested: return .none
        case .requestedByPeer: return accept()
        case .notPaired:
            state = .requested
            requestedAt = now
            requestTimestamp = now
            return .send(Self.pairPacket(true, timestamp: now))
        }
    }

    public func accept() -> PairAction {
        guard state == .requestedByPeer else { return .none }
        state = .paired
        return .send(Self.pairPacket(true, timestamp: nil))
    }

    public func reject() -> PairAction {
        guard state == .requestedByPeer else { return .none }
        state = .notPaired
        return .send(Self.pairPacket(false, timestamp: nil))
    }

    public func unpair() -> PairAction {
        guard state != .notPaired else { return .none }
        state = .notPaired
        return .send(Self.pairPacket(false, timestamp: nil))
    }

    /// Call regularly. Drops a request that nobody answered.
    public func tick(now: Int64) -> PairAction {
        if state == .requested && now - requestedAt > timeoutSeconds {
            state = .notPaired
            return .unpaired
        }
        return .none
    }

    public func handle(_ packet: NetworkPacket, now: Int64) -> PairAction {
        guard packet.type == PacketType.pair, let wantsPair = packet.bool("pair") else { return .none }
        if !wantsPair {
            let was = state
            state = .notPaired
            return was == .notPaired ? .none : .unpaired
        }
        switch state {
        case .requested:
            state = .paired
            return .paired
        case .notPaired:
            guard allowed, let ts = packet.int("timestamp"), abs(now - ts) <= maxClockSkewSeconds else {
                // Not allowed, or a missing or stale timestamp: refuse, as protocol v8 requires.
                return .send(Self.pairPacket(false, timestamp: nil))
            }
            state = .requestedByPeer
            requestTimestamp = ts
            return .askUser
        case .requestedByPeer:
            return .none
        case .paired:
            return .send(Self.pairPacket(true, timestamp: nil))
        }
    }

    private static func pairPacket(_ pair: Bool, timestamp: Int64?) -> NetworkPacket {
        var body: [String: JSONValue] = ["pair": .bool(pair)]
        if let timestamp { body["timestamp"] = .int(timestamp) }
        return NetworkPacket(type: PacketType.pair, body: body)
    }
}
