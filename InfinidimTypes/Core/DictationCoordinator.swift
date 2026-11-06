import Foundation
import OSLog

/// Orquestra o ditado: grava → transcreve → refina → salva no histórico → cola.
final class DictationCoordinator {
    private enum Phase {
        case idle, recording, processing
    }

    private static let minimumAudioSeconds = 0.5
    private static let maximumAudioSeconds = 5.0 * 60

    private let permissions: PermissionsManager
    private let settings: AppSettings
    private let transcriber: WhisperKitTranscriber
    private let refiner: PromptRefiner
    private let history: HistoryStore
    private let hud: HUDController
    private let recorder = AudioRecorder()

    var onNeedsPermissions: (() -> Void)?

    private var phase: Phase = .idle
    private var context: DictationContext = .empty
    private var maxDurationTask: Task<Void, Never>?

    init(permissions: PermissionsManager, settings: AppSettings, transcriber: WhisperKitTranscriber,
         refiner: PromptRefiner, history: HistoryStore, hud: HUDController) {
        self.permissions = permissions
        self.settings = settings
        self.transcriber = transcriber
        self.refiner = refiner
        self.history = history
        self.hud = hud
    }

    // MARK: Gravação

    func startRecording() {
        guard phase == .idle else { return }
        permissions.refresh()
        guard permissions.allGranted else {
            hud.show(.failure("Conceda as permissões de Microfone e Acessibilidade"))
            onNeedsPermissions?()
            return
        }

        context = ContextCollector.capture()
        do {
            try recorder.start()
        } catch {
            hud.show(.failure(error.localizedDescription))
            return
        }
        phase = .recording
        hud.show(.recording) { [recorder] in recorder.level }

        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maximumAudioSeconds))
            guard !Task.isCancelled else { return }
            self?.finishRecording()
        }
    }

    func cancelRecording() {
        guard phase == .recording else { return }
        maxDurationTask?.cancel()
        _ = recorder.stop()
        phase = .idle
        hud.show(.notice("Ditado cancelado"))
    }

    func finishRecording() {
        guard phase == .recording else { return }
        maxDurationTask?.cancel()
        let samples = recorder.stop()
        let audioSeconds = Double(samples.count) / AudioRecorder.sampleRate
        guard audioSeconds >= Self.minimumAudioSeconds else {
            phase = .idle
            hud.hide()
            return
        }

        phase = .processing
        let context = self.context
        Task {
            await process(samples: samples, audioSeconds: audioSeconds, context: context)
            phase = .idle
        }
    }

    // MARK: Processamento

    private func process(samples: [Float], audioSeconds: Double, context: DictationContext) async {
        hud.show(.working(transcriber.state == .ready ? "Transcrevendo…" : "Carregando o modelo de voz…"))
        let clock = ContinuousClock()
        let transcriptionStart = clock.now
        let transcript: String
        do {
            transcript = HallucinationFilter.clean(try await transcriber.transcribe(samples))
        } catch {
            Logger.dictation.error("Falha na transcrição: \(error.localizedDescription, privacy: .public)")
            hud.show(.failure("Falha na transcrição: \(error.localizedDescription)"))
            return
        }
        let transcriptionSeconds = (clock.now - transcriptionStart).seconds
        guard !transcript.isEmpty else {
            hud.show(.notice("Nada foi reconhecido"))
            return
        }

        // Se o refinamento falhar, o ditado segue com a transcrição bruta: nada se perde.
        let model = settings.model
        hud.show(.working("Refinando com \(model.displayName)…"))
        let refinementStart = clock.now
        var result: RefinementResult?
        var refinementError: String?
        do {
            result = try await refiner.refine(transcript: transcript, context: context)
        } catch {
            refinementError = error.localizedDescription
            Logger.dictation.error("Falha no refinamento: \(error.localizedDescription, privacy: .public)")
        }
        let refinementSeconds = (clock.now - refinementStart).seconds

        let record = DictationRecord(
            text: result?.text ?? transcript, rawTranscript: transcript, context: context,
            modelID: model.id, refined: result != nil, errorMessage: refinementError,
            audioSeconds: audioSeconds, transcriptionSeconds: transcriptionSeconds,
            refinementSeconds: refinementSeconds,
            inputTokens: result?.inputTokens, outputTokens: result?.outputTokens
        )
        // Salva antes de tentar colar.
        history.insert(record)
        Logger.dictation.notice("""
            Ditado: áudio \(audioSeconds, format: .fixed(precision: 1), privacy: .public) s, \
            transcrição \(transcriptionSeconds, format: .fixed(precision: 2), privacy: .public) s, \
            refinamento \(refinementSeconds, format: .fixed(precision: 2), privacy: .public) s \
            (\(model.id, privacy: .public), tokens \(result?.inputTokens ?? 0, privacy: .public)/\(result?.outputTokens ?? 0, privacy: .public))
            """)

        guard FocusDetector.check() != .notEditable else {
            hud.show(.notice("Salvo no histórico: nenhum campo de texto em foco"))
            return
        }
        await TextInserter.paste(record.text)
        record.pasted = true
        history.save()

        if let refinementError {
            hud.show(.failure("Não entre em pânico: colei o texto sem refinar. \(refinementError)"))
        } else {
            hud.show(.success("Prompt colado"))
        }
    }

    #if DEBUG
    /// Com `-transcribeFile <caminho>`, transcreve e refina um arquivo de áudio, sem colar nem salvar.
    func debugProcessFile(at path: String) async {
        do {
            let clock = ContinuousClock()
            let start = clock.now
            let transcript = HallucinationFilter.clean(try await transcriber.transcribe(fileAt: path))
            Logger.dictation.notice("[debug] transcrição (\((clock.now - start).seconds, format: .fixed(precision: 2), privacy: .public) s): \(transcript, privacy: .public)")
            let refinementStart = clock.now
            let result = try await refiner.refine(transcript: transcript, context: ContextCollector.capture())
            Logger.dictation.notice("[debug] prompt (\((clock.now - refinementStart).seconds, format: .fixed(precision: 2), privacy: .public) s, \(result.modelID, privacy: .public)): \(result.text, privacy: .public)")
        } catch {
            Logger.dictation.error("[debug] falha: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
