package com.infinidim.infinitypes

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.infinidim.infinitypes.dictation.DictationSession
import com.infinidim.infinitypes.ui.DictationPanel
import com.infinidim.infinitypes.ui.HistoryScreen
import com.infinidim.infinitypes.ui.InfiniTypesTheme
import com.infinidim.infinitypes.ui.SettingsScreen

class MainActivity : ComponentActivity() {
    private lateinit var session: DictationSession

    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        session = DictationSession(this, lifecycleScope)
        val services = (application as InfiniTypesApplication).services
        setContent {
            InfiniTypesTheme {
                // Sem chave da API, a primeira tela é a de Ajustes.
                var tab by rememberSaveable { mutableIntStateOf(if (services.apiKey.hasKey.value) 0 else 2) }
                val titles = listOf("InfiniTypes", "Histórico", "Ajustes")
                Scaffold(
                    topBar = { TopAppBar(title = { Text(titles[tab]) }) },
                    bottomBar = {
                        NavigationBar {
                            NavigationBarItem(tab == 0, { tab = 0 }, { Icon(Icons.Filled.GraphicEq, null) }, label = { Text("Ditar") })
                            NavigationBarItem(tab == 1, { tab = 1 }, { Icon(Icons.Filled.History, null) }, label = { Text("Histórico") })
                            NavigationBarItem(tab == 2, { tab = 2 }, { Icon(Icons.Filled.Settings, null) }, label = { Text("Ajustes") })
                        }
                    },
                ) { padding ->
                    Box(Modifier.padding(padding).fillMaxSize()) {
                        when (tab) {
                            0 -> Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) { DictationPanel(session) }
                            1 -> HistoryScreen(services)
                            else -> SettingsScreen(services)
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
