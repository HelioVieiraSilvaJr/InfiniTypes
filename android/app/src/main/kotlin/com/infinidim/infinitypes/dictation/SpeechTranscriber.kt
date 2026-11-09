package com.infinidim.infinitypes.dictation

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * Reconhecimento de voz do Android, de preferência no próprio aparelho.
 *
 * O reconhecedor encerra sozinho depois de uma pausa; enquanto você não toca em parar, ele recomeça
 * e os trechos são juntados, para uma fala longa, com pausas para pensar, sair inteira.
 */
class SpeechTranscriber(
    private val context: Context,
    private val allowNetwork: Boolean,
    private val listener: Listener,
) {
    interface Listener {
        fun onPartial(text: String)
        fun onLevel(level: Float)
        fun onFinished(text: String)
        fun onError(message: String)
    }

    private val onDevice = SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
    private var recognizer: SpeechRecognizer? = null
    private val segments = mutableListOf<String>()
    private var vocabulary: List<String> = emptyList()
    private var active = false
    private var stopping = false

    /** `null` se dá para gravar; senão, o motivo. */
    fun unavailableReason(): String? = when {
        onDevice -> null
        allowNetwork && SpeechRecognizer.isRecognitionAvailable(context) -> null
        else -> "Este aparelho não tem reconhecimento de voz offline. Instale o pacote de português nas configurações " +
            "de voz do Google ou permita o reconhecimento pela rede nos Ajustes do InfiniTypes."
    }

    fun start(vocabulary: List<String>) {
        this.vocabulary = vocabulary
        segments.clear()
        active = true
        stopping = false
        val recognizer = recognizer ?: (if (onDevice) SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            else SpeechRecognizer.createSpeechRecognizer(context)).also {
            it.setRecognitionListener(recognitionListener)
            recognizer = it
        }
        recognizer.startListening(intent())
    }

    /** Termina a fala: o último trecho chega em `onResults` e o texto completo vai para `onFinished`. */
    fun finish() {
        if (!active) return
        stopping = true
        recognizer?.stopListening()
    }

    fun cancel() {
        active = false
        stopping = false
        recognizer?.cancel()
    }

    fun destroy() {
        cancel()
        recognizer?.destroy()
        recognizer = null
    }

    private fun intent() = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        // Fixo em português: com muitos termos técnicos, a detecção automática tende a trocar para inglês.
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, "pt-BR")
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        // O glossário puxa o reconhecimento para essas grafias.
        if (vocabulary.isNotEmpty()) putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(vocabulary.take(100)))
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 4_000L)
    }

    private fun deliver() {
        active = false
        stopping = false
        listener.onFinished(segments.joinToString(" ").trim())
    }

    private fun restart() {
        recognizer?.startListening(intent())
    }

    private val recognitionListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit

        override fun onRmsChanged(rmsdB: Float) {
            // O RMS vem mais ou menos entre -2 e 10 dB.
            listener.onLevel(((rmsdB + 2f) / 12f).coerceIn(0f, 1f))
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val partial = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
            listener.onPartial((segments + partial).joinToString(" ").trim())
        }

        override fun onResults(results: Bundle?) {
            if (!active) return
            results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                ?.takeIf { it.isNotBlank() }?.let { segments += it.trim() }
            if (stopping) deliver() else restart()
        }

        override fun onError(error: Int) {
            if (!active) return
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                    if (stopping) deliver() else restart()
                SpeechRecognizer.ERROR_CLIENT -> if (stopping) deliver()
                SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> {
                    active = false
                    downloadPortuguese()
                    listener.onError("Baixando o reconhecimento de voz em português para o aparelho. Tente de novo em instantes.")
                }
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                    active = false
                    listener.onError("Libere o microfone para o InfiniTypes nas configurações do Android.")
                }
                SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER -> {
                    active = false
                    listener.onError("O reconhecimento de voz precisou da rede e falhou. Confira a conexão.")
                }
                else -> {
                    active = false
                    listener.onError("O reconhecimento de voz falhou (código $error).")
                }
            }
        }
    }

    private fun downloadPortuguese() {
        if (onDevice) recognizer?.triggerModelDownload(intent())
    }
}
