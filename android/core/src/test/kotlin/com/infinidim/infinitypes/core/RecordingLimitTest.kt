package com.infinidim.infinitypes.core

import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingLimitTest {
    @Test
    fun countsDownFromTenMinutes() {
        assertEquals("10:00", RecordingLimit.remainingLabel(0))
        assertEquals("10:00", RecordingLimit.remainingLabel(300))
        assertEquals("9:59", RecordingLimit.remainingLabel(1_000))
        assertEquals("0:05", RecordingLimit.remainingLabel(595_500))
        assertEquals("0:00", RecordingLimit.remainingLabel(700_000))
    }
}
