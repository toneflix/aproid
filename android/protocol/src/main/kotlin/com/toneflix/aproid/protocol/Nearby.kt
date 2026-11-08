package com.toneflix.aproid.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import java.nio.ByteBuffer
import java.security.PrivateKey
import java.security.PublicKey
import java.security.SecureRandom
import java.security.spec.MGF1ParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

/**
 * Finding the phone over Bluetooth when Wi-Fi discovery fails. The phone offers a Bluetooth LE
 * service; a paired Mac writes a [Request], and the phone answers with where to reach it, and
 * optionally a hotspot to join, sealed to that Mac's certificate so only it can read the answer.
 */
object Nearby {
    const val SERVICE = "a9d2e4b0-6f1c-4e8a-b7d3-5c0f2a1e9b40"
    const val REQUEST = "a9d2e4b0-6f1c-4e8a-b7d3-5c0f2a1e9b41"
    const val ANSWER = "a9d2e4b0-6f1c-4e8a-b7d3-5c0f2a1e9b42"

    enum class Want(val wire: String) {
        /** Just tell me your address. */
        CONNECT("connect"),

        /** We share no network: start a hotspot for me to join. */
        HOTSPOT("hotspot"),
    }

    data class Request(val deviceId: String, val want: Want) {
        fun toBytes(): ByteArray = buildJsonObject {
            put("id", deviceId)
            put("want", want.wire)
        }.toString().toByteArray()

        companion object {
            fun fromBytes(bytes: ByteArray): Request? = runCatching {
                val json = Json.parseToJsonElement(bytes.decodeToString()) as JsonObject
                val id = (json["id"] as? JsonPrimitive)?.content?.takeIf(DeviceIdentity::isValidDeviceId) ?: return null
                val want = Want.entries.firstOrNull { it.wire == (json["want"] as? JsonPrimitive)?.content } ?: return null
                Request(id, want)
            }.getOrNull()
        }
    }

    /** Where to reach the phone. [ssid] and [password] are set when it started a hotspot. */
    data class Answer(
        val deviceId: String,
        val addresses: List<String>,
        val port: Int,
        val ssid: String? = null,
        val password: String? = null,
    ) {
        fun toJson(): JsonObject = buildJsonObject {
            put("i", deviceId)
            put("a", JsonArray(addresses.map(::JsonPrimitive)))
            put("p", port)
            ssid?.let { put("s", it) }
            password?.let { put("k", it) }
        }

        companion object {
            fun fromJson(json: JsonObject): Answer? {
                fun text(key: String) = (json[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
                val id = text("i") ?: return null
                val port = (json["p"] as? JsonPrimitive)?.intOrNull?.takeIf { it in 1..65535 } ?: return null
                val addresses = (json["a"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.content }

                return Answer(id, addresses, port, text("s"), text("k"))
            }
        }
    }

    private const val KEY_BITS = 256
    private const val NONCE_SIZE = 12
    private const val TAG_BITS = 128

    /**
     * Encrypts [answer] for the holder of [peer]'s private key: a fresh AES-GCM key wrapped with
     * RSA-OAEP (SHA-256 for both the hash and MGF1, to match Apple's), then the nonce and ciphertext.
     */
    fun seal(answer: Answer, peer: PublicKey, random: SecureRandom = SecureRandom()): ByteArray {
        val key = KeyGenerator.getInstance("AES").apply { init(KEY_BITS, random) }.generateKey()
        val nonce = ByteArray(NONCE_SIZE).also(random::nextBytes)

        val wrapped = Cipher.getInstance("RSA/ECB/OAEPPadding").run {
            init(Cipher.ENCRYPT_MODE, peer, oaep, random)
            doFinal(key.encoded)
        }
        val sealed = Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
            doFinal(answer.toJson().toString().toByteArray())
        }

        return ByteBuffer.allocate(2 + wrapped.size + nonce.size + sealed.size)
            .putShort(wrapped.size.toShort())
            .put(wrapped)
            .put(nonce)
            .put(sealed)
            .array()
    }

    /** Reads an answer sealed to us. Null when it isn't for our key or was changed on the way. */
    fun open(bytes: ByteArray, own: PrivateKey): Answer? = runCatching {
        val buffer = ByteBuffer.wrap(bytes)
        val wrapped = ByteArray(buffer.short.toInt() and 0xFFFF).also { buffer.get(it) }
        val nonce = ByteArray(NONCE_SIZE).also { buffer.get(it) }
        val sealed = ByteArray(buffer.remaining()).also { buffer.get(it) }

        val key = Cipher.getInstance("RSA/ECB/OAEPPadding").run {
            init(Cipher.DECRYPT_MODE, own, oaep)
            doFinal(wrapped)
        }
        val plain = Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
            doFinal(sealed)
        }

        Answer.fromJson(Json.parseToJsonElement(plain.decodeToString()) as JsonObject)
    }.getOrNull()

    private val oaep = OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, PSource.PSpecified.DEFAULT)
}
