import AVFoundation
import Observation
import OSLog
import UIKit

/// Ditado no iPhone: grava até você tocar em parar, transcreve, refina e copia o resultado.
///
/// O iOS não deixa colar em outro app nem ler a seleção dele, então a entrega é pela área de
/// transferência. Na revisão, o original é o texto do campo da tela, que recebe cada resultado.
@Observable
final class DictationModel {
    enum Phase: Equatable {
        case idle
        case recording
        case working(String)
        case finished(String)
        case failed(String)
    }

    private static let minimumAudioSeconds = 0.5
    static let maxSelectionCharacters = 15_000
    private static let projectKey = "ios.projectName"
    private static let revisionTextKey = "ios.revisionText"

    private(set) var phase: Phase = .idle
    var mode: DictationMode = .prompt
    /// Projeto do glossário escolhido na lista: no iPhone não há título de janela para reconhecê-lo.
    var projectName: String? {
        didSet { UserDefaults.standard.set(projectName, forKey: Self.projectKey) }
    }
    /// Texto a revisar, colado no campo da tela. Cada revisão o substitui pelo resultado, para revisar de novo.
    /// Fica salvo, para não se perder se o iOS encerrar o app enquanto você usa outro.
    var revisionText: String {
        didSet { UserDefaults.standard.set(revisionText, forKey: Self.revisionTextKey) }
    }
    private(set) var lastText: String?
    /// Início da gravação em andamento, para a contagem regressiva até o tempo máximo.
    private(set) var recordingStartedAt: Date?

    let settings: AppSettings
    let glossary: GlossaryStore
    let history: HistoryStore
    let transcriber: WhisperKitTranscriber
    private let refiner: PromptRefiner
    private let recorder = AudioRecorder()
    @ObservationIgnored private var maxDurationTask: Task<Void, Never>?

    init(settings: AppSettings, glossary: GlossaryStore, history: HistoryStore, transcriber: WhisperKitTranscriber,
         refiner: PromptRefiner) {
        self.settings = settings
        self.glossary = glossary
        self.history = history
        self.transcriber = transcriber
        self.refiner = refiner
        projectName = UserDefaults.standard.string(forKey: Self.projectKey)
        revisionText = UserDefaults.standard.string(forKey: Self.revisionTextKey) ?? ""
    }

    var level: Float { recorder.level }
    var isRecording: Bool { phase == .recording }
    var isWorking: Bool { if case .working = phase { true } else { false } }

    func toggle() {
        if isRecording { finish() } else { Task { await start() } }
    }

    func start(mode: DictationMode? = nil) async {
        guard !isRecording, !isWorking else { return }
        if let mode { self.mode = mode }
        if self.mode == .revision, revisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            phase = .failed("Cole no campo o texto a revisar e toque no microfone.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .failed("Libere o microfone em Ajustes → InfiniTypes para ditar.")
            return
        }
        do {
            try recorder.start()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        phase = .recording
        recordingStartedAt = .now
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(RecordingLimit.seconds))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func cancel() {
        guard isRecording else { return }
        maxDurationTask?.cancel()
        _ = recorder.stop()
        phase = .idle
    }

    func finish() {
        guard isRecording else { return }
        maxDurationTask?.cancel()
        let samples = recorder.stop()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let audioSeconds = Double(samples.count) / AudioRecorder.sampleRate
        guard audioSeconds >= Self.minimumAudioSeconds else {
            phase = .idle
            return
        }
        Task { await process(samples, audioSeconds: audioSeconds) }
    }

    // MARK: Processamento

    private func process(_ samples: [Float], audioSeconds: Double) async {
        let mode = self.mode
        // O projeto escolhido faz o papel do título da janela na escolha dos termos do glossário.
        let match = glossary.glossary.match(windowTitle: projectName)
        let context = DictationContext(projectName: match.projectName)

        phase = .working(transcriber.state == .ready ? "Transcrevendo…" : "Preparando o modelo de voz…")
        let start = ContinuousClock.now
        let text: String
        do {
            text = HallucinationFilter.clean(try await transcriber.transcribe(samples, vocabulary: match.terms))
        } catch {
            Logger.dictation.error("Falha na transcrição: \(error.localizedDescription, privacy: .public)")
            phase = .failed("Falha na transcrição: \(error.localizedDescription)")
            return
        }
        guard !text.isEmpty else {
            phase = .failed("Nada foi reconhecido")
            return
        }
        let transcriptionSeconds = (ContinuousClock.now - start).seconds

        if mode == .revision {
            await revise(text, context: context, vocabulary: match.terms, audioSeconds: audioSeconds,
                         transcriptionSeconds: transcriptionSeconds)
            return
        }

        phase = .working("\(mode == .literal ? "Limpando" : "Refinando") com \(settings.model.displayName)…")
        let refinementStart = ContinuousClock.now
        var result: RefinementResult?
        var refinementError: String?
        do {
            result = try await refiner.refine(transcript: text, context: context, mode: mode, vocabulary: match.terms)
        } catch {
            refinementError = error.localizedDescription
            Logger.dictation.error("Falha no refinamento: \(error.localizedDescription, privacy: .public)")
        }
        let delivered = result?.text ?? text
        save(DictationRecord(
            text: delivered, rawTranscript: text, context: context, mode: mode, modelID: settings.modelID,
            refined: result != nil, errorMessage: refinementError, audioSeconds: audioSeconds,
            transcriptionSeconds: transcriptionSeconds, refinementSeconds: (ContinuousClock.now - refinementStart).seconds,
            inputTokens: result?.inputTokens, outputTokens: result?.outputTokens
        ))
        deliver(delivered)
        phase = refinementError.map { .failed("Copiei o texto sem refinar. \($0)") }
            ?? .finished(mode == .literal ? "Texto copiado" : "Prompt copiado")
    }

    private func revise(_ dictation: String, context: DictationContext, vocabulary: [String], audioSeconds: Double,
                        transcriptionSeconds: Double) async {
        func record(text: String, original: String?, refined: Bool, error: String?, seconds: Double? = nil,
                    tokens: (Int?, Int?) = (nil, nil)) -> DictationRecord {
            DictationRecord(text: text, rawTranscript: dictation, context: context, mode: .revision, originalText: original,
                            modelID: settings.modelID, refined: refined, errorMessage: error, audioSeconds: audioSeconds,
                            transcriptionSeconds: transcriptionSeconds, refinementSeconds: seconds,
                            inputTokens: tokens.0, outputTokens: tokens.1)
        }

        // O campo fica bloqueado enquanto grava e revisa, então este é o texto que estava nele ao tocar no microfone.
        let original = revisionText
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            save(record(text: dictation, original: nil, refined: false, error: "Campo de revisão vazio"))
            phase = .failed("O campo de revisão está vazio. A fala ficou no histórico.")
            return
        }
        // Salvaguardas antes de mandar o texto do campo para a API.
        let secrets = SecretScanner.findings(in: original)
        guard secrets.isEmpty else {
            save(record(text: dictation, original: nil, refined: false,
                        error: "Texto não enviado: parece conter \(secrets.joined(separator: ", "))"))
            phase = .failed("Nada foi enviado: o texto do campo parece conter \(secrets.joined(separator: ", ")).")
            return
        }
        guard original.count <= Self.maxSelectionCharacters else {
            save(record(text: dictation, original: original, refined: false,
                        error: "Texto grande demais (\(original.count) caracteres)"))
            phase = .failed("Texto grande demais para revisar (\(original.count) caracteres; o limite é \(Self.maxSelectionCharacters)).")
            return
        }

        phase = .working("Revisando com \(settings.model.displayName)…")
        let start = ContinuousClock.now
        do {
            let result = try await refiner.revise(selection: original, dictation: dictation, context: context,
                                                  vocabulary: vocabulary)
            save(record(text: result.text, original: original, refined: true, error: nil,
                        seconds: (ContinuousClock.now - start).seconds, tokens: (result.inputTokens, result.outputTokens)))
            if result.editCount == 0 {
                phase = .finished("A fala não pediu alterações: o texto foi mantido")
                return
            }
            revisionText = result.text
            deliver(result.text)
            let detail = result.editCount.map { $0 == 1 ? " (1 alteração)" : " (\($0) alterações)" } ?? ""
            phase = .finished("Revisão pronta\(detail): o campo foi atualizado e o texto, copiado")
        } catch {
            save(record(text: dictation, original: original, refined: false, error: error.localizedDescription,
                        seconds: (ContinuousClock.now - start).seconds))
            phase = .failed("A revisão falhou e o texto do campo continua intacto. \(error.localizedDescription)")
        }
    }

    private func deliver(_ text: String) {
        UIPasteboard.general.string = text
        lastText = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func save(_ record: DictationRecord) {
        history.insert(record)
        Logger.dictation.notice("Ditado \(record.mode.rawValue, privacy: .public): áudio \(record.audioSeconds, format: .fixed(precision: 1), privacy: .public) s, transcrição \(record.transcriptionSeconds, format: .fixed(precision: 2), privacy: .public) s")
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
