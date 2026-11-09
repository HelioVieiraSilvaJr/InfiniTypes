package com.infinidim.infinitypes.ime

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.inputmethodservice.InputMethodService
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import com.infinidim.infinitypes.MainActivity
import com.infinidim.infinitypes.R
import com.infinidim.infinitypes.core.DictationContext
import com.infinidim.infinitypes.core.DictationMode
import com.infinidim.infinitypes.dictation.DictationSession
import com.infinidim.infinitypes.dictation.DictationState
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Teclado de voz: toque no microfone, fale e toque de novo. O resultado entra no campo em foco.
 * Na revisão, o texto selecionado no campo é o original, e a versão revisada o substitui.
 */
class InfiniTypesKeyboard : InputMethodService() {
    private val scope = MainScope()
    private lateinit var session: DictationSession
    private var mode = DictationMode.PROMPT
    private lateinit var status: TextView
    private lateinit var micButton: ImageButton
    private val modeButtons = mutableMapOf<DictationMode, TextView>()

    override fun onCreate() {
        super.onCreate()
        session = DictationSession(this, scope)
    }

    override fun onDestroy() {
        session.destroy()
        scope.cancel()
        super.onDestroy()
    }

    override fun onCreateInputView(): View {
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()
        val dark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val backgroundColor = if (dark) Color.rgb(0x1F, 0x1F, 0x23) else Color.rgb(0xEC, 0xEE, 0xF2)
        val foreground = if (dark) Color.WHITE else Color.rgb(0x1F, 0x1F, 0x23)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(backgroundColor)
            setPadding(dp(12), dp(10), dp(12), dp(10))
        }

        val modes = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER }
        for (each in DictationMode.entries) {
            val chip = TextView(this).apply {
                text = each.label
                textSize = 14f
                gravity = Gravity.CENTER
                setPadding(dp(14), dp(6), dp(14), dp(6))
                setOnClickListener { selectMode(each) }
            }
            modeButtons[each] = chip
            modes.addView(chip, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).apply { setMargins(dp(4), 0, dp(4), 0) })
        }
        root.addView(modes, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        micButton = ImageButton(this).apply {
            setImageResource(R.drawable.ic_mic)
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.rgb(0x2F, 0x6F, 0xF0)) }
            contentDescription = "Ditar"
            setOnClickListener { toggle() }
        }
        root.addView(micButton, LinearLayout.LayoutParams(dp(84), dp(84)).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            setMargins(0, dp(14), 0, dp(8))
        })

        status = TextView(this).apply {
            setTextColor(foreground)
            textSize = 14f
            gravity = Gravity.CENTER
            maxLines = 3
        }
        root.addView(status, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        val keys = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun key(label: String, description: String, action: () -> Unit) = TextView(this).apply {
            text = label
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(foreground)
            gravity = Gravity.CENTER
            contentDescription = description
            setPadding(0, dp(10), 0, dp(10))
            setOnClickListener { action() }
        }.also { keys.addView(it, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)) }
        key("🌐", "Trocar de teclado") { if (!switchToPreviousInputMethod()) showInputMethodPicker() }
        key("espaço", "Espaço") { currentInputConnection?.commitText(" ", 1) }
        key("⌫", "Apagar") { sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL) }
        key("enter", "Enter") { if (!sendDefaultEditorAction(true)) sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER) }
        root.addView(keys, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(8) })

        selectMode(mode)
        scope.launch { session.state.collect(::render) }
        return root
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        // Sem campo, não há onde entregar: a fala em andamento é descartada.
        if (session.isListening) session.cancel()
        super.onFinishInputView(finishingInput)
    }

    private fun showInputMethodPicker() {
        getSystemService(android.view.inputmethod.InputMethodManager::class.java).showInputMethodPicker()
    }

    private fun selectMode(selected: DictationMode) {
        if (session.isListening || session.isWorking) return
        mode = selected
        modeButtons.forEach { (each, chip) ->
            val active = each == selected
            chip.background = GradientDrawable().apply {
                cornerRadius = 100f
                setColor(if (active) Color.rgb(0x2F, 0x6F, 0xF0) else Color.TRANSPARENT)
            }
            chip.setTextColor(if (active) Color.WHITE else status.currentTextColor)
        }
        status.text = when (selected) {
            DictationMode.PROMPT -> "Toque no microfone e fale: sai um prompt organizado."
            DictationMode.LITERAL -> "Só limpa a fala, mantendo as suas palavras."
            DictationMode.REVISION -> "Selecione o texto no campo e dite o que mudar."
        }
    }

    private fun toggle() {
        when {
            session.isListening -> session.stop()
            session.isWorking -> Unit
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED -> {
                status.text = "Abra o app InfiniTypes para liberar o microfone."
                startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            else -> {
                val selection = currentInputConnection?.getSelectedText(0)?.toString()
                session.start(mode, selection, editorContext()) { text -> currentInputConnection?.commitText(text, 1) }
            }
        }
    }

    /** O app em que o campo está, para o refinamento acertar nomes. */
    private fun editorContext(): DictationContext {
        val packageName = currentInputEditorInfo?.packageName ?: return DictationContext.EMPTY
        val label = runCatching {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, 0)).toString()
        }.getOrNull()
        return DictationContext(appName = label ?: packageName, appId = packageName)
    }

    private fun render(state: DictationState) {
        val listening = state is DictationState.Listening
        micButton.setImageResource(if (listening) R.drawable.ic_stop else R.drawable.ic_mic)
        (micButton.background as? GradientDrawable)?.setColor(if (listening) Color.rgb(0xE5, 0x3E, 0x3E) else Color.rgb(0x2F, 0x6F, 0xF0))
        micButton.alpha = if (state is DictationState.Working) 0.5f else 1f
        micButton.imageTintList = ColorStateList.valueOf(Color.WHITE)
        when (state) {
            DictationState.Idle -> selectMode(mode)
            is DictationState.Listening -> status.text = state.partial.ifEmpty { "Ouvindo… toque para terminar" }
            is DictationState.Working -> status.text = state.message
            is DictationState.Finished -> status.text = state.message
            is DictationState.Failed -> status.text = state.message
        }
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        if (::status.isInitialized && !session.isListening && !session.isWorking) selectMode(mode)
    }
}
