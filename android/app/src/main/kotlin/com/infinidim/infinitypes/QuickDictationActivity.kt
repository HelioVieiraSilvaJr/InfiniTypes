package com.infinidim.infinitypes

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.infinidim.infinitypes.dictation.DictationSession
import com.infinidim.infinitypes.ui.DictationPanel
import com.infinidim.infinitypes.ui.InfiniTypesTheme

/** Ditado rápido aberto pelo bloco das Configurações Rápidas. Começa a ouvir na hora. */
class QuickDictationActivity : ComponentActivity() {
    private lateinit var session: DictationSession

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        session = DictationSession(this, lifecycleScope)
        setContent {
            InfiniTypesTheme {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
                    Surface(
                        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
                        tonalElevation = 6.dp,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(Modifier.padding(24.dp).navigationBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
                            DictationPanel(session, autoStart = true)
                            TextButton(onClick = ::finish) { Text("Fechar") }
                        }
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        session.destroy()
        super.onDestroy()
    }
}
