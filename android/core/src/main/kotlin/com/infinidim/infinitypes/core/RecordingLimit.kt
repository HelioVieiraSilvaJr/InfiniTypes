package com.infinidim.infinitypes.core

import kotlin.math.ceil

/** Tempo máximo de uma gravação e a contagem regressiva mostrada enquanto ela dura. */
object RecordingLimit {
    /** Tempo para desenvolver uma ideia longa. Ao chegar nele, a gravação termina e o ditado segue normalmente. */
    const val DURATION_MILLIS = 10 * 60 * 1000L

    /** Tempo restante como "10:00", "9:59", …, "0:00". Arredonda para cima, para começar no limite cheio. */
    fun remainingLabel(elapsedMillis: Long): String {
        val remaining = ceil((DURATION_MILLIS - elapsedMillis) / 1000.0).toInt().coerceAtLeast(0)
        return "${remaining / 60}:${(remaining % 60).toString().padStart(2, '0')}"
    }
}
