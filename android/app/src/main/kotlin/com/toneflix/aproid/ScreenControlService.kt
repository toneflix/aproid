package com.toneflix.aproid

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.toneflix.aproid.protocol.ScreenInput

/**
 * Plays the Mac's clicks, drags and typing on the phone while its screen is mirrored.
 * Android only allows this through an accessibility service the user turns on.
 */
class ScreenControlService : AccessibilityService() {
    /** Whether the user turned the service on, and whether Android is actually running it. */
    enum class Status { OFF, STOPPED, ON }

    override fun onServiceConnected() {
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    private fun play(input: ScreenInput) {
        when (input) {
            is ScreenInput.Tap -> stroke(input.x, input.y, input.x, input.y, TAP_MS)
            is ScreenInput.LongPress -> stroke(input.x, input.y, input.x, input.y, LONG_PRESS_MS)
            is ScreenInput.Swipe -> stroke(input.x, input.y, input.toX, input.toY, input.durationMs)
            is ScreenInput.Text -> focusedField()?.type(input.text)
            is ScreenInput.Key -> key(input)
        }
    }

    /** One finger from one point to another; a tap is a stroke that doesn't move. */
    private fun stroke(x: Double, y: Double, toX: Double, toY: Double, durationMs: Long) {
        val (width, height) = screenSize()
        val path = Path().apply {
            moveTo((x * width).toFloat(), (y * height).toFloat())
            lineTo((toX * width).toFloat(), (toY * height).toFloat())
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs.coerceAtLeast(1)))
            .build()

        dispatchGesture(gesture, null, null)
    }

    private fun key(input: ScreenInput.Key) {
        when (input.key) {
            ScreenInput.BACK -> performGlobalAction(GLOBAL_ACTION_BACK)
            ScreenInput.HOME -> performGlobalAction(GLOBAL_ACTION_HOME)
            ScreenInput.RECENTS -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            ScreenInput.NOTIFICATIONS -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
            else -> focusedField()?.press(input.key, input.select)
        }
    }

    private fun focusedField() = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.let(::FocusedField)

    private fun screenSize(): Pair<Int, Int> {
        val windows = getSystemService(WindowManager::class.java)

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            windows.maximumWindowMetrics.bounds.let { it.width() to it.height() }
        } else {
            val metrics = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            windows.defaultDisplay.getRealMetrics(metrics)
            metrics.widthPixels to metrics.heightPixels
        }
    }

    companion object {
        private const val TAP_MS = 40L
        private const val LONG_PRESS_MS = 700L

        @Volatile private var instance: ScreenControlService? = null

        fun perform(input: ScreenInput) {
            val service = instance ?: return
            android.os.Handler(android.os.Looper.getMainLooper()).post { service.play(input) }
        }

        /**
         * Android stops the service when the app is updated or killed and, on many phones, keeps it switched on
         * but "Not working" until the user turns it off and on again. That shows here as [Status.STOPPED].
         */
        fun status(context: Context): Status = when {
            instance != null -> Status.ON
            isEnabled(context) -> Status.STOPPED
            else -> Status.OFF
        }

        private fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
            val me = ComponentName(context, ScreenControlService::class.java).flattenToString()
            return enabled.split(':').any { it.equals(me, ignoreCase = true) }
        }

        fun settingsIntent() = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
