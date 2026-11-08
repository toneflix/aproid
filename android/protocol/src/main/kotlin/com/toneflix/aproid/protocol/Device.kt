package com.toneflix.aproid.protocol

/**
 * A connected peer: its encrypted link plus pairing. Packets from a device that
 * is not paired are dropped, except pairing packets.
 */
class Device(
    val link: DeviceLink,
    private val ownCertificate: DeviceCertificate,
    private val trustStore: TrustStore,
    private val clock: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    interface Listener {
        /** The peer asked to pair. Show [code] and call [accept] or [reject]. */
        fun onPairRequest(device: Device, code: String) {}

        fun onPairStateChanged(device: Device, state: PairState) {}

        fun onPacket(device: Device, packet: NetworkPacket) {}

        fun onDisconnected(device: Device) {}
    }

    val id: String get() = link.identity.deviceId

    val name: String get() = link.identity.deviceName

    var listener: Listener? = null

    private val pairing = PairingStateMachine(
        if (trustStore.isTrusted(id)) PairState.PAIRED else PairState.NOT_PAIRED,
    )

    val pairState: PairState get() = pairing.state

    val isPaired: Boolean get() = pairing.state == PairState.PAIRED

    /** The code to show on screen while a pair request is open. */
    val verificationCode: String
        get() = VerificationKey.compute(
            ownCertificate.publicKeyBytes,
            link.certificate.publicKey.encoded,
            pairing.requestTimestamp,
        )

    fun start() {
        link.onPacket = ::handle
        link.onClosed = { listener?.onDisconnected(this) }
        link.startReading()
    }

    fun send(packet: NetworkPacket): Boolean {
        if (!isPaired) return false

        link.send(packet)

        return true
    }

    fun requestPair() = apply(pairing.requestPair(clock()))

    fun accept() = apply(pairing.accept())

    fun reject() = apply(pairing.reject())

    fun unpair() = apply(pairing.unpair())

    /** Call every few seconds so unanswered requests expire. */
    fun tick() = apply(pairing.tick(clock()))

    private fun handle(packet: NetworkPacket) {
        if (packet.type == PacketType.PAIR) {
            apply(pairing.onPacket(packet, clock()))
            return
        }

        if (isPaired) listener?.onPacket(this, packet)
    }

    private fun apply(action: PairAction) {
        when (action) {
            PairAction.None -> return
            PairAction.AskUser -> listener?.onPairRequest(this, verificationCode)
            is PairAction.Send -> link.send(action.packet)
            PairAction.Paired, PairAction.Unpaired -> Unit
        }

        syncTrust()
        listener?.onPairStateChanged(this, pairing.state)
    }

    private fun syncTrust() {
        when (pairing.state) {
            PairState.PAIRED -> trustStore.trust(id, link.certificate.encoded)
            PairState.NOT_PAIRED -> trustStore.forget(id)
            else -> Unit
        }
    }
}
