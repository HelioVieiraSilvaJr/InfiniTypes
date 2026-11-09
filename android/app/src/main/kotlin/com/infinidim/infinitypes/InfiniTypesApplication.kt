package com.infinidim.infinitypes

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import com.infinidim.infinitypes.core.ClaudeRefiner
import com.infinidim.infinitypes.core.HallucinationFilter
import com.infinidim.infinitypes.storage.ApiKeyStore
import com.infinidim.infinitypes.storage.GlossaryStore
import com.infinidim.infinitypes.storage.HistoryDatabase
import com.infinidim.infinitypes.storage.SettingsStore

class InfiniTypesApplication : Application() {
    lateinit var services: Services
        private set

    override fun onCreate() {
        super.onCreate()
        services = Services(this)
        HallucinationFilter.log = { Log.i("InfiniTypes", it) }
    }
}

/** O que o app, o teclado e o bloco das Configurações Rápidas compartilham. */
class Services(context: Context) {
    val settings = SettingsStore(context)
    val apiKey = ApiKeyStore(context)
    val glossary = GlossaryStore(context)
    val history = HistoryDatabase(context)
    val refiner = ClaudeRefiner(apiKey::get) { settings.modelId to settings.effort }.apply {
        log = { Log.i("InfiniTypes", it) }
    }
}

fun Context.copyToClipboard(text: String) {
    getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("InfiniTypes", text))
}

fun Context.clipboardText(): String? =
    getSystemService(ClipboardManager::class.java).primaryClip?.takeIf { it.itemCount > 0 }
        ?.getItemAt(0)?.coerceToText(this)?.toString()
