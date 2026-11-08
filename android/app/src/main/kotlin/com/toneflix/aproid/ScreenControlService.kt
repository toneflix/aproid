package com.toneflix.aproid

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.os.Build
import android.os.Bundle
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
    override fun onServiceConnected() {
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    private fun play(input: ScreenInput) {
        when (input) {
            is ScreenInput.Tap -> stroke(input.x, input.y, input.x, input.y, TAP_MS)
            is ScreenInput.LongPress -> stroke(input.x, input.y, input.x, input.y, LONG_PRESS_MS)
            is ScreenInput.Swipe -> stroke(input.x, input.y, input.toX, input.toY, input.durationMs)
            is ScreenInput.Text -> type(input.text)
            is ScreenInput.Key -> key(input.key)
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

    private fun key(key: String) {
        when (key) {
            ScreenInput.BACK -> performGlobalAction(GLOBAL_ACTION_BACK)
            ScreenInput.HOME -> performGlobalAction(GLOBAL_ACTION_HOME)
            ScreenInput.RECENTS -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            ScreenInput.NOTIFICATIONS -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
            ScreenInput.ENTER -> enter()
            ScreenInput.DELETE -> editFocused { it.dropLast(1) }
        }
    }

    private fun type(text: String) = editFocused { it + text }

    /** Changes the text of the field that has focus, since there is no way to send key presses. */
    private fun editFocused(change: (String) -> String) {
        val field = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return

        // A hint shows as the text of an empty field, so don't build on it.
        val current = if (field.isShowingHintText) "" else field.text?.toString().orEmpty()
        val arguments = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, change(current))
        }
        field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
    }

    private fun enter() {
        val field = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            field.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
        } else {
            editFocused { it + "\n" }
        }
    }

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

        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
            val me = ComponentName(context, ScreenControlService::class.java).flattenToString()
            return enabled.split(':').any { it.equals(me, ignoreCase = true) }
        }

        fun settingsIntent() = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
