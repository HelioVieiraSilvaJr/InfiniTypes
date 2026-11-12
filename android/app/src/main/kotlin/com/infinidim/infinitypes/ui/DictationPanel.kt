package com.infinidim.infinitypes.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.infinidim.infinitypes.InfiniTypesApplication
import com.infinidim.infinitypes.clipboardText
import com.infinidim.infinitypes.copyToClipboard
import com.infinidim.infinitypes.core.DictationContext
import com.infinidim.infinitypes.core.DictationMode
import com.infinidim.infinitypes.dictation.DictationSession
import com.infinidim.infinitypes.dictation.DictationState

/**
 * Ditado com entrega pela área de transferência, usado na aba Ditar e no bloco das Configurações Rápidas.
 * Na revisão, o original é o texto do campo da tela, que recebe cada resultado para uma nova revisão.
 */
@Composable
fun DictationPanel(session: DictationSession, autoStart: Boolean = false, onDelivered: (String) -> Unit = {}) {
    val context = LocalContext.current
    val focus = LocalFocusManager.current
    val settings = remember { (context.applicationContext as InfiniTypesApplication).services.settings }
    val state by session.state.collectAsState()
    var mode by rememberSaveable { mutableStateOf(DictationMode.PROMPT) }
    var started by rememberSaveable { mutableStateOf(false) }
    var permissionDenied by remember { mutableStateOf(false) }
    var revisionText by remember { mutableStateOf(settings.revisionText) }

    fun updateRevisionText(text: String) {
        revisionText = text
        settings.revisionText = text
    }

    fun begin() {
        val revising = mode == DictationMode.REVISION
        session.start(mode, if (revising) revisionText else null, DictationContext.EMPTY) { text ->
            if (revising) updateRevisionText(text)
            context.copyToClipboard(text)
            onDelivered(text)
        }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        permissionDenied = !granted
        if (granted) begin()
    }

    fun toggle() {
        focus.clearFocus()
        when {
            session.isListening -> session.stop()
            session.isWorking -> Unit
            // Com o campo vazio, a sessão só avisa que falta o texto: não há por que pedir o microfone antes.
            mode == DictationMode.REVISION && revisionText.isBlank() -> begin()
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED ->
                permission.launch(Manifest.permission.RECORD_AUDIO)
            else -> begin()
        }
    }

    if (autoStart && !started) {
        started = true
        toggle()
    }

    Column(
        Modifier.verticalScroll(rememberScrollState()).imePadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            DictationMode.entries.forEachIndexed { index, each ->
                SegmentedButton(
                    selected = mode == each,
                    onClick = { if (!session.isListening && !session.isWorking) mode = each },
                    shape = SegmentedButtonDefaults.itemShape(index, DictationMode.entries.size),
                ) { Text(each.label) }
            }
        }
        Text(
            when (mode) {
                DictationMode.PROMPT -> "Fale do jeito que você pensa: sai um prompt organizado, já copiado."
                DictationMode.LITERAL -> "Só limpa a fala, mantendo as suas palavras."
                DictationMode.REVISION -> "Cole o texto no campo e dite o que mudar. O resultado substitui o texto do campo, para revisar de novo, e é copiado."
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        if (mode == DictationMode.REVISION) {
            RevisionField(
                text = revisionText,
                onChange = ::updateRevisionText,
                onPaste = { context.clipboardText()?.let(::updateRevisionText) },
                enabled = state !is DictationState.Listening && state !is DictationState.Working,
            )
        }

        val listening = state as? DictationState.Listening
        Box(contentAlignment = Alignment.Center) {
            Box(
                Modifier.size(150.dp).scale(1f + (listening?.level ?: 0f) * 0.3f)
                    .background((if (listening != null) Color.Red else MaterialTheme.colorScheme.primary).copy(alpha = 0.15f), CircleShape),
            )
            FilledIconButton(
                onClick = ::toggle,
                enabled = state !is DictationState.Working,
                modifier = Modifier.size(110.dp),
                colors = if (listening != null) IconButtonDefaults.filledIconButtonColors(containerColor = Color(0xFFE53E3E))
                else IconButtonDefaults.filledIconButtonColors(),
            ) {
                Icon(if (listening != null) Icons.Filled.Stop else Icons.Filled.Mic,
                    contentDescription = if (listening != null) "Terminar" else "Ditar", modifier = Modifier.size(48.dp))
            }
        }

        val message = when (val current = state) {
            DictationState.Idle -> if (permissionDenied) "Sem o microfone não dá para ditar. Libere nas configurações do Android." else "Toque para ditar"
            is DictationState.Listening -> "Ouvindo… ${current.remaining}" + current.partial.let { if (it.isEmpty()) " · toque para terminar" else "\n$it" }
            is DictationState.Working -> current.message
            is DictationState.Finished -> when {
                !current.delivered -> current.message
                mode == DictationMode.REVISION -> "${current.message}: o campo foi atualizado e o texto, copiado"
                else -> "${current.message}: copiado para a área de transferência"
            }
            is DictationState.Failed -> current.message
        }
        Text(
            message,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            color = if (state is DictationState.Failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
        )
    }
}

/** Campo com o texto a revisar. Cada revisão substitui o conteúdo pelo resultado. */
@Composable
private fun RevisionField(text: String, onChange: (String) -> Unit, onPaste: () -> Unit, enabled: Boolean) {
    Column(Modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = text,
            onValueChange = onChange,
            modifier = Modifier.fillMaxWidth(),
            enabled = enabled,
            label = { Text("Texto a revisar") },
            placeholder = { Text("Cole aqui o texto a revisar") },
            minLines = 5,
            maxLines = 10,
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            TextButton(onClick = onPaste, enabled = enabled) { Text("Colar") }
            TextButton(onClick = { onChange("") }, enabled = enabled && text.isNotEmpty()) { Text("Limpar") }
        }
    }
}
