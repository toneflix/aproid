package com.toneflix.flyylink

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/**
 * A small card in the corner of the TV, over whatever is on screen, that goes away by itself.
 * Without "Display over other apps" it falls back to a plain toast.
 */
class TvPopup private constructor(context: Context) {
    private val context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val windows = context.getSystemService(WindowManager::class.java)
    private var shown: View? = null

    fun show(label: String, title: String, text: String) = main.post {
        if (!Settings.canDrawOverlays(context)) {
            Toast.makeText(context, listOf(title, text).filter { it.isNotBlank() }.joinToString(": "), Toast.LENGTH_LONG).show()
            return@post
        }

        hide()
        val card = card(label, title, text)
        runCatching { windows.addView(card, layout()) }.onSuccess {
            shown = card
            card.animate().alpha(1f).translationX(0f).setDuration(ANIMATION_MS).start()
            main.postDelayed({ if (shown === card) hide() }, SHOW_MS)
        }
    }

    private fun hide() {
        val card = shown ?: return
        shown = null

        card.animate().alpha(0f).setDuration(ANIMATION_MS).withEndAction { runCatching { windows.removeView(card) } }.start()
    }

    private fun card(label: String, title: String, text: String): View {
        val icon = ImageView(context).apply {
            setImageResource(R.mipmap.ic_launcher)
            layoutParams = LinearLayout.LayoutParams(dp(44), dp(44)).apply { marginEnd = dp(16) }
        }
        val lines = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(line(label, 13f, LABEL_COLOR, bold = false, maxLines = 1))
            if (title.isNotBlank()) addView(line(title, 17f, TITLE_COLOR, bold = true, maxLines = 1))
            if (text.isNotBlank()) addView(line(text, 15f, TEXT_COLOR, bold = false, maxLines = 3))
        }

        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                cornerRadius = dp(22).toFloat()
                setColor(BACKGROUND)
                setStroke(dp(1), BORDER)
            }
            setPadding(dp(20), dp(16), dp(24), dp(16))
            elevation = dp(8).toFloat()
            alpha = 0f
            translationX = dp(40).toFloat()
            addView(icon)
            addView(lines)
        }
    }

    private fun line(value: String, size: Float, color: Int, bold: Boolean, maxLines: Int) = TextView(context).apply {
        text = value
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
        setTextColor(color)
        if (bold) typeface = Typeface.DEFAULT_BOLD
        this.maxLines = maxLines
        ellipsize = TextUtils.TruncateAt.END
    }

    private fun layout() = WindowManager.LayoutParams(
        dp(420),
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.END
        x = dp(48)
        y = dp(36)
    }

    private fun dp(value: Int): Int = (value * context.resources.displayMetrics.density).toInt()

    companion object {
        @Volatile private var shared: TvPopup? = null

        /** One popup for the whole app, so a new card replaces the last instead of stacking. */
        fun of(context: Context): TvPopup = shared ?: synchronized(this) { shared ?: TvPopup(context).also { shared = it } }

        private const val SHOW_MS = 6_000L
        private const val ANIMATION_MS = 220L

        private const val BACKGROUND = 0xF01E1C18.toInt()
        private const val BORDER = 0x33F6C101
        private const val LABEL_COLOR = 0xFFF6C101.toInt()
        private const val TITLE_COLOR = 0xFFF3F0E8.toInt()
        private const val TEXT_COLOR = 0xFFB1AB9C.toInt()
    }
}
