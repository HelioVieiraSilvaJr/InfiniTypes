protocol Transcriber {
    /// Transcreve áudio em 16 kHz mono Float32.
    func transcribe(_ samples: [Float]) async throws -> String
}
