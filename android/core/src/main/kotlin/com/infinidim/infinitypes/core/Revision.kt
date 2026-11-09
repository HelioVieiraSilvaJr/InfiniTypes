package com.infinidim.infinitypes.core

import org.json.JSONArray
import org.json.JSONObject

/** Uma alteração devolvida pelo modelo na revisão: um trecho literal do original e o que fica no lugar. */
data class RevisionEdit(val original: String, val revised: String)

class RevisionPatchException(val error: Error) : Exception(error.reason) {
    /** O motivo vai para o log, sem o trecho do texto do usuário. */
    enum class Error(val reason: String) {
        NOT_FOUND("trecho não encontrado"),
        AMBIGUOUS("trecho repetido"),
        OVERLAPPING("alterações sobrepostas"),
    }
}

/** Aplica ao texto original as alterações devolvidas pelo modelo. O que não foi alterado fica idêntico. */
object RevisionPatcher {
    /** Esquema JSON enviado à API para a resposta vir como `{"edits": [{"original", "revised"}]}`. */
    fun schema(): JSONObject = JSONObject()
        .put("type", "object")
        .put(
            "properties",
            JSONObject().put(
                "edits",
                JSONObject()
                    .put("type", "array")
                    .put(
                        "items",
                        JSONObject()
                            .put("type", "object")
                            .put(
                                "properties",
                                JSONObject()
                                    .put("original", JSONObject().put("type", "string"))
                                    .put("revised", JSONObject().put("type", "string")),
                            )
                            .put("required", JSONArray().put("original").put("revised"))
                            .put("additionalProperties", false),
                    ),
            ),
        )
        .put("required", JSONArray().put("edits"))
        .put("additionalProperties", false)

    /** Lê a resposta estruturada do modelo. */
    fun parse(json: String): List<RevisionEdit> {
        val edits = JSONObject(json).getJSONArray("edits")
        return (0 until edits.length()).map {
            val edit = edits.getJSONObject(it)
            RevisionEdit(edit.getString("original"), edit.getString("revised"))
        }
    }

    /** Cada trecho precisa aparecer uma única vez no original, e os trechos não podem se sobrepor. */
    fun apply(edits: List<RevisionEdit>, text: String): String {
        val located = edits.map { edit ->
            if (edit.original.isEmpty()) throw RevisionPatchException(RevisionPatchException.Error.NOT_FOUND)
            val start = text.indexOf(edit.original)
            if (start < 0) throw RevisionPatchException(RevisionPatchException.Error.NOT_FOUND)
            if (text.indexOf(edit.original, start + edit.original.length) >= 0) {
                throw RevisionPatchException(RevisionPatchException.Error.AMBIGUOUS)
            }
            Triple(start, edit.original.length, edit.revised)
        }.sortedBy { it.first }

        val result = StringBuilder()
        var cursor = 0
        for ((start, length, revised) in located) {
            if (start < cursor) throw RevisionPatchException(RevisionPatchException.Error.OVERLAPPING)
            result.append(text, cursor, start).append(revised)
            cursor = start + length
        }
        return result.append(text, cursor, text.length).toString()
    }
}
