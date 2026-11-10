package com.toneflix.aproid

import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import com.toneflix.aproid.protocol.ScreenInput
import java.text.BreakIterator

/**
 * The text field that has focus, edited the way a keyboard would: at the cursor, over the selection,
 * and moved by character, word or line. Android lets an accessibility service set a field's text and
 * selection but not press keys, so every key becomes one of those.
 */
class FocusedField(private val node: AccessibilityNodeInfo) {
    private val text = if (node.isShowingHintText) "" else node.text?.toString().orEmpty()
    private val anchor = node.textSelectionStart.takeIf { it in 0..text.length } ?: text.length
    private val caret = node.textSelectionEnd.takeIf { it in 0..text.length } ?: text.length
    private val from = minOf(anchor, caret)
    private val to = maxOf(anchor, caret)

    fun type(input: String) = replace(from, to, input)

    /** Edits or moves for one non-text key. Returns false for keys that are not about text. */
    fun press(key: String, select: Boolean): Boolean {
        when (key) {
            ScreenInput.DELETE -> if (from != to) replace(from, to, "") else replace(back(from), from, "")
            ScreenInput.DELETE_FORWARD -> if (from != to) replace(from, to, "") else replace(from, ahead(from), "")
            ScreenInput.DELETE_WORD -> if (from != to) replace(from, to, "") else replace(wordStart(from), from, "")
            ScreenInput.ENTER -> enter()
            ScreenInput.TAB -> node.focusSearch(if (select) View.FOCUS_BACKWARD else View.FOCUS_FORWARD)
                ?.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            ScreenInput.SELECT_ALL -> select(0, text.length)
            ScreenInput.COPY -> node.performAction(AccessibilityNodeInfo.ACTION_COPY)
            ScreenInput.CUT -> node.performAction(AccessibilityNodeInfo.ACTION_CUT)
            ScreenInput.LEFT -> move(if (!select && from != to) from else back(caret), select)
            ScreenInput.RIGHT -> move(if (!select && from != to) to else ahead(caret), select)
            ScreenInput.WORD_LEFT -> move(wordStart(caret), select)
            ScreenInput.WORD_RIGHT -> move(wordEnd(caret), select)
            ScreenInput.LINE_START -> move(lineStart(caret), select)
            ScreenInput.LINE_END -> move(lineEnd(caret), select)
            ScreenInput.UP -> move(lineAbove(caret), select)
            ScreenInput.DOWN -> move(lineBelow(caret), select)
            else -> return false
        }

        return true
    }

    private fun enter() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !node.isMultiLine) {
            node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
        } else {
            type("\n")
        }
    }

    private fun replace(start: Int, end: Int, input: String) {
        val arguments = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text.replaceRange(start, end, input))
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)

        select(start + input.length, start + input.length)
    }

    private fun move(target: Int, extend: Boolean) = if (extend) select(anchor, target) else select(target, target)

    private fun select(start: Int, end: Int) {
        val arguments = Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, start)
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, end)
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, arguments)
    }

    private fun back(index: Int) = if (index > 0) text.offsetByCodePoints(index, -1) else 0

    private fun ahead(index: Int) = if (index < text.length) text.offsetByCodePoints(index, 1) else text.length

    private fun wordStart(index: Int): Int {
        var position = index
        while (position > 0 && text[position - 1].isWhitespace()) position--
        if (position == 0) return 0

        val boundary = words().preceding(position)
        return if (boundary == BreakIterator.DONE) 0 else boundary
    }

    private fun wordEnd(index: Int): Int {
        var position = index
        while (position < text.length && text[position].isWhitespace()) position++
        if (position >= text.length) return text.length

        val boundary = words().following(position)
        return if (boundary == BreakIterator.DONE) text.length else boundary
    }

    private fun words() = BreakIterator.getWordInstance().apply { setText(text) }

    private fun lineStart(index: Int) = text.lastIndexOf('\n', index - 1) + 1

    private fun lineEnd(index: Int) = text.indexOf('\n', index).let { if (it < 0) text.length else it }

    private fun lineAbove(index: Int): Int {
        val start = lineStart(index)
        if (start == 0) return 0

        val above = lineStart(start - 1)
        return minOf(above + (index - start), start - 1)
    }

    private fun lineBelow(index: Int): Int {
        val end = lineEnd(index)
        if (end == text.length) return text.length

        val below = end + 1
        return minOf(below + (index - lineStart(index)), lineEnd(below))
    }
}
