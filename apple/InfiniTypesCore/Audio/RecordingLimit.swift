import Foundation

/// Tempo máximo de uma gravação e a contagem regressiva mostrada enquanto ela dura.
nonisolated enum RecordingLimit {
    /// Tempo para desenvolver uma ideia longa. Ao chegar nele, a gravação termina e o ditado segue normalmente.
    static let seconds: TimeInterval = 10 * 60

    /// Tempo restante como "10:00", "9:59", …, "0:00". Arredonda para cima, para começar no limite cheio.
    static func remainingLabel(since start: Date, now: Date = .now) -> String {
        let remaining = max(0, Int((seconds - now.timeIntervalSince(start)).rounded(.up)))
        return "\(remaining / 60):" + String(format: "%02d", remaining % 60)
    }
}
