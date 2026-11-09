package com.infinidim.infinitypes.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.infinidim.infinitypes.clipboardText
import com.infinidim.infinitypes.copyToClipboard
import com.infinidim.infinitypes.core.DictationContext
import com.infinidim.infinitypes.core.DictationMode
import com.infinidim.infinitypes.dictation.DictationSession
import com.infinidim.infinitypes.dictation.DictationState

/**
 * Ditado com entrega pela área de transferência, usado na aba Ditar e no bloco das Configurações Rápidas.
 * Na revisão, o texto copiado é o original.
 */
@Composable
fun DictationPanel(session: DictationSession, autoStart: Boolean = false, onDelivered: (String) -> Unit = {}) {
    val context = LocalContext.current
    val state by session.state.collectAsState()
    var mode by rememberSaveable { mutableStateOf(DictationMode.PROMPT) }
    var started by rememberSaveable { mutableStateOf(false) }
    var permissionDenied by remember { mutableStateOf(false) }

    fun begin() {
        session.start(mode, context.clipboardText(), DictationContext.EMPTY) { text ->
            context.copyToClipboard(text)
            onDelivered(text)
        }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        permissionDenied = !granted
        if (granted) begin()
    }

    fun toggle() {
        when {
            session.isListening -> session.stop()
            session.isWorking -> Unit
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED ->
                permission.launch(Manifest.permission.RECORD_AUDIO)
            else -> begin()
        }
    }

    if (autoStart && !started) {
        started = true
        toggle()
    }

    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
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
                DictationMode.REVISION -> "Copie o texto antes. Depois dite o que mudar: a versão revisada é copiada."
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

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
            is DictationState.Listening -> current.partial.ifEmpty { "Ouvindo… toque para terminar" }
            is DictationState.Working -> current.message
            is DictationState.Finished -> "${current.message}: copiado para a área de transferência"
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
