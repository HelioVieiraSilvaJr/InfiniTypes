package com.infinidim.infinitypes.dictation

import android.content.Context
import android.util.Log
import com.infinidim.infinitypes.InfiniTypesApplication
import com.infinidim.infinitypes.core.DictationContext
import com.infinidim.infinitypes.core.DictationMode
import com.infinidim.infinitypes.core.DictationRecord
import com.infinidim.infinitypes.core.HallucinationFilter
import com.infinidim.infinitypes.core.ModelCatalog
import com.infinidim.infinitypes.core.RecordingLimit
import com.infinidim.infinitypes.core.RefinementResult
import com.infinidim.infinitypes.core.SecretScanner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed interface DictationState {
    data object Idle : DictationState
    /** @param remaining tempo que falta para a gravação terminar sozinha, como "9:59". */
    data class Listening(
        val partial: String,
        val level: Float,
        val remaining: String = RecordingLimit.remainingLabel(0),
    ) : DictationState
    data class Working(val message: String) : DictationState
    /** @param delivered se o texto foi entregue; não é quando a revisão não pediu alterações. */
    data class Finished(val message: String, val delivered: Boolean = true) : DictationState
    data class Failed(val message: String) : DictationState
}

/**
 * Um ditado: ouve até você tocar em parar, refina (ou revisa o texto original) e entrega o resultado.
 * O teclado entrega no campo; o bloco das Configurações Rápidas e o app copiam para a área de transferência.
 */
class DictationSession(private val context: Context, private val scope: CoroutineScope) {
    private val services = (context.applicationContext as InfiniTypesApplication).services
    private val _state = MutableStateFlow<DictationState>(DictationState.Idle)
    val state: StateFlow<DictationState> = _state

    private var transcriber: SpeechTranscriber? = null
    private var mode = DictationMode.PROMPT
    private var original: String? = null
    private var dictationContext = DictationContext.EMPTY
    private var vocabulary: List<String> = emptyList()
    private var startedAt = 0L
    private var countdown: Job? = null
    private var deliver: (String) -> Unit = {}

    val isListening: Boolean get() = _state.value is DictationState.Listening
    val isWorking: Boolean get() = _state.value is DictationState.Working

    /**
     * @param original na revisão, o texto a revisar (a seleção no teclado, o copiado nos outros casos).
     * @param deliver recebe o texto final, uma única vez.
     */
    fun start(mode: DictationMode, original: String?, appContext: DictationContext, deliver: (String) -> Unit) {
        if (isListening || isWorking) return
        if (mode == DictationMode.REVISION && original.isNullOrBlank()) {
            _state.value = DictationState.Failed("Para revisar, selecione o texto (no teclado) ou cole-o no campo de revisão (no app).")
            return
        }
        val match = services.glossary.glossary.value.match(services.settings.projectName)
        this.mode = mode
        this.original = original
        this.deliver = deliver
        dictationContext = appContext.copy(projectName = match.projectName)
        vocabulary = match.terms
        val transcriber = transcriber ?: SpeechTranscriber(context, services.settings.allowNetworkRecognition, listener)
            .also { transcriber = it }
        transcriber.unavailableReason()?.let {
            _state.value = DictationState.Failed(it)
            return
        }
        startedAt = System.currentTimeMillis()
        _state.value = DictationState.Listening("", 0f)
        transcriber.start(vocabulary)
        startCountdown()
    }

    /** Atualiza o tempo restante e, ao chegar no limite, termina a gravação como se você tocasse em parar. */
    private fun startCountdown() {
        countdown?.cancel()
        countdown = scope.launch {
            while (true) {
                val listening = _state.value as? DictationState.Listening ?: break
                val elapsed = System.currentTimeMillis() - startedAt
                _state.value = listening.copy(remaining = RecordingLimit.remainingLabel(elapsed))
                if (elapsed >= RecordingLimit.DURATION_MILLIS) {
                    stop()
                    break
                }
                delay(250)
            }
        }
    }

    fun stop() {
        if (isListening) transcriber?.finish()
    }

    fun cancel() {
        countdown?.cancel()
        transcriber?.cancel()
        _state.value = DictationState.Idle
    }

    fun destroy() {
        countdown?.cancel()
        transcriber?.destroy()
        transcriber = null
    }

    private val listener = object : SpeechTranscriber.Listener {
        override fun onPartial(text: String) {
            (_state.value as? DictationState.Listening)?.let { _state.value = it.copy(partial = text) }
        }

        override fun onLevel(level: Float) {
            (_state.value as? DictationState.Listening)?.let { _state.value = it.copy(level = level) }
        }

        override fun onFinished(text: String) {
            val audioSeconds = (System.currentTimeMillis() - startedAt) / 1000.0
            scope.launch { process(HallucinationFilter.clean(text), audioSeconds) }
        }

        override fun onError(message: String) {
            _state.value = DictationState.Failed(message)
        }
    }

    private suspend fun process(text: String, audioSeconds: Double) {
        if (text.isEmpty()) {
            _state.value = DictationState.Failed("Nada foi reconhecido")
            return
        }
        if (mode == DictationMode.REVISION) {
            revise(text, original.orEmpty(), audioSeconds)
            return
        }

        val model = ModelCatalog.model(services.settings.modelId)
        _state.value = DictationState.Working("${if (mode == DictationMode.LITERAL) "Limpando" else "Refinando"} com ${model.displayName}…")
        val start = System.currentTimeMillis()
        // Se o refinamento falhar, o ditado segue com a transcrição bruta: nada se perde.
        var result: RefinementResult? = null
        var refinementError: String? = null
        try {
            result = withContext(Dispatchers.IO) { services.refiner.refine(text, dictationContext, mode, vocabulary) }
        } catch (error: Exception) {
            refinementError = error.message
            Log.e(TAG, "Falha no refinamento: ${error.javaClass.simpleName}")
        }
        val delivered = result?.text ?: text
        save(record(text, delivered, refined = result != null, error = refinementError, audioSeconds = audioSeconds,
            refinementSeconds = seconds(start), tokens = result?.inputTokens to result?.outputTokens))
        deliver(delivered)
        _state.value = refinementError?.let { DictationState.Failed("Entreguei o texto sem refinar. $it") }
            ?: DictationState.Finished(if (mode == DictationMode.LITERAL) "Texto pronto" else "Prompt pronto")
    }

    private suspend fun revise(dictation: String, original: String, audioSeconds: Double) {
        // Salvaguardas antes de mandar o texto original para a API.
        val secrets = SecretScanner.findings(original)
        if (secrets.isNotEmpty()) {
            val found = secrets.joinToString(", ")
            save(record(dictation, dictation, refined = false, error = "Texto não enviado: parece conter $found", audioSeconds = audioSeconds))
            _state.value = DictationState.Failed("Nada foi enviado: o texto parece conter $found. A fala ficou no histórico.")
            return
        }
        if (original.length > MAX_SELECTION_CHARACTERS) {
            save(record(dictation, dictation, original = original, refined = false,
                error = "Texto grande demais (${original.length} caracteres)", audioSeconds = audioSeconds))
            _state.value = DictationState.Failed("Texto grande demais para revisar (${original.length} caracteres; o limite é $MAX_SELECTION_CHARACTERS).")
            return
        }

        val model = ModelCatalog.model(services.settings.modelId)
        _state.value = DictationState.Working("Revisando com ${model.displayName}…")
        val start = System.currentTimeMillis()
        try {
            val result = withContext(Dispatchers.IO) { services.refiner.revise(original, dictation, dictationContext, vocabulary) }
            save(record(dictation, result.text, original = original, refined = true, audioSeconds = audioSeconds,
                refinementSeconds = seconds(start), tokens = result.inputTokens to result.outputTokens))
            if (result.editCount == 0) {
                _state.value = DictationState.Finished("A fala não pediu alterações: o texto foi mantido", delivered = false)
                return
            }
            deliver(result.text)
            val detail = result.editCount?.let { if (it == 1) " (1 alteração)" else " ($it alterações)" }.orEmpty()
            _state.value = DictationState.Finished("Revisão pronta$detail")
        } catch (error: Exception) {
            save(record(dictation, dictation, original = original, refined = false, error = error.message,
                audioSeconds = audioSeconds, refinementSeconds = seconds(start)))
            _state.value = DictationState.Failed("A revisão falhou e o texto original continua intacto. ${error.message.orEmpty()}")
        }
    }

    private fun record(
        transcript: String,
        delivered: String,
        original: String? = null,
        refined: Boolean,
        error: String? = null,
        audioSeconds: Double,
        refinementSeconds: Double? = null,
        tokens: Pair<Int?, Int?> = null to null,
    ) = DictationRecord(
        text = delivered,
        rawTranscript = transcript,
        appName = dictationContext.appName,
        appId = dictationContext.appId,
        projectName = dictationContext.projectName,
        mode = mode,
        originalText = original,
        modelId = services.settings.modelId,
        refined = refined,
        errorMessage = error,
        audioSeconds = audioSeconds,
        // O reconhecimento do Android acontece durante a fala; não há etapa separada de transcrição.
        transcriptionSeconds = 0.0,
        refinementSeconds = refinementSeconds,
        inputTokens = tokens.first,
        outputTokens = tokens.second,
    )

    private suspend fun save(record: DictationRecord) {
        withContext(Dispatchers.IO) { services.history.insert(record) }
        Log.i(TAG, "Ditado ${record.mode.rawValue}: áudio ${"%.1f".format(record.audioSeconds)} s, refinado ${record.refined}")
    }

    private fun seconds(since: Long) = (System.currentTimeMillis() - since) / 1000.0

    companion object {
        private const val TAG = "InfiniTypes"

        /** Limite do texto enviado à API na revisão. */
        const val MAX_SELECTION_CHARACTERS = 15_000
    }
}
