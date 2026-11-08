package com.toneflix.aproid

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Surface
import android.view.WindowManager
import com.toneflix.aproid.protocol.Screen
import com.toneflix.aproid.protocol.ScreenFrame
import java.io.InputStream
import java.util.concurrent.LinkedBlockingQueue
import kotlin.concurrent.thread
import kotlin.math.roundToInt

/**
 * Records the screen into H.264 and streams it to the Mac over a payload connection.
 * The encoder restarts at the new size when the phone rotates; the stream carries the new settings.
 */
class ScreenService : Service() {
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var encoder: Encoder? = null
    private var frames: FrameQueue? = null
    private var deviceId: String? = null
    private var request: ScreenPlugin.Pending? = null
    private var orientation = Configuration.ORIENTATION_UNDEFINED
    private val main = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        val pending = ScreenPlugin.pending
        if (intent == null) return START_NOT_STICKY
        val resultData = intent.extraData()
        if (pending == null || resultData == null || projection != null) return START_NOT_STICKY

        // Android requires the foreground service before the recording can begin.
        val device = DeviceStore.find(pending.deviceId)
        val shown = notification(device?.name ?: "")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, shown, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, shown)
        }

        if (device == null || !device.isPaired) {
            stopSelf()
            return START_NOT_STICKY
        }

        val manager = getSystemService(MediaProjectionManager::class.java)
        val projection = manager.getMediaProjection(intent.getIntExtra(EXTRA_RESULT, 0), resultData) ?: run {
            stopSelf()
            return START_NOT_STICKY
        }
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                main.post { stopSelf() }
            }
        }, main)

        this.projection = projection
        this.deviceId = device.id
        this.request = pending
        orientation = resources.configuration.orientation
        isRunning = true

        val queue = FrameQueue()
        frames = queue
        val (width, height) = videoSize(pending.maxSize)

        // Encoding starts once the Mac connects, so the first frame it gets is the settings and a key frame.
        val offered = device.sendWithPayload(Screen.started(width, height), Screen.STREAM, open = {
            main.post { startEncoding(width, height) }
            queue.stream
        }) { error ->
            Log.i(TAG, "Screen stream ended: ${error?.message ?: "closed"}")
            main.post { stopSelf() }
        }
        if (!offered) stopSelf()

        return START_NOT_STICKY
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)

        if (newConfig.orientation == orientation || encoder == null) return
        orientation = newConfig.orientation

        // Wait a moment so the display reports its rotated size.
        main.postDelayed({
            val request = request ?: return@postDelayed
            val (width, height) = videoSize(request.maxSize)
            startEncoding(width, height)
        }, 300)
    }

    override fun onDestroy() {
        isRunning = false
        encoder?.stop()
        encoder = null
        display?.release()
        display = null
        projection?.stop()
        projection = null
        frames?.close()
        frames = null
        deviceId?.let { id -> DeviceStore.find(id)?.let { DeviceStore.send(it, Screen.stopped()) } }
        super.onDestroy()
    }

    /** Starts (or restarts, after a rotation) the encoder and points the recording at it. */
    private fun startEncoding(width: Int, height: Int) {
        val projection = projection ?: return
        val queue = frames ?: return
        val request = request ?: return

        val previous = encoder
        val next = runCatching { Encoder(width, height, request.bitrate, queue) }.getOrElse {
            Log.w(TAG, "Could not start the encoder", it)
            stopSelf()
            return
        }
        encoder = next

        val density = resources.displayMetrics.densityDpi
        val current = display
        if (current == null) {
            display = projection.createVirtualDisplay(
                "Aproid",
                width,
                height,
                density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                next.surface,
                null,
                null,
            )
        } else {
            current.resize(width, height, density)
            current.surface = next.surface
        }

        // Only now that the recording points at the new encoder can the old one go.
        previous?.stop()
    }

    /** The screen's size scaled so its long side fits [maxSize], in multiples of 16 as encoders like. */
    private fun videoSize(maxSize: Int): Pair<Int, Int> {
        val windows = getSystemService(WindowManager::class.java)
        val (realWidth, realHeight) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            windows.maximumWindowMetrics.bounds.let { it.width() to it.height() }
        } else {
            val metrics = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            windows.defaultDisplay.getRealMetrics(metrics)
            metrics.widthPixels to metrics.heightPixels
        }

        val scale = minOf(1.0, maxSize.toDouble() / maxOf(realWidth, realHeight))
        fun fit(side: Int) = ((side * scale / 16).roundToInt() * 16).coerceAtLeast(16)

        return fit(realWidth) to fit(realHeight)
    }

    private fun notification(macName: String): Notification {
        val stop = PendingIntent.getService(
            this, 0, Intent(this, ScreenService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE,
        )

        return Notification.Builder(this, ScreenPlugin.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_slideshow)
            .setContentTitle(getString(R.string.screen_mirroring, macName))
            .setContentText(getString(R.string.screen_mirroring_hint))
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.screen_stop), stop).build())
            .build()
    }

    private fun Intent.extraData(): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            getParcelableExtra(EXTRA_DATA)
        }

    /** One H.264 encoder fed by a surface, with a thread that moves its output into the stream. */
    private class Encoder(width: Int, height: Int, bitrate: Int, private val queue: FrameQueue) {
        private val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        val surface: Surface
        @Volatile private var running = true
        private var skipping = false

        init {
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_FRAME_RATE, 60)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
                // A still screen makes no new frames; repeat the last one so the Mac never waits long.
                setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 100_000)
                setInteger(MediaFormat.KEY_PRIORITY, 0)
                setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
                setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel41)
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            surface = codec.createInputSurface()
            codec.start()

            thread(name = "aproid-screen", isDaemon = true) { drain() }
        }

        private fun drain() {
            val info = MediaCodec.BufferInfo()

            // The codec throws once it is stopped, which ends the loop.
            runCatching {
                while (running) {
                    val index = codec.dequeueOutputBuffer(info, 100_000)
                    if (index < 0) continue

                    val buffer = codec.getOutputBuffer(index)
                    if (buffer != null && info.size > 0) {
                        val bytes = ByteArray(info.size)
                        buffer.position(info.offset)
                        buffer.get(bytes)
                        send(bytes, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                }
            }
        }

        /** Drops frames while the Wi-Fi can't keep up, then starts again cleanly from a key frame. */
        private fun send(bytes: ByteArray, info: MediaCodec.BufferInfo) {
            var flags = 0
            if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) flags = flags or ScreenFrame.CONFIG
            if (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0) flags = flags or ScreenFrame.KEY
            val frame = ScreenFrame(bytes, info.presentationTimeUs, flags)

            if (!frame.isConfig && queue.backlog > MAX_BACKLOG && !skipping) {
                skipping = true
                runCatching { codec.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) }) }
            }
            if (skipping && frame.isKey) skipping = false
            if (skipping && !frame.isConfig) return

            queue.put(frame.header() + frame.data)
        }

        fun stop() {
            running = false
            runCatching { codec.stop() }
            runCatching { codec.release() }
            surface.release()
        }

        private companion object {
            const val MAX_BACKLOG = 20
        }
    }

    /** Frames waiting to go out, read by the payload connection as one endless stream. */
    private class FrameQueue {
        private val queue = LinkedBlockingQueue<ByteArray>()
        private val end = ByteArray(0)

        val backlog: Int get() = queue.size

        fun put(bytes: ByteArray) = queue.put(bytes)

        fun close() = queue.put(end)

        val stream: InputStream = object : InputStream() {
            private var current: ByteArray? = null
            private var position = 0

            override fun read(): Int {
                val one = ByteArray(1)
                return if (read(one, 0, 1) < 0) -1 else one[0].toInt() and 0xFF
            }

            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                var chunk = current
                if (chunk == null || position >= chunk.size) {
                    chunk = queue.take()
                    if (chunk === end) {
                        queue.put(end)
                        return -1
                    }
                    current = chunk
                    position = 0
                }

                val count = minOf(length, chunk.size - position)
                System.arraycopy(chunk, position, buffer, offset, count)
                position += count
                return count
            }
        }
    }

    companion object {
        private const val TAG = "AproidScreen"
        private const val NOTIFICATION_ID = 5
        private const val ACTION_STOP = "com.toneflix.aproid.screen.STOP"
        private const val EXTRA_RESULT = "result"
        private const val EXTRA_DATA = "data"

        @Volatile var isRunning = false
            private set

        fun start(context: Context, resultCode: Int, data: Intent) {
            val intent = Intent(context, ScreenService::class.java)
                .putExtra(EXTRA_RESULT, resultCode)
                .putExtra(EXTRA_DATA, data)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ScreenService::class.java))
        }
    }
}
