package com.infinidim.infinitypes.storage

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.edit
import com.infinidim.infinitypes.core.Effort
import com.infinidim.infinitypes.core.Glossary
import com.infinidim.infinitypes.core.GlossaryProject
import com.infinidim.infinitypes.core.ModelCatalog
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Preferências do app. A chave da API fica à parte, cifrada pelo Android Keystore. */
class SettingsStore(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    var modelId: String
        get() = prefs.getString("modelId", null) ?: ModelCatalog.DEFAULT_MODEL_ID
        set(value) = prefs.edit { putString("modelId", value) }

    var effort: Effort
        get() = Effort.parse(prefs.getString("effort", null))
        set(value) = prefs.edit { putString("effort", value.rawValue) }

    /** Projeto do glossário escolhido: no Android não há título de janela para reconhecê-lo. */
    var projectName: String?
        get() = prefs.getString("projectName", null)
        set(value) = prefs.edit { putString("projectName", value) }

    /** Por padrão só o reconhecimento no aparelho é usado, para o áudio não sair dele. */
    var allowNetworkRecognition: Boolean
        get() = prefs.getBoolean("allowNetworkRecognition", false)
        set(value) = prefs.edit { putBoolean("allowNetworkRecognition", value) }

    /**
     * Texto do campo de revisão do app. Cada revisão o substitui pelo resultado, para revisar de novo, e ele fica
     * salvo para não se perder se o Android encerrar o app enquanto você usa outro.
     */
    var revisionText: String
        get() = prefs.getString("revisionText", null).orEmpty()
        set(value) = prefs.edit { putString("revisionText", value) }
}

/** Chave da API cifrada com AES-GCM por uma chave do Android Keystore, que nunca sai do hardware. */
class ApiKeyStore(context: Context) {
    private val prefs = context.getSharedPreferences("secrets", Context.MODE_PRIVATE)
    private val _hasKey = MutableStateFlow(prefs.contains(VALUE))
    val hasKey: StateFlow<Boolean> = _hasKey

    fun get(): String? {
        val stored = prefs.getString(VALUE, null) ?: return null
        return runCatching {
            val bytes = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, IV_LENGTH))
            String(cipher.doFinal(bytes, IV_LENGTH, bytes.size - IV_LENGTH), Charsets.UTF_8)
        }.getOrNull()
    }

    /** Uma chave vazia remove a atual. */
    fun set(value: String) {
        val key = value.trim()
        if (key.isEmpty()) {
            prefs.edit { remove(VALUE) }
        } else {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val encrypted = cipher.iv + cipher.doFinal(key.toByteArray(Charsets.UTF_8))
            prefs.edit { putString(VALUE, Base64.encodeToString(encrypted, Base64.NO_WRAP)) }
        }
        _hasKey.value = key.isNotEmpty()
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "infinitypes-api-key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
        const val VALUE = "anthropicApiKey"
    }
}

/** Glossário em `files/Glossary.json`, no mesmo formato do Windows. */
class GlossaryStore(context: Context) {
    private val file = File(context.filesDir, "Glossary.json")
    private val _glossary = MutableStateFlow(load())
    val glossary: StateFlow<Glossary> = _glossary

    fun update(glossary: Glossary) {
        _glossary.value = glossary
        val projects = JSONArray()
        glossary.projects.forEach { projects.put(JSONObject().put("name", it.name).put("terms", it.terms)) }
        val json = JSONObject().put("global_terms", glossary.globalTerms).put("projects", projects)
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(json.toString(2))
        temporary.renameTo(file)
    }

    private fun load(): Glossary = runCatching {
        val json = JSONObject(file.readText())
        val projects = json.optJSONArray("projects") ?: JSONArray()
        Glossary(
            json.optString("global_terms"),
            (0 until projects.length()).map { projects.getJSONObject(it).let { p -> GlossaryProject(p.optString("name"), p.optString("terms")) } },
        )
    }.getOrDefault(Glossary())
}
