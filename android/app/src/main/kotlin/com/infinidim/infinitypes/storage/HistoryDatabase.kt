package com.infinidim.infinitypes.storage

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.infinidim.infinitypes.core.DictationMode
import com.infinidim.infinitypes.core.DictationRecord
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Histórico em SQLite (`databases/History.db`), com as mesmas colunas do Windows. */
class HistoryDatabase(context: Context) : SQLiteOpenHelper(context, "History.db", null, 1) {
    private val _version = MutableStateFlow(0)

    /** Muda a cada gravação, para as telas recarregarem a lista. */
    val version: StateFlow<Int> = _version

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE dictations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at INTEGER NOT NULL,
                text TEXT NOT NULL,
                raw_transcript TEXT NOT NULL,
                app_name TEXT,
                app_id TEXT,
                project_name TEXT,
                mode TEXT NOT NULL,
                original_text TEXT,
                model_id TEXT,
                refined INTEGER NOT NULL,
                pasted INTEGER NOT NULL,
                error_message TEXT,
                audio_seconds REAL NOT NULL,
                transcription_seconds REAL NOT NULL,
                refinement_seconds REAL,
                input_tokens INTEGER,
                output_tokens INTEGER,
                in_eval_set INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX dictations_created_at ON dictations (created_at)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun insert(record: DictationRecord): DictationRecord {
        val values = ContentValues().apply {
            put("created_at", record.createdAt)
            put("text", record.text)
            put("raw_transcript", record.rawTranscript)
            put("app_name", record.appName)
            put("app_id", record.appId)
            put("project_name", record.projectName)
            put("mode", record.mode.rawValue)
            put("original_text", record.originalText)
            put("model_id", record.modelId)
            put("refined", record.refined)
            put("pasted", record.pasted)
            put("error_message", record.errorMessage)
            put("audio_seconds", record.audioSeconds)
            put("transcription_seconds", record.transcriptionSeconds)
            put("refinement_seconds", record.refinementSeconds)
            put("input_tokens", record.inputTokens)
            put("output_tokens", record.outputTokens)
            put("in_eval_set", record.inEvalSet)
        }
        val id = writableDatabase.insertOrThrow("dictations", null, values)
        _version.value++
        return record.copy(id = id)
    }

    fun update(record: DictationRecord) {
        val values = ContentValues().apply {
            put("pasted", record.pasted)
            put("in_eval_set", record.inEvalSet)
        }
        writableDatabase.update("dictations", values, "id = ?", arrayOf(record.id.toString()))
        _version.value++
    }

    fun delete(id: Long) {
        writableDatabase.delete("dictations", "id = ?", arrayOf(id.toString()))
        _version.value++
    }

    /** Do mais novo para o mais antigo. A busca olha o texto entregue, a transcrição, o app e o projeto. */
    fun records(search: String = "", limit: Int = 500): List<DictationRecord> {
        val filter = search.trim()
        val (selection, args) = if (filter.isEmpty()) {
            null to null
        } else {
            val like = "%$filter%"
            "text LIKE ? OR raw_transcript LIKE ? OR app_name LIKE ? OR project_name LIKE ?" to arrayOf(like, like, like, like)
        }
        readableDatabase.query("dictations", null, selection, args, null, null, "created_at DESC, id DESC", limit.toString())
            .use { cursor -> return generateSequence { if (cursor.moveToNext()) read(cursor) else null }.toList() }
    }

    private fun read(cursor: Cursor): DictationRecord {
        fun string(column: String) = cursor.getColumnIndexOrThrow(column).let { if (cursor.isNull(it)) null else cursor.getString(it) }
        fun double(column: String) = cursor.getColumnIndexOrThrow(column).let { if (cursor.isNull(it)) null else cursor.getDouble(it) }
        fun int(column: String) = cursor.getColumnIndexOrThrow(column).let { if (cursor.isNull(it)) null else cursor.getInt(it) }
        return DictationRecord(
            id = cursor.getLong(cursor.getColumnIndexOrThrow("id")),
            createdAt = cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
            text = string("text").orEmpty(),
            rawTranscript = string("raw_transcript").orEmpty(),
            appName = string("app_name"),
            appId = string("app_id"),
            projectName = string("project_name"),
            mode = DictationMode.parse(string("mode")),
            originalText = string("original_text"),
            modelId = string("model_id"),
            refined = int("refined") == 1,
            pasted = int("pasted") == 1,
            errorMessage = string("error_message"),
            audioSeconds = double("audio_seconds") ?: 0.0,
            transcriptionSeconds = double("transcription_seconds") ?: 0.0,
            refinementSeconds = double("refinement_seconds"),
            inputTokens = int("input_tokens"),
            outputTokens = int("output_tokens"),
            inEvalSet = int("in_eval_set") == 1,
        )
    }
}
