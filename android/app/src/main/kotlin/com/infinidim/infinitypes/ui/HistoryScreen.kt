package com.infinidim.infinitypes.ui

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.infinidim.infinitypes.Services
import com.infinidim.infinitypes.copyToClipboard
import com.infinidim.infinitypes.core.DayGrouping
import com.infinidim.infinitypes.core.DictationRecord
import com.infinidim.infinitypes.core.EvalExporter
import com.infinidim.infinitypes.core.ModelCatalog
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/** Todo ditado fica aqui, para você nunca perder o que falou. */
@Composable
fun HistoryScreen(services: Services) {
    val context = LocalContext.current
    val version by services.history.version.collectAsState()
    var search by remember { mutableStateOf("") }
    var expanded by remember { mutableLongStateOf(-1L) }
    val records = remember(version, search) { services.history.records(search) }
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    val sections = records.groupBy { DayGrouping.title(Instant.ofEpochMilli(it.createdAt).atZone(zone).toLocalDate(), today) }
    val marked = remember(version) { services.history.records(limit = Int.MAX_VALUE).filter { it.inEvalSet } }

    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        OutlinedTextField(search, { search = it }, Modifier.fillMaxWidth(), label = { Text("Buscar no histórico") }, singleLine = true)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("${records.size} ditados · ${marked.size} marcados", style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.weight(1f))
            TextButton(enabled = marked.isNotEmpty(), onClick = {
                val jsonl = EvalExporter.jsonl(marked.map { Instant.ofEpochMilli(it.createdAt).truncatedTo(ChronoUnit.SECONDS).toString() to it })
                context.startActivity(Intent.createChooser(
                    Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, jsonl), "Exportar avaliação"))
            }) { Text("Exportar avaliação") }
        }
        if (records.isEmpty()) {
            Text(if (search.isEmpty()) "Nenhum ditado ainda. Toque no microfone na aba Ditar e fale." else "Nada encontrado.",
                modifier = Modifier.padding(top = 32.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            sections.forEach { (title, items) ->
                item(key = "section-$title") {
                    Text(title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 12.dp))
                }
                items(items, key = { it.id }) { record ->
                    RecordCard(
                        record,
                        expanded = expanded == record.id,
                        onToggle = { expanded = if (expanded == record.id) -1 else record.id },
                        onCopy = { context.copyToClipboard(record.text) },
                        onStar = { services.history.update(record.copy(inEvalSet = !record.inEvalSet)) },
                        onDelete = { services.history.delete(record.id) },
                    )
                }
            }
        }
    }
}

@Composable
private fun RecordCard(
    record: DictationRecord,
    expanded: Boolean,
    onToggle: () -> Unit,
    onCopy: () -> Unit,
    onStar: () -> Unit,
    onDelete: () -> Unit,
) {
    val time = DateTimeFormatter.ofPattern("HH:mm").format(Instant.ofEpochMilli(record.createdAt).atZone(ZoneId.systemDefault()))
    val header = listOfNotNull(time, record.mode.label, record.appName, record.projectName,
        record.modelId?.let { ModelCatalog.model(it).displayName }).joinToString(" · ")
    Card(Modifier.fillMaxWidth().clickable(onClick = onToggle)) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(header, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                IconButton(onClick = onCopy) { Icon(Icons.Filled.ContentCopy, "Copiar") }
                IconButton(onClick = onStar) {
                    Icon(if (record.inEvalSet) Icons.Filled.Star else Icons.Filled.StarBorder, "Marcar para a avaliação")
                }
                IconButton(onClick = onDelete) { Icon(Icons.Filled.Delete, "Apagar") }
            }
            Text(record.text, maxLines = if (expanded) Int.MAX_VALUE else 4, overflow = TextOverflow.Ellipsis)
            record.errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            if (expanded) {
                record.originalText?.let { Detail("Texto original", it) }
                Detail("Transcrição", record.rawTranscript)
            }
        }
    }
}

@Composable
private fun Detail(title: String, text: String) {
    Text(title, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 10.dp))
    Text(text, style = MaterialTheme.typography.bodySmall)
}
