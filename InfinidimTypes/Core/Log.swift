import OSLog

extension Logger {
    private static let subsystem = "com.infinidim.InfinidimTypes"

    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let dictation = Logger(subsystem: subsystem, category: "dictation")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let history = Logger(subsystem: subsystem, category: "history")
}
