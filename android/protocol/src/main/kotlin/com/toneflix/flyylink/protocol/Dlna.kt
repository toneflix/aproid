package com.toneflix.flyylink.protocol

import java.net.URI
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element
import org.w3c.dom.Node

/** SSDP, the multicast search that finds TVs and speakers able to play media sent over DLNA. */
object Ssdp {
    const val ADDRESS = "239.255.255.250"
    const val PORT = 1900
    const val RENDERER = "urn:schemas-upnp-org:device:MediaRenderer:1"

    fun searchMessage(target: String = RENDERER, waitSeconds: Int = 2): String =
        "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: $ADDRESS:$PORT\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: $waitSeconds\r\n" +
            "ST: $target\r\n" +
            "\r\n"

    /** Null unless [message] is a search answer or an alive notice with a description location. */
    fun parse(message: String): SsdpReply? {
        val lines = message.split("\r\n", "\n")
        val start = lines.firstOrNull()?.uppercase() ?: return null
        if (!start.startsWith("HTTP/1.1 200") && !start.startsWith("NOTIFY")) return null

        val headers = lines.drop(1).mapNotNull { line ->
            val colon = line.indexOf(':')
            if (colon <= 0) null else line.substring(0, colon).trim().uppercase() to line.substring(colon + 1).trim()
        }.toMap()

        if (headers["NTS"] == "ssdp:byebye") return null

        val location = headers["LOCATION"]?.takeIf { it.startsWith("http") } ?: return null

        return SsdpReply(location, headers["USN"].orEmpty(), headers["ST"] ?: headers["NT"].orEmpty())
    }
}

data class SsdpReply(val location: String, val usn: String, val target: String)

/** A TV or speaker that plays media from a URL, as its UPnP device description lists it. */
data class TvRenderer(
    val id: String,
    val name: String,
    val avTransportUrl: String,
    val renderingControlUrl: String? = null,
) {
    /** The address of the TV, used to pick the local address it can reach us on. */
    val host: String get() = URI(avTransportUrl).host

    companion object {
        /** Reads the first device in [xml] that has an AVTransport service, resolving its URLs against [location]. */
        fun parse(xml: String, location: String): TvRenderer? {
            val root = Xml.parse(xml) ?: return null
            val base = Xml.child(root, "URLBase")?.textContent?.trim()?.takeIf { it.isNotEmpty() } ?: location

            for (device in Xml.descendants(root, "device")) {
                val services = Xml.child(device, "serviceList")?.let { Xml.children(it, "service") }.orEmpty()
                val transport = services.controlUrl(AvTransport.SERVICE_PREFIX) ?: continue

                return TvRenderer(
                    id = Xml.text(device, "UDN") ?: location,
                    name = Xml.text(device, "friendlyName") ?: URI(location).host,
                    avTransportUrl = resolve(base, transport),
                    renderingControlUrl = services.controlUrl(RenderingControl.SERVICE_PREFIX)?.let { resolve(base, it) },
                )
            }

            return null
        }

        private fun List<Element>.controlUrl(typePrefix: String): String? =
            firstOrNull { Xml.text(it, "serviceType")?.startsWith(typePrefix) == true }?.let { Xml.text(it, "controlURL") }

        private fun resolve(base: String, url: String): String = runCatching { URI(base).resolve(url.trim()).toString() }.getOrDefault(url)
    }
}

/** What kind of media a file is, which picks how a TV shows it. */
enum class CastKind(val upnpClass: String) {
    PHOTO("object.item.imageItem.photo"),
    VIDEO("object.item.videoItem"),
    MUSIC("object.item.audioItem.musicTrack");

    companion object {
        /** Null for anything a TV can't play, such as a document. */
        fun of(mime: String?): CastKind? = when (mime?.substringBefore('/')?.lowercase()) {
            "image" -> PHOTO
            "video" -> VIDEO
            "audio" -> MUSIC
            else -> null
        }
    }
}

/** One UPnP action, sent as a SOAP request to a service's control URL. */
data class SoapCall(val service: String, val action: String, val arguments: List<Pair<String, String>>) {
    val soapAction: String get() = "\"$service#$action\""

    fun envelope(): String {
        val body = arguments.joinToString("") { (name, value) -> "<$name>${Xml.escape(value)}</$name>" }

        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
            "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">" +
            "<s:Body><u:$action xmlns:u=\"$service\">$body</u:$action></s:Body></s:Envelope>"
    }
}

/** Where playback is on the TV, in milliseconds. A duration of 0 means the TV doesn't know it, as for photos. */
data class CastPosition(val position: Long, val duration: Long)

enum class CastState {
    PLAYING,
    PAUSED,
    STOPPED,
    LOADING;

    companion object {
        fun fromWire(state: String?): CastState? = when (state?.trim()?.uppercase()) {
            "PLAYING" -> PLAYING
            "PAUSED_PLAYBACK", "PAUSED_RECORDING" -> PAUSED
            "STOPPED", "NO_MEDIA_PRESENT" -> STOPPED
            "TRANSITIONING" -> LOADING
            else -> null
        }
    }
}

/** The AVTransport service: what to play, and play, pause, stop and seek. */
object AvTransport {
    const val SERVICE = "urn:schemas-upnp-org:service:AVTransport:1"
    const val SERVICE_PREFIX = "urn:schemas-upnp-org:service:AVTransport:"

    fun setUri(url: String, title: String, mime: String, size: Long? = null): SoapCall =
        call("SetAVTransportURI", "CurrentURI" to url, "CurrentURIMetaData" to metadata(url, title, mime, size))

    fun play(): SoapCall = call("Play", "Speed" to "1")

    fun pause(): SoapCall = call("Pause")

    fun stop(): SoapCall = call("Stop")

    fun seek(positionMs: Long): SoapCall = call("Seek", "Unit" to "REL_TIME", "Target" to time(positionMs))

    fun positionInfo(): SoapCall = call("GetPositionInfo")

    fun transportInfo(): SoapCall = call("GetTransportInfo")

    fun position(response: String): CastPosition? {
        val root = Xml.parse(response) ?: return null
        val position = Xml.descendantText(root, "RelTime")?.let(::parseTime) ?: return null

        return CastPosition(position, Xml.descendantText(root, "TrackDuration")?.let(::parseTime) ?: 0)
    }

    fun state(response: String): CastState? = Xml.parse(response)?.let { CastState.fromWire(Xml.descendantText(it, "CurrentTransportState")) }

    /** The DIDL-Lite description TVs show as the title, and use to pick a player. */
    fun metadata(url: String, title: String, mime: String, size: Long? = null): String {
        val kind = CastKind.of(mime) ?: CastKind.VIDEO
        val sizeAttribute = size?.takeIf { it >= 0 }?.let { " size=\"$it\"" }.orEmpty()

        return "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" " +
            "xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\">" +
            "<item id=\"0\" parentID=\"-1\" restricted=\"1\">" +
            "<dc:title>${Xml.escape(title)}</dc:title>" +
            "<upnp:class>${kind.upnpClass}</upnp:class>" +
            "<res protocolInfo=\"http-get:*:${Xml.escape(mime)}:*\"$sizeAttribute>${Xml.escape(url)}</res>" +
            "</item></DIDL-Lite>"
    }

    /** "1:02:03" for 3,723,000 ms. */
    fun time(ms: Long): String {
        val seconds = (ms / 1000).coerceAtLeast(0)

        return "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    /** Milliseconds in "H:MM:SS" or "H:MM:SS.fff", or null for "NOT_IMPLEMENTED" and other text. */
    fun parseTime(text: String): Long? {
        val parts = text.trim().split(':')
        if (parts.size != 3) return null

        val hours = parts[0].toLongOrNull() ?: return null
        val minutes = parts[1].toLongOrNull() ?: return null
        val seconds = parts[2].toDoubleOrNull() ?: return null

        return (hours * 3600 + minutes * 60) * 1000 + (seconds * 1000).toLong()
    }

    private fun call(action: String, vararg arguments: Pair<String, String>) = SoapCall(SERVICE, action, listOf("InstanceID" to "0") + arguments)
}

/** The RenderingControl service: the TV's volume, from 0 to 100. */
object RenderingControl {
    const val SERVICE = "urn:schemas-upnp-org:service:RenderingControl:1"
    const val SERVICE_PREFIX = "urn:schemas-upnp-org:service:RenderingControl:"

    fun setVolume(volume: Int): SoapCall = call("SetVolume", "DesiredVolume" to volume.coerceIn(0, 100).toString())

    fun getVolume(): SoapCall = call("GetVolume")

    fun volume(response: String): Int? = Xml.parse(response)?.let { Xml.descendantText(it, "CurrentVolume")?.trim()?.toIntOrNull() }

    private fun call(action: String, vararg arguments: Pair<String, String>) =
        SoapCall(SERVICE, action, listOf("InstanceID" to "0", "Channel" to "Master") + arguments)
}

/** The part of a file asked for by an HTTP Range header. [end] is inclusive. */
data class ByteRange(val start: Long, val end: Long) {
    val length: Long get() = end - start + 1

    /** False when the range starts past the end of the file. */
    val isSatisfiable: Boolean get() = start <= end

    companion object {
        /** Null when there is no single byte range to honour, so the whole file is sent. */
        fun parse(header: String?, size: Long): ByteRange? {
            val spec = header?.trim()?.takeIf { it.startsWith("bytes=", ignoreCase = true) }?.substring(6)?.trim() ?: return null
            if (',' in spec) return null

            val dash = spec.indexOf('-')
            if (dash < 0) return null

            val first = spec.substring(0, dash).trim()
            val last = spec.substring(dash + 1).trim()

            if (first.isEmpty()) {
                val suffix = last.toLongOrNull()?.takeIf { it > 0 } ?: return null
                return ByteRange((size - suffix).coerceAtLeast(0), size - 1)
            }

            val start = first.toLongOrNull() ?: return null
            val asked = if (last.isEmpty()) size - 1 else last.toLongOrNull() ?: return null
            if (start >= size) return ByteRange(start, start - 1)
            if (asked < start) return null

            return ByteRange(start, minOf(asked, size - 1))
        }
    }
}

/** The request line and headers of an HTTP request, with header names in lower case. */
data class HttpRequestHead(val method: String, val path: String, val headers: Map<String, String>) {
    companion object {
        fun parse(head: String): HttpRequestHead? {
            val lines = head.split("\r\n", "\n")
            val parts = lines.firstOrNull()?.split(' ')?.takeIf { it.size >= 2 } ?: return null

            val headers = lines.drop(1).mapNotNull { line ->
                val colon = line.indexOf(':')
                if (colon <= 0) null else line.substring(0, colon).trim().lowercase() to line.substring(colon + 1).trim()
            }.toMap()

            return HttpRequestHead(parts[0].uppercase(), parts[1], headers)
        }
    }
}

/** Namespace-blind lookups over a parsed XML document. */
internal object Xml {
    fun parse(text: String): Element? = runCatching {
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        }

        factory.newDocumentBuilder().parse(text.trim().byteInputStream()).documentElement
    }.getOrNull()

    fun children(element: Element, name: String): List<Element> =
        (0 until element.childNodes.length).map { element.childNodes.item(it) }
            .filterIsInstance<Element>()
            .filter { it.name == name }

    fun child(element: Element, name: String): Element? = children(element, name).firstOrNull()

    fun text(element: Element, name: String): String? = child(element, name)?.textContent?.trim()?.takeIf { it.isNotEmpty() }

    fun descendants(element: Element, name: String): List<Element> {
        val found = mutableListOf<Element>()

        fun walk(node: Node) {
            for (i in 0 until node.childNodes.length) {
                val child = node.childNodes.item(i) as? Element ?: continue
                if (child.name == name) found += child
                walk(child)
            }
        }

        walk(element)

        return found
    }

    fun descendantText(element: Element, name: String): String? = descendants(element, name).firstOrNull()?.textContent

    fun escape(text: String): String = buildString {
        for (c in text) {
            when (c) {
                '&' -> append("&amp;")
                '<' -> append("&lt;")
                '>' -> append("&gt;")
                '"' -> append("&quot;")
                '\'' -> append("&apos;")
                else -> append(c)
            }
        }
    }

    private val Element.name: String get() = localName ?: tagName.substringAfter(':')
}
