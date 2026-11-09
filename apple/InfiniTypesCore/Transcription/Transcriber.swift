protocol Transcriber {
    /// Transcreve áudio em 16 kHz mono Float32. `vocabulary` traz termos com a grafia correta.
    func transcribe(_ samples: [Float], vocabulary: [String]) async throws -> String
}
