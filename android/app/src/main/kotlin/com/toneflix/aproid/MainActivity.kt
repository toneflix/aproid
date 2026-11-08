package com.toneflix.aproid

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
        }
        val me = DeviceStore.identity(this)
        setContent {
            MaterialTheme {
                Scaffold { padding ->
                    Column(
                        modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text("Aproid", style = MaterialTheme.typography.headlineMedium)
                        Text("This phone: ${me.deviceName}")
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { LinkService.start(this@MainActivity) }) { Text("Start") }
                            OutlinedButton(onClick = { LinkService.stop(this@MainActivity) }) { Text("Stop") }
                        }
                        Text("Nearby devices", style = MaterialTheme.typography.titleMedium)
                        PeerList()
                    }
                }
            }
        }
    }
}

@Composable
private fun PeerList() {
    val peers by DeviceStore.peers.collectAsStateWithLifecycle()
    if (peers.isEmpty()) {
        Text("None yet. Open Aproid on your Mac, on the same Wi-Fi.")
        return
    }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items(peers.values.toList(), key = { it.identity.deviceId }) { peer ->
            Card {
                Column(Modifier.padding(12.dp)) {
                    Text(peer.identity.deviceName, style = MaterialTheme.typography.titleSmall)
                    Text("${peer.identity.deviceType.wire} at ${peer.address.hostAddress}")
                }
            }
        }
    }
}
