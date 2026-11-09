package com.infinidim.infinitypes.ui

import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon as DrawableIcon
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.infinidim.infinitypes.DictationTileService
import com.infinidim.infinitypes.R
import com.infinidim.infinitypes.Services
import com.infinidim.infinitypes.core.AnthropicClient
import com.infinidim.infinitypes.core.Effort
import com.infinidim.infinitypes.core.GlossaryProject
import com.infinidim.infinitypes.core.ModelCatalog
import com.infinidim.infinitypes.core.RefinementModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Chave da API, modelo, glossário, teclado e bloco das Configurações Rápidas. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(services: Services) {
    val context = LocalContext.current
    val settings = services.settings
    val hasKey by services.apiKey.hasKey.collectAsState()
    val glossary by services.glossary.glossary.collectAsState()
    var key by remember { mutableStateOf("") }
    var modelId by remember { mutableStateOf(settings.modelId) }
    var effort by remember { mutableStateOf(settings.effort) }
    var projectName by remember { mutableStateOf(settings.projectName) }
    var allowNetwork by remember { mutableStateOf(settings.allowNetworkRecognition) }
    var models by remember { mutableStateOf(ModelCatalog.known) }
    var modelsError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(hasKey) {
        val apiKey = services.apiKey.get() ?: return@LaunchedEffect
        runCatching { withContext(Dispatchers.IO) { AnthropicClient(apiKey).listModels() } }
            .onSuccess { models = ModelCatalog.merge(it); modelsError = null }
            .onFailure { modelsError = "Não consegui atualizar a lista de modelos: ${it.message}" }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Section("Chave da API da Anthropic")
        Hint("Crie uma chave em console.anthropic.com. Ela fica cifrada pelo Android Keystore e só é enviada para api.anthropic.com.")
        if (hasKey) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Chave salva", modifier = Modifier.weight(1f))
                TextButton(onClick = { services.apiKey.set("") }) { Text("Remover") }
            }
        } else {
            OutlinedTextField(key, { key = it }, Modifier.fillMaxWidth(), label = { Text("sk-ant-…") }, singleLine = true,
                visualTransformation = PasswordVisualTransformation())
            Button(onClick = { services.apiKey.set(key); key = "" }, enabled = key.isNotBlank()) { Text("Salvar chave") }
        }

        HorizontalDivider()
        Section("Modelo")
        Dropdown(
            label = "Modelo",
            options = (models + listOfNotNull(ModelCatalog.model(modelId).takeIf { m -> models.none { it.id == m.id } })).map { it.id to it.displayName },
            selected = modelId,
        ) { modelId = it; settings.modelId = it }
        val model: RefinementModel = ModelCatalog.model(modelId)
        model.priceLabel?.let { Hint(it) }
        modelsError?.let { Hint(it) }
        if (model.supportsEffort) {
            Text("Esforço", style = MaterialTheme.typography.labelLarge)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                Effort.entries.forEachIndexed { index, each ->
                    SegmentedButton(effort == each, { effort = each; settings.effort = each },
                        SegmentedButtonDefaults.itemShape(index, Effort.entries.size)) { Text(each.label) }
                }
            }
        }

        HorizontalDivider()
        Section("Glossário")
        Hint("Termos com a grafia certa, um por linha (ex.: Supabase, useAuthStore). Eles orientam o reconhecimento e o refinamento.")
        OutlinedTextField(glossary.globalTerms, { services.glossary.update(glossary.copy(globalTerms = it)) },
            Modifier.fillMaxWidth().heightIn(min = 100.dp), label = { Text("Termos globais") })
        val projectNames = glossary.projects.map { it.name.trim() }.filter { it.isNotEmpty() }
        Dropdown(
            label = "Projeto atual",
            options = listOf("" to "Nenhum projeto") + projectNames.map { it to it },
            selected = projectName.orEmpty(),
        ) { projectName = it.ifEmpty { null }; settings.projectName = projectName }
        glossary.projects.forEachIndexed { index, project ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(project.name, { services.glossary.update(glossary.copy(projects = glossary.projects.replace(index, project.copy(name = it)))) },
                    Modifier.fillMaxWidth(), label = { Text("Nome do projeto") }, singleLine = true)
                OutlinedTextField(project.terms, { services.glossary.update(glossary.copy(projects = glossary.projects.replace(index, project.copy(terms = it)))) },
                    Modifier.fillMaxWidth().heightIn(min = 80.dp), label = { Text("Termos do projeto") })
                TextButton(onClick = { services.glossary.update(glossary.copy(projects = glossary.projects.filterIndexed { i, _ -> i != index })) }) {
                    Text("Remover projeto")
                }
            }
        }
        OutlinedButton(onClick = { services.glossary.update(glossary.copy(projects = glossary.projects + GlossaryProject())) }) {
            Text("Adicionar projeto")
        }

        HorizontalDivider()
        Section("Teclado InfiniTypes")
        Hint("Dite direto em qualquer campo: ative o teclado e troque para ele pelo ícone de teclado. Na revisão, selecione o texto antes.")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { context.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) }) { Text("Ativar") }
            OutlinedButton(onClick = { context.getSystemService(InputMethodManager::class.java).showInputMethodPicker() }) { Text("Trocar de teclado") }
        }
        Section("Configurações Rápidas")
        Hint("Um bloco que abre o ditado já ouvindo e copia o resultado, para quem não quiser trocar de teclado.")
        OutlinedButton(onClick = {
            context.getSystemService(StatusBarManager::class.java).requestAddTileService(
                ComponentName(context, DictationTileService::class.java), "Ditar prompt",
                DrawableIcon.createWithResource(context, R.drawable.ic_waveform), context.mainExecutor,
            ) {}
        }) { Text("Adicionar o bloco") }

        HorizontalDivider()
        Section("Privacidade")
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Permitir reconhecimento pela rede")
                Hint("Só quando o aparelho não reconhece português offline. Com isso, o áudio vai para o serviço de voz do Android.")
            }
            Switch(allowNetwork, { allowNetwork = it; settings.allowNetworkRecognition = it })
        }
    }
}

private fun List<GlossaryProject>.replace(index: Int, project: GlossaryProject) = mapIndexed { i, each -> if (i == index) project else each }

@Composable
private fun Section(title: String) = Text(title, style = MaterialTheme.typography.titleMedium)

@Composable
private fun Hint(text: String) = Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Dropdown(label: String, options: List<Pair<String, String>>, selected: String, onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(open, { open = it }) {
        OutlinedTextField(
            value = options.firstOrNull { it.first == selected }?.second ?: selected,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(open) },
            modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(open, { open = false }) {
            options.forEach { (value, title) ->
                DropdownMenuItem(text = { Text(title) }, onClick = { onSelect(value); open = false })
            }
        }
    }
}
