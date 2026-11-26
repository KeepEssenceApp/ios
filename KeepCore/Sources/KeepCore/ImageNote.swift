import Foundation

/// What the share sheet says about a picture beyond the core's sentence, when what was saved is not what was
/// shared (QA #87). Said as it is, and only as far as it is true:
///   - `instead`: the picture was not saved, and a link or the text was (the save is that, not a picture);
///   - `after`: the picture was saved with a loss (an animation kept as one still picture).
/// A save that happened says it; a save that waits in the queue says it after the queued sentence; a save that was
/// already there, or that did not happen, keeps the plain sentence, which is then the true one.
public struct ImageNote: Equatable, Sendable {
    public var instead: String?
    public var after: String?

    public init(instead: String? = nil, after: String? = nil) {
        self.instead = instead
        self.after = after
    }

    public func apply(to outcome: SaveOutcome) -> SaveOutcome {
        switch outcome.kind {
        case .saved:
            if let instead { return SaveOutcome(kind: .saved, sentence: instead) }
            if let after { return SaveOutcome(kind: .saved, sentence: "\(outcome.sentence) \(after)") }
        case .queued:
            if let say = instead ?? after { return SaveOutcome(kind: .queued, sentence: "\(outcome.sentence) \(say)") }
        case .duplicate, .failed:
            break
        }
        return outcome
    }
}

extension ImageNote {
    /// A size limit in whole MiB (1,048,576 bytes), the unit it really is in: 3,145,728 bytes is 3 MiB, not 3 MB
    /// (which is 3,000,000). Rounded down, because the sentence it goes in says "over N": that stays true of every
    /// picture that is refused, and a limit that is not a whole number of MiB is never named as a larger one.
    public static func mebibytes(_ bytes: Int) -> Int { max(0, bytes) / 1_048_576 }
}
