import Foundation
import OSLog

/// Orquestra o ditado: grava → transcreve → refina (ou revisa a seleção) → salva no histórico → cola.
final class DictationCoordinator {
    private enum Phase {
        /// Atalho pressionado, esperando um instante antes de abrir o microfone.
        case arming
        case recording
        case processing
        case idle
    }

    private static let minimumAudioSeconds = 0.5
    private static let maximumAudioSeconds = 5.0 * 60
    /// Toques rápidos (ex.: ⌘C com o ⌘ direito) terminam antes disso e não abrem o microfone.
    private static let armingDelay: [DictationMode: Duration] = [.literal: .milliseconds(150)]
    /// O HUD só aparece depois disso, para atalhos cancelados não piscarem na tela.
    private static let hudDelay: Duration = .milliseconds(300)
    /// Limite do texto selecionado enviado à API na revisão.
    static let maxSelectionCharacters = 15_000

    private let permissions: PermissionsManager
    private let settings: AppSettings
    private let glossary: GlossaryStore
    private let transcriber: WhisperKitTranscriber
    private let refiner: PromptRefiner
    private let history: HistoryStore
    private let hud: HUDController
    private let recorder = AudioRecorder()

    var onNeedsPermissions: (() -> Void)?
    /// A gravação acabou (soltou, cancelou ou atingiu o tempo máximo), para o atalho sair do mãos-livres.
    var onRecordingEnded: (() -> Void)?

    private var phase: Phase = .idle
    private var mode: DictationMode = .prompt
    /// Gravando sem a tecla segurada: um toque no atalho termina.
    private var handsFree = false
    private var context: DictationContext = .empty
    /// Seleção lida pela Accessibility ao apertar o atalho. Na revisão é o texto a revisar; nos outros
    /// modos serve para avisar que o texto colado vai substituí-la.
    private var selection: SelectionReader.Result = .none
    private var recordingStartedAt: ContinuousClock.Instant?
    private var pendingTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?

    init(permissions: PermissionsManager, settings: AppSettings, glossary: GlossaryStore,
         transcriber: WhisperKitTranscriber, refiner: PromptRefiner, history: HistoryStore, hud: HUDController) {
        self.permissions = permissions
        self.settings = settings
        self.glossary = glossary
        self.transcriber = transcriber
        self.refiner = refiner
        self.history = history
        self.hud = hud
    }

    // MARK: Gravação

    func startRecording(mode: DictationMode, handsFree: Bool = false) {
        guard phase == .idle else {
            if handsFree { onRecordingEnded?() }
            return
        }
        self.mode = mode
        self.handsFree = handsFree
        context = ContextCollector.capture()
        selection = SelectionReader.accessibilitySelection()
        if mode == .revision, selection == .secureField {
            hud.show(.failure("Campo de senha: a revisão por voz não lê esse conteúdo"))
            return
        }

        let delay = Self.armingDelay[mode] ?? .zero
        guard delay > .zero else {
            beginCapture()
            return
        }
        phase = .arming
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, phase == .arming else { return }
            beginCapture()
        }
    }

    func cancelRecording() {
        switch phase {
        case .arming:
            pendingTask?.cancel()
            phase = .idle
        case .recording:
            let wasVisible = hudIsVisible
            stopTasks()
            _ = recorder.stop()
            phase = .idle
            onRecordingEnded?()
            if wasVisible { hud.show(.notice("Ditado cancelado")) } else { hud.hide() }
        case .processing, .idle:
            break
        }
    }

    func finishRecording() {
        switch phase {
        case .arming:
            // Foi só um toque na tecla.
            pendingTask?.cancel()
            phase = .idle
        case .recording:
            stopTasks()
            let samples = recorder.stop()
            onRecordingEnded?()
            let audioSeconds = Double(samples.count) / AudioRecorder.sampleRate
            guard audioSeconds >= Self.minimumAudioSeconds else {
                phase = .idle
                hud.hide()
                return
            }
            phase = .processing
            let (mode, context, selection) = (self.mode, self.context, self.selection)
            // Se a Accessibility não mostrou a seleção, um ⌘C a revela: sempre na revisão, e nos outros
            // modos só nos apps em que isso é seguro. Roda junto com a transcrição, agora que o atalho
            // já foi solto.
            // A espera longa fica escondida atrás da transcrição, que leva cerca de um segundo. Ela também evita
            // que uma cópia tardia do app sobrescreva a área de transferência depois de restaurada.
            let needsCopy = selection == .none && (mode == .revision || FocusDetector.frontmostHidesSelection)
            let copiedSelection = needsCopy ? Task { await SelectionReader.copySelection(timeout: .milliseconds(1500)) } : nil
            Task {
                await process(samples: samples, audioSeconds: audioSeconds, mode: mode, context: context,
                              selection: selection, copiedSelection: copiedSelection)
                phase = .idle
            }
        case .processing, .idle:
            break
        }
    }

    private func beginCapture() {
        permissions.refresh()
        guard permissions.allGranted else {
            phase = .idle
            onRecordingEnded?()
            hud.show(.failure("Conceda as permissões de Microfone e Acessibilidade"))
            onNeedsPermissions?()
            return
        }
        do {
            try recorder.start()
        } catch {
            phase = .idle
            onRecordingEnded?()
            hud.show(.failure(error.localizedDescription))
            return
        }
        phase = .recording
        recordingStartedAt = .now

        let modeLabel = switch (mode, selection) {
        case (.revision, .text(let text)): "Ouvindo (revisão de \(text.wordCount) palavras)…"
        case (.revision, _): "Ouvindo (revisão da seleção)…"
        case (.literal, .text): "Ouvindo (literal; vai substituir a seleção)…"
        case (.literal, _): "Ouvindo (literal)…"
        case (.prompt, .text): "Ouvindo (prompt novo; vai substituir a seleção)…"
        case (.prompt, _): "Ouvindo…"
        }
        let label = handsFree ? "Mãos livres: toque no ⌘ direito para terminar (Esc cancela)…" : modeLabel
        // Na revisão e no mãos-livres o gesto é intencional: o aviso aparece na hora, confirmando o modo.
        let hudDelay = mode == .revision || handsFree ? .zero : Self.hudDelay
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: hudDelay)
            guard !Task.isCancelled, let self, phase == .recording else { return }
            hud.show(.recording(label)) { [recorder] in recorder.level }
        }
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maximumAudioSeconds))
            guard !Task.isCancelled else { return }
            self?.finishRecording()
        }
    }

    private var hudIsVisible: Bool {
        guard let recordingStartedAt else { return false }
        return mode == .revision || handsFree || ContinuousClock.now - recordingStartedAt >= Self.hudDelay
    }

    private func stopTasks() {
        pendingTask?.cancel()
        maxDurationTask?.cancel()
    }

    // MARK: Processamento

    private struct Transcription {
        let text: String
        let seconds: Double
        let audioSeconds: Double
        let vocabulary: [String]
        let context: DictationContext
    }

    private func process(samples: [Float], audioSeconds: Double, mode: DictationMode, context: DictationContext,
                         selection: SelectionReader.Result, copiedSelection: Task<SelectionReader.Result, Never>?) async {
        let match = glossary.glossary.match(windowTitle: context.windowTitle)
        var context = context
        context.projectName = match.projectName

        hud.show(.working(transcriber.state == .ready ? "Transcrevendo…" : "Carregando o modelo de voz…"))
        let start = ContinuousClock.now
        let text: String
        do {
            text = HallucinationFilter.clean(try await transcriber.transcribe(samples, vocabulary: match.terms))
        } catch {
            Logger.dictation.error("Falha na transcrição: \(error.localizedDescription, privacy: .public)")
            hud.show(.failure("Falha na transcrição: \(error.localizedDescription)"))
            return
        }
        guard !text.isEmpty else {
            hud.show(.notice("Nada foi reconhecido"))
            return
        }
        let transcription = Transcription(text: text, seconds: (ContinuousClock.now - start).seconds,
                                          audioSeconds: audioSeconds, vocabulary: match.terms, context: context)

        var selection = selection
        if selection == .none, let copiedSelection {
            selection = await copiedSelection.value
        }

        guard mode == .revision else {
            await refineAndPaste(transcription, mode: mode, replacesSelection: selection != .none)
            return
        }
        guard case .text(let original) = selection else {
            // Você pediu revisão: colar um prompt novo poderia apagar uma seleção que o app só não
            // conseguiu ler. Nada é colado, e a fala fica no histórico.
            Logger.dictation.notice("Revisão sem texto selecionado legível; nada foi colado")
            save(transcription, mode: .revision, text: transcription.text, refined: false,
                 error: "Não foi possível ler o texto selecionado")
            hud.show(.failure("Não consegui ler o texto selecionado, então não alterei nada. A fala ficou no histórico."))
            return
        }
        await revise(original, with: transcription)
    }

    private func refineAndPaste(_ transcription: Transcription, mode: DictationMode, replacesSelection: Bool) async {
        // Se o refinamento falhar, o ditado segue com a transcrição bruta: nada se perde.
        let model = settings.model
        let action = mode == .literal ? "Limpando" : "Refinando"
        let warning = replacesSelection ? " (o resultado vai substituir o texto selecionado)" : ""
        hud.show(.working("\(action) com \(model.displayName)…\(warning)"))
        let start = ContinuousClock.now
        var result: RefinementResult?
        var refinementError: String?
        do {
            result = try await refiner.refine(transcript: transcription.text, context: transcription.context,
                                              mode: mode, vocabulary: transcription.vocabulary)
        } catch {
            refinementError = error.localizedDescription
            Logger.dictation.error("Falha no refinamento: \(error.localizedDescription, privacy: .public)")
        }

        // Salva antes de tentar colar.
        let record = save(transcription, mode: mode, text: result?.text ?? transcription.text,
                          refined: result != nil, error: refinementError,
                          refinementSeconds: (ContinuousClock.now - start).seconds,
                          tokens: (result?.inputTokens, result?.outputTokens))

        guard FocusDetector.check() != .notEditable else {
            hud.show(.notice("Salvo no histórico: nenhum campo de texto em foco"))
            return
        }
        await TextInserter.paste(record.text)
        record.pasted = true
        history.save()

        if let refinementError {
            hud.show(.failure("Não entre em pânico: colei o texto sem refinar. \(refinementError)"))
        } else if replacesSelection {
            hud.show(.notice("Colado no lugar do texto selecionado: ⌘Z desfaz. Para revisar uma seleção, toque e segure o ⌥ direito."))
        } else {
            hud.show(.success(mode == .literal ? "Texto colado" : "Prompt colado"))
        }
    }

    private func revise(_ original: String, with transcription: Transcription) async {
        // Salvaguardas antes de mandar o texto selecionado para a API.
        let secrets = SecretScanner.findings(in: original)
        guard secrets.isEmpty else {
            // O texto com o segredo não vai para o histórico; só a fala.
            save(transcription, mode: .revision, text: transcription.text, refined: false,
                 error: "Seleção não enviada: parece conter \(secrets.joined(separator: ", "))")
            hud.show(.failure("Nada foi enviado: a seleção parece conter \(secrets.joined(separator: ", ")). A fala ficou no histórico."))
            return
        }
        guard original.count <= Self.maxSelectionCharacters else {
            save(transcription, mode: .revision, text: transcription.text, original: original, refined: false,
                 error: "Seleção grande demais (\(original.count) caracteres)")
            hud.show(.failure("Seleção grande demais para revisar (\(original.count) caracteres; o limite é \(Self.maxSelectionCharacters)). A fala ficou no histórico."))
            return
        }

        let model = settings.model
        hud.show(.working("Revisando “\(original.preview)” com \(model.displayName)…"))
        let start = ContinuousClock.now
        let result: RevisionResult
        do {
            result = try await refiner.revise(selection: original, dictation: transcription.text,
                                              context: transcription.context, vocabulary: transcription.vocabulary)
        } catch {
            Logger.dictation.error("Falha na revisão: \(error.localizedDescription, privacy: .public)")
            save(transcription, mode: .revision, text: transcription.text, original: original, refined: false,
                 error: error.localizedDescription, refinementSeconds: (ContinuousClock.now - start).seconds)
            hud.show(.failure("Não entre em pânico: a revisão falhou e seu texto continua intacto. \(error.localizedDescription)"))
            return
        }

        let record = save(transcription, mode: .revision, text: result.text, original: original, refined: true,
                          error: nil, refinementSeconds: (ContinuousClock.now - start).seconds,
                          tokens: (result.inputTokens, result.outputTokens))
        Logger.dictation.notice("Revisão: \(result.editCount.map { "\($0) alterações" } ?? "texto reescrito", privacy: .public), \(original.count, privacy: .public) → \(result.text.count, privacy: .public) caracteres")

        if result.editCount == 0 {
            hud.show(.notice("A fala não pediu alterações: o texto foi mantido"))
            return
        }
        if FocusDetector.frontmostIsTerminal {
            // No terminal, colar não substitui a seleção: acrescentaria o texto no cursor.
            TextInserter.copy(result.text)
            hud.show(.notice("Revisão copiada: apague o texto antigo no terminal e cole com ⌘V"))
            return
        }
        guard FocusDetector.check() != .notEditable else {
            hud.show(.notice("Revisão salva no histórico: nenhum campo de texto em foco"))
            return
        }
        await TextInserter.paste(result.text)
        record.pasted = true
        history.save()

        // Na reescrita completa, um texto bem mais curto sugere que algo se perdeu.
        if result.editCount == nil, Double(result.text.count) < Double(original.count) * 0.7 {
            hud.show(.failure("Revisão colada, mas ficou bem mais curta que o original. Confira: ⌘Z desfaz, e o original está no histórico."))
        } else {
            let detail = result.editCount.map { $0 == 1 ? " (1 alteração)" : " (\($0) alterações)" } ?? ""
            hud.show(.success("Revisão colada\(detail)"))
        }
    }

    @discardableResult
    private func save(_ transcription: Transcription, mode: DictationMode, text: String, original: String? = nil,
                      refined: Bool, error: String?, refinementSeconds: Double? = nil,
                      tokens: (input: Int?, output: Int?) = (nil, nil)) -> DictationRecord {
        let record = DictationRecord(
            text: text, rawTranscript: transcription.text, context: transcription.context, mode: mode,
            originalText: original, modelID: settings.modelID, refined: refined, errorMessage: error,
            audioSeconds: transcription.audioSeconds, transcriptionSeconds: transcription.seconds,
            refinementSeconds: refinementSeconds, inputTokens: tokens.input, outputTokens: tokens.output
        )
        history.insert(record)
        Logger.dictation.notice("""
            Ditado \(mode.rawValue, privacy: .public): áudio \(transcription.audioSeconds, format: .fixed(precision: 1), privacy: .public) s, \
            transcrição \(transcription.seconds, format: .fixed(precision: 2), privacy: .public) s, \
            refinamento \(refinementSeconds ?? 0, format: .fixed(precision: 2), privacy: .public) s \
            (\(self.settings.modelID, privacy: .public), tokens \(tokens.input ?? 0, privacy: .public)/\(tokens.output ?? 0, privacy: .public), \
            glossário \(transcription.vocabulary.count, privacy: .public) termos, projeto \(transcription.context.projectName ?? "-", privacy: .public))
            """)
        return record
    }

    #if DEBUG
    /// Com `-transcribeFile <caminho>` (e `-literal YES` para o modo literal), transcreve e refina
    /// um arquivo de áudio usando o contexto e o glossário da janela em foco, sem colar nem salvar.
    /// Com `-reviseFile <caminho>`, o texto desse arquivo faz o papel da seleção; com `-glossaryFile <caminho>`,
    /// um glossário em JSON substitui o do usuário.
    func debugProcessFile(at path: String, mode: DictationMode, selectionFile: String?, glossary override: Glossary?) async {
        do {
            var context = ContextCollector.capture()
            let match = (override ?? glossary.glossary).match(windowTitle: context.windowTitle)
            context.projectName = match.projectName
            let start = ContinuousClock.now
            let transcript = HallucinationFilter.clean(try await transcriber.transcribe(fileAt: path, vocabulary: match.terms))
            Logger.dictation.notice("[debug] transcrição (\((ContinuousClock.now - start).seconds, format: .fixed(precision: 2), privacy: .public) s, glossário \(match.terms.count, privacy: .public) termos): \(transcript, privacy: .public)")
            let refinementStart = ContinuousClock.now
            if let selectionFile {
                let original = try String(contentsOfFile: selectionFile, encoding: .utf8)
                let result = try await refiner.revise(selection: original, dictation: transcript, context: context,
                                                      vocabulary: match.terms)
                Logger.dictation.notice("[debug] revisão (\((ContinuousClock.now - refinementStart).seconds, format: .fixed(precision: 2), privacy: .public) s, \(result.editCount.map { "\($0) alterações" } ?? "reescrita", privacy: .public), tokens \(result.inputTokens, privacy: .public)/\(result.outputTokens, privacy: .public)):\n\(result.text, privacy: .public)")
            } else {
                let result = try await refiner.refine(transcript: transcript, context: context, mode: mode, vocabulary: match.terms)
                Logger.dictation.notice("[debug] \(mode.rawValue, privacy: .public) (\((ContinuousClock.now - refinementStart).seconds, format: .fixed(precision: 2), privacy: .public) s, \(result.modelID, privacy: .public)): \(result.text, privacy: .public)")
            }
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

private extension String {
    var wordCount: Int {
        split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Começo do texto, para o HUD mostrar o que foi capturado.
    var preview: String {
        let flat = split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return flat.count > 40 ? flat.prefix(40) + "…" : flat
    }
}
