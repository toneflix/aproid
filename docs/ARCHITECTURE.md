# Architecture

Three apps, one protocol. The Windows app (`windows/`) mirrors the Mac app: `Aproid.Core` is the C# port of AproidKit, and a WinUI 3 tray app takes the place of the menu bar app.

```
Android phone                                  Mac
┌──────────────────────────┐                  ┌──────────────────────────┐
│ app (Compose UI)          │                  │ Aproid (SwiftUI menu bar) │
│ LinkService (foreground)  │                  │ AppModel                  │
│ feature plugins           │                  │ feature plugins           │
├──────────────────────────┤   Wi-Fi / LAN    ├──────────────────────────┤
│ protocol (Kotlin)         │ ◀──────────────▶ │ AproidKit (Swift)         │
│ packets, pairing, LanLink │   TLS over TCP   │ packets, pairing, LanLink │
└──────────────────────────┘                  └──────────────────────────┘
```

The protocol code exists three times, in Kotlin, Swift and C#, with the same names and the same tests. When you change one, change the others.

## Why KDE Connect's protocol

It already solves discovery, pairing, encryption and file transfer, and it is documented and widely used. Speaking it means Aproid works with KDE Connect on Linux, Windows and Android from day one. We add our own packet types (prefixed `aproid.`) for features KDE Connect lacks. A peer only gets those if it lists them in its capabilities, so plain KDE Connect clients are unaffected.

We do not copy KDE Connect's code, which is GPL. We implement the protocol ourselves, which keeps this repository MIT.

## Protocol summary (version 8)

**Packets.** Every message is one line of JSON ending in `\n`:

```json
{"id": 1700000000000, "type": "kdeconnect.ping", "body": {}}
```

A packet that carries a file adds `payloadSize` and `payloadTransferInfo: {"port": N}`. The receiver opens a separate TLS connection to that port to download the bytes.

**Discovery.**

1. Each device broadcasts a `kdeconnect.identity` packet over UDP to port 1716. It holds the device id, name, type, protocol version, capabilities and the TCP port it listens on (from 1716 to 1764).
2. A device that hears a broadcast opens a TCP connection to that port and sends its own identity in plain text. It skips devices it already has an open link to.
3. If both devices connect at the same moment, both keep the link opened by the device with the larger id and close the other. Any later link replaces the old one, because a peer only reconnects when its old link died.

**Encryption.** Each device has a self-signed certificate whose common name is its device id. After the plain-text identity, both sides start TLS on the same socket. The device that *opened* the TCP connection acts as the TLS *server*. Once TLS is up, version 8 has both sides send their identity again over the encrypted link. A paired device's certificate is saved and must match on every later connection.

**Heartbeat (`aproid.heartbeat`).** Every 5 seconds each side sends `{"pong": false}` and the other answers at once with `{"pong": true}`. A link that receives nothing for 30 seconds is closed, so discovery can reconnect. A sleeping phone wakes to answer even when its own timer is paused. Only peers that list the packet in their capabilities take part.

**Pairing.** A sends `kdeconnect.pair` with `pair: true` and `timestamp` (Unix seconds). B shows a prompt and a short verification code derived from both certificates and the timestamp, so the user can check the same code shows on both screens. B answers `pair: true` to accept or `pair: false` to reject. Either side sends `pair: false` later to unpair. Requests time out after 30 seconds. `PairingStateMachine` implements this on both sides.

## What is done and what is next

Done:

- Packet format, identity, name rules and the pairing state machine, with tests, in Kotlin and Swift.
- LAN discovery, plain-text identity exchange, and the TLS upgrade with v8 identity re-exchange (`LanLink`).
- Self-signed RSA 2048 certificates per device (`DeviceCertificate`), stored on first launch.
- Trusted devices (`TrustStore`): a paired device whose certificate changes is refused.
- `Device`: wraps a link with pairing, and drops packets from unpaired devices.
- Pairing UI with the verification code on both apps.
- The Mac side runs on SwiftNIO and swift-nio-ssl, because Network.framework cannot start TLS on a connection that is already open.

- `Plugin` and `PluginRouter`: each feature declares the packet types it accepts, and the router hands packets from paired devices to it.
- Notifications plugin: Android sends `kdeconnect.notification` from a `NotificationListenerService`; the Mac shows them in Notification Center with a Reply field, and sends back `kdeconnect.notification.reply` or `kdeconnect.notification.request` (`cancel`) on dismiss. On pairing the Mac asks for all current notifications (`request: true`).

Next, in order:

1. Check against a real KDE Connect install: the verification code derivation and certificate fields.
2. Notification app icons (sent as payloads), then ping, battery, clipboard and share (files and links).

## Platform limits to design around

- **RCS:** Android gives other apps no RCS access. RCS chats can only be mirrored through their notifications. SMS and MMS work through the SMS provider.
- **Google Play and SMS or call log permissions:** these are restricted to default SMS or phone apps and a few exceptions, including companion apps for connected devices. Expect a review and a written justification.
- **Call audio (experimental):** Android does not let apps capture call audio, so the Mac acts as a Bluetooth hands-free device for the phone, as Phone Link does on Windows. `HandsFreeAudio` uses `IOBluetoothHandsFreeDevice`: once the phone and Mac are paired over Bluetooth, the Mac connects as a headset and Android sends call audio to it by itself. `aproid.callaudio.request` (`status` or `pair`, with the Mac's Bluetooth address) lets the Mac ask how the phone's side stands or have the phone start pairing; the phone answers and reports changes with `aproid.callaudio`. Answering from the Mac goes over Bluetooth so the audio comes to the Mac; the call banner moves the audio between the Mac and the phone and mutes the microphone in use (`mute`/`unmute` in `aproid.call.request` for the phone's). Audio is phone-call quality, and `IOBluetoothHandsFreeDevice` is an old API that some macOS versions handle unreliably.
- **Background limits:** the Android side runs as a `connectedDevice` foreground service. Later we should use `CompanionDeviceManager` so the system keeps the service alive and grants extra background rights.
- **macOS local network privacy:** a bundled app needs `NSLocalNetworkUsageDescription` and Bonjour entries in its Info.plist. When we move from `swift run` to a signed `.app`, add these.
