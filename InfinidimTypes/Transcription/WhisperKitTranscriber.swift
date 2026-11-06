import Foundation
import Observation
import OSLog
import WhisperKit

// O WhisperKit é usado só por este transcritor, uma transcrição por vez.
extension WhisperKit: @retroactive @unchecked Sendable {}

/// Transcrição local com o Whisper large-v3-turbo via Core ML.
@Observable
final class WhisperKitTranscriber: Transcriber {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    static let modelVariant = "openai_whisper-large-v3-v20240930_turbo_632MB"
    private static let modelRepo = "argmaxinc/whisperkit-coreml"
    private static let requiredModels = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]

    private(set) var state: State = .idle

    @ObservationIgnored private var pipe: WhisperKit?
    @ObservationIgnored private var loadTask: Task<WhisperKit, Error>?

    private var modelsDirectory: URL { AppPaths.support.appending(path: "Models", directoryHint: .isDirectory) }

    /// Baixa (só na primeira vez) e carrega o modelo em segundo plano.
    func prepare() {
        guard pipe == nil, loadTask == nil else { return }
        loadTask = Task { try await load() }
    }

    func transcribe(_ samples: [Float], vocabulary: [String]) async throws -> String {
        let pipe = try await readyPipe()
        let options = Self.decodingOptions(vocabulary: vocabulary, tokenizer: pipe.tokenizer)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return Self.joined(results)
    }

    /// Transcreve um arquivo de áudio em qualquer formato que o AVFoundation leia.
    func transcribe(fileAt path: String, vocabulary: [String]) async throws -> String {
        let pipe = try await readyPipe()
        let options = Self.decodingOptions(vocabulary: vocabulary, tokenizer: pipe.tokenizer)
        let results = try await pipe.transcribe(audioPath: path, decodeOptions: options)
        return Self.joined(results)
    }

    private static func decodingOptions(vocabulary: [String], tokenizer: (any WhisperTokenizer)?) -> DecodingOptions {
        var options = DecodingOptions(
            task: .transcribe,
            // Fixo em português: a detecção automática tende a trocar para inglês com muitos termos técnicos.
            language: "pt",
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad
        )
        options.promptTokens = promptTokens(for: vocabulary, tokenizer: tokenizer)
        return options
    }

    /// O glossário vira o "texto anterior" do Whisper, o que puxa o reconhecimento para essas grafias.
    /// O contexto do modelo aceita ~224 tokens; o glossário usa no máximo 150.
    private static func promptTokens(for vocabulary: [String], tokenizer: (any WhisperTokenizer)?) -> [Int]? {
        guard let tokenizer, !vocabulary.isEmpty else { return nil }
        let text = " " + vocabulary.joined(separator: ", ") + "."
        let tokens = tokenizer.encode(text: text).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return Array(tokens.prefix(150))
    }

    private static func joined(_ results: [TranscriptionResult]) -> String {
        results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readyPipe() async throws -> WhisperKit {
        if let pipe { return pipe }
        prepare()
        guard let loadTask else { throw CancellationError() }
        let pipe = try await loadTask.value
        self.pipe = pipe
        return pipe
    }

    private func load() async throws -> WhisperKit {
        do {
            let folder = if let local = localModelFolder() { local } else { try await download() }
            state = .loading
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                tokenizerFolder: modelsDirectory,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
            let pipe = try await WhisperKit(config)
            Logger.transcription.notice("Modelo de voz pronto: \(Self.modelVariant, privacy: .public)")
            state = .ready
            self.pipe = pipe
            return pipe
        } catch {
            Logger.transcription.error("Falha ao preparar o modelo de voz: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            loadTask = nil
            throw error
        }
    }

    private func localModelFolder() -> URL? {
        let folder = modelsDirectory.appending(path: "models/\(Self.modelRepo)/\(Self.modelVariant)", directoryHint: .isDirectory)
        let complete = Self.requiredModels.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
        return complete ? folder : nil
    }

    private func download() async throws -> URL {
        state = .downloading(0)
        Logger.transcription.notice("Baixando o modelo de voz \(Self.modelVariant, privacy: .public)")
        return try await WhisperKit.download(
            variant: Self.modelVariant,
            downloadBase: modelsDirectory,
            from: Self.modelRepo
        ) { [weak self] progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in self?.state = .downloading(fraction) }
        }
    }
}
