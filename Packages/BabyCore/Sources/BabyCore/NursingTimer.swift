import Foundation

/// Left/right breastfeeding timer logic. Accumulated time lives in
/// `leftDuration`/`rightDuration`; the running side is `activeSide` and has been
/// running since `activeSideStartedAt`.
extension EventRecord {
    public var isNursingPaused: Bool { kind == .nursing && isOngoing && activeSide == nil }

    public func nursingElapsed(_ side: BreastSide, at now: Date = Date()) -> TimeInterval {
        let stored = side == .left ? leftDuration : rightDuration
        guard activeSide == side, let since = activeSideStartedAt else { return stored }
        return stored + max(0, now.timeIntervalSince(since))
    }

    public func nursingTotal(at now: Date = Date()) -> TimeInterval {
        nursingElapsed(.left, at: now) + nursingElapsed(.right, at: now)
    }

    /// Starts (or resumes) timing `side`, banking any time on the other side first.
    public mutating func startNursing(_ side: BreastSide, at now: Date = Date()) {
        if activeSide == side { return }
        pauseNursing(at: now)
        activeSide = side
        activeSideStartedAt = now
        lastSide = side
        endDate = nil
        updatedAt = now
    }

    public mutating func pauseNursing(at now: Date = Date()) {
        guard let side = activeSide, let since = activeSideStartedAt else {
            activeSide = nil
            activeSideStartedAt = nil
            return
        }
        let elapsed = max(0, now.timeIntervalSince(since))
        switch side {
        case .left: leftDuration += elapsed
        case .right: rightDuration += elapsed
        }
        activeSide = nil
        activeSideStartedAt = nil
        updatedAt = now
    }

    public mutating func switchNursingSide(at now: Date = Date()) {
        let next = (activeSide ?? lastSide ?? .right).other
        startNursing(next, at: now)
    }

    /// Stops the timer and closes the session.
    public mutating func finishNursing(at now: Date = Date()) {
        if let side = activeSide { lastSide = side }
        pauseNursing(at: now)
        endDate = now
        updatedAt = now
    }

    /// The side the next feed should start on: the opposite of the last side used.
    public static func suggestedNextSide(after lastNursing: EventRecord?) -> BreastSide {
        guard let last = lastNursing?.lastSide ?? lastNursing?.activeSide else { return .left }
        return last.other
    }
}
