package com.toneflix.aproid

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.toneflix.aproid.protocol.PairState
import kotlin.concurrent.thread

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
                        DeviceList()
                    }
                    PairRequestDialog()
                }
            }
        }
    }
}

/** Runs a device action off the main thread, since it writes to the network. */
private fun withDevice(id: String, action: (com.toneflix.aproid.protocol.Device) -> Unit) {
    thread(isDaemon = true) { DeviceStore.find(id)?.let(action) }
}

@Composable
private fun DeviceList() {
    val devices by DeviceStore.states.collectAsStateWithLifecycle()

    if (devices.isEmpty()) {
        Text("None yet. Open Aproid on your Mac, on the same Wi-Fi.")
        return
    }

    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items(devices, key = { it.id }) { device -> DeviceCard(device) }
    }
}

@Composable
private fun DeviceCard(device: DeviceState) {
    Card(Modifier.fillMaxWidth()) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(device.name, style = MaterialTheme.typography.titleSmall)
                Text(statusText(device))
                device.code?.let { Text(it, fontFamily = FontFamily.Monospace) }
            }
            Spacer(Modifier.padding(4.dp))
            when (device.pairState) {
                PairState.NOT_PAIRED -> Button(onClick = { withDevice(device.id) { it.requestPair() } }) { Text("Pair") }
                PairState.PAIRED -> OutlinedButton(onClick = { withDevice(device.id) { it.unpair() } }) { Text("Unpair") }
                else -> Unit
            }
        }
    }
}

private fun statusText(device: DeviceState): String = when (device.pairState) {
    PairState.NOT_PAIRED -> "Not paired"
    PairState.REQUESTED -> "Waiting for the Mac to accept. Check the code matches:"
    PairState.REQUESTED_BY_PEER -> "Wants to pair"
    PairState.PAIRED -> "Paired"
}

@Composable
private fun PairRequestDialog() {
    val request by DeviceStore.pairRequest.collectAsStateWithLifecycle()
    val device = request ?: return

    AlertDialog(
        onDismissRequest = {},
        title = { Text("Pair with ${device.name}?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Check that this code also shows on ${device.name}:")
                Text(device.code ?: "", style = MaterialTheme.typography.headlineSmall, fontFamily = FontFamily.Monospace)
            }
        },
        confirmButton = { TextButton(onClick = { withDevice(device.id) { it.accept() } }) { Text("Pair") } },
        dismissButton = { TextButton(onClick = { withDevice(device.id) { it.reject() } }) { Text("Reject") } },
    )
}
