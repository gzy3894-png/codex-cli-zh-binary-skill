package com.rk.terminal.ui.screens.terminal

import android.content.res.Configuration
import android.content.res.Resources
import android.media.MediaPlayer
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.blankj.utilcode.util.ClipboardUtils
import com.blankj.utilcode.util.KeyboardUtils
import com.rk.libcommons.child
import com.rk.settings.Settings
import com.rk.terminal.ui.activities.terminal.MainActivity
import com.rk.terminal.ui.screens.terminal.virtualkeys.SpecialButton
import com.termux.terminal.TerminalEmulator
import com.termux.terminal.TerminalSession
import com.termux.terminal.TerminalSessionClient
import com.termux.view.TerminalView
import com.termux.view.TerminalViewClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.FileOutputStream

object TerminalRenderPerformanceMetrics {
    data class Snapshot(
        val renderRequests: Long,
        val renderFrames: Long,
        val coalescedRequests: Long,
        val burstMode: Boolean,
        val lastFrameMs: Long
    )

    private val lock = Any()
    private var renderRequests = 0L
    private var renderFrames = 0L
    private var coalescedRequests = 0L
    private var burstMode = false
    private var lastFrameMs = 0L

    fun recordRequest(coalesced: Boolean) {
        synchronized(lock) {
            renderRequests += 1
            if (coalesced) {
                coalescedRequests += 1
                burstMode = true
            }
        }
    }

    fun recordFrame(durationMs: Long, burst: Boolean) {
        synchronized(lock) {
            renderFrames += 1
            lastFrameMs = durationMs.coerceAtLeast(0L)
            burstMode = burst
        }
    }

    fun snapshot(): Snapshot = synchronized(lock) {
        Snapshot(
            renderRequests = renderRequests,
            renderFrames = renderFrames,
            coalescedRequests = coalescedRequests,
            burstMode = burstMode,
            lastFrameMs = lastFrameMs
        )
    }
}

class TerminalBackEnd(
    private val terminal: TerminalView,
    private val activity: MainActivity,
    private val coroutineScope: CoroutineScope = activity.lifecycleScope
) : TerminalViewClient, TerminalSessionClient {

    private val terminalViewModel by lazy { ViewModelProvider(activity)[TerminalViewModel::class.java] }
    private val screenUpdateLock = Any()
    private var screenUpdateScheduled = false
    private var pendingScreenUpdateDelayMs = TEXT_UPDATE_COALESCE_DELAY_MS
    @Volatile private var lastUserInputUptimeMs = 0L

    private val screenUpdateRunnable = Runnable {
        val burst = synchronized(screenUpdateLock) {
            val wasBurst = pendingScreenUpdateDelayMs > USER_INPUT_COALESCE_DELAY_MS
            screenUpdateScheduled = false
            wasBurst
        }
        renderScreenUpdate(burstMode = burst)
    }

    private val scheduleScreenUpdateRunnable = Runnable {
        val delayMs = synchronized(screenUpdateLock) {
            if (screenUpdateScheduled) pendingScreenUpdateDelayMs else null
        } ?: return@Runnable
        terminal.removeCallbacks(screenUpdateRunnable)
        terminal.postOnAnimationDelayed(screenUpdateRunnable, delayMs)
    }

    override fun onTextChanged(changedSession: TerminalSession) {
        if (changedSession != terminal.currentSession) return
        val coalesced = scheduleScreenUpdate(
            delayMs = if (isRecentUserInput()) {
                USER_INPUT_COALESCE_DELAY_MS
            } else {
                TEXT_UPDATE_COALESCE_DELAY_MS
            }
        )
        TerminalRenderPerformanceMetrics.recordRequest(coalesced)
    }

    override fun onTitleChanged(changedSession: TerminalSession) {}
    override fun onSessionFinished(finishedSession: TerminalSession) {}

    override fun onCopyTextToClipboard(session: TerminalSession, text: String) {
        ClipboardUtils.copyText("Terminal", text)
    }

    override fun onPasteTextFromClipboard(session: TerminalSession?) {
        val clip = ClipboardUtils.getText().toString()
        if (clip.trim().isNotEmpty() && terminal.mEmulator != null) {
            noteUserInput()
            terminal.mEmulator.paste(clip)
        }
    }

    override fun onBell(session: TerminalSession) {
        if (!Settings.bell) return
        
        coroutineScope.launch {
            val bellFile = activity.cacheDir.child("bell.oga")
            if (!bellFile.exists()) {
                withContext(Dispatchers.IO) {
                    activity.assets.open("bell.oga").use { input ->
                        FileOutputStream(bellFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                }
            }

            MediaPlayer().apply {
                setOnCompletionListener { it?.release() }
                setDataSource(bellFile.absolutePath)
                prepare()
                start()
            }
        }
    }

    override fun onColorsChanged(session: TerminalSession) {}
    override fun onTerminalCursorStateChange(state: Boolean) {}
    override fun getTerminalCursorStyle(): Int = TerminalEmulator.DEFAULT_TERMINAL_CURSOR_STYLE

    override fun logError(tag: String?, message: String?) { Log.e(tag ?: "Terminal", message ?: "") }
    override fun logWarn(tag: String?, message: String?) { Log.w(tag ?: "Terminal", message ?: "") }
    override fun logInfo(tag: String?, message: String?) { Log.i(tag ?: "Terminal", message ?: "") }
    override fun logDebug(tag: String?, message: String?) { Log.d(tag ?: "Terminal", message ?: "") }
    override fun logVerbose(tag: String?, message: String?) { Log.v(tag ?: "Terminal", message ?: "") }

    override fun logStackTraceWithMessage(tag: String?, message: String?, e: Exception?) {
        Log.e(tag ?: "Terminal", message ?: "", e)
    }

    override fun logStackTrace(tag: String?, e: Exception?) {
        Log.e(tag ?: "Terminal", "Stack trace", e)
    }

    override fun onScale(scale: Float): Float {
        val fontScale = scale.coerceIn(10f, 45f)
        terminal.setTextSize(fontScale.toInt())
        requestImmediateScreenRefresh()
        return fontScale
    }

    private val isHardwareKeyboardConnected: Boolean
        get() = Resources.getSystem().configuration.keyboard != Configuration.KEYBOARD_NOKEYS

    override fun onSingleTapUp(e: MotionEvent) {
        if (!(isHardwareKeyboardConnected && Settings.hide_soft_keyboard_if_hwd)) {
            showSoftInput()
        }
    }

    override fun shouldBackButtonBeMappedToEscape(): Boolean = false
    override fun shouldEnforceCharBasedInput(): Boolean = Settings.input_mode != 1
    override fun shouldUseCtrlSpaceWorkaround(): Boolean = true
    override fun isTerminalViewSelected(): Boolean = true
    override fun copyModeChanged(copyMode: Boolean) {}

    override fun onKeyDown(keyCode: Int, e: KeyEvent, session: TerminalSession): Boolean {
        noteUserInput()
        if (KeyShortcutHandler.handle(keyCode, e, activity)) return true
        
        if (keyCode == KeyEvent.KEYCODE_ENTER && !session.isRunning) {
            val binder = activity.viewModel.sessionBinder ?: return false
            val service = binder.getService()
            val currentId = service.currentSession.value.first
            
            binder.terminateSession(currentId)
            
            if (service.sessionList.isEmpty()) {
                activity.finish()
            } else {
                terminalViewModel.changeSession(activity, binder, service.sessionList.keys.first())
            }
            return true
        }
        return false
    }

    override fun onKeyUp(keyCode: Int, e: KeyEvent): Boolean {
        noteUserInput()
        return false
    }
    override fun onLongPress(event: MotionEvent): Boolean = false

    override fun readControlKey(): Boolean =
        terminalViewModel.virtualKeysView?.readSpecialButton(SpecialButton.CTRL, true) == true

    override fun readAltKey(): Boolean =
        terminalViewModel.virtualKeysView?.readSpecialButton(SpecialButton.ALT, true) == true

    override fun readShiftKey(): Boolean =
        terminalViewModel.virtualKeysView?.readSpecialButton(SpecialButton.SHIFT, true) == true

    override fun readFnKey(): Boolean =
        terminalViewModel.virtualKeysView?.readSpecialButton(SpecialButton.FN, true) == true

    override fun onCodePoint(codePoint: Int, ctrlDown: Boolean, session: TerminalSession): Boolean {
        noteUserInput()
        return false
    }

    override fun onEmulatorSet() {
        if (terminal.mEmulator != null) {
            terminal.setTerminalCursorBlinkerState(true, true)
            requestImmediateScreenRefresh()
        }
    }

    private fun showSoftInput() {
        terminal.requestFocus()
        KeyboardUtils.showSoftInput(terminal)
    }

    private fun noteUserInput() {
        lastUserInputUptimeMs = SystemClock.uptimeMillis()
    }

    private fun isRecentUserInput(): Boolean =
        SystemClock.uptimeMillis() - lastUserInputUptimeMs <= USER_INPUT_IMMEDIATE_WINDOW_MS

    private fun scheduleScreenUpdate(delayMs: Long): Boolean {
        val normalizedDelayMs = delayMs.coerceAtLeast(0L)
        var coalesced = false
        val shouldPostScheduler = synchronized(screenUpdateLock) {
            if (screenUpdateScheduled && pendingScreenUpdateDelayMs <= normalizedDelayMs) {
                coalesced = true
                false
            } else {
                coalesced = screenUpdateScheduled
                screenUpdateScheduled = true
                pendingScreenUpdateDelayMs = normalizedDelayMs
                true
            }
        }

        if (shouldPostScheduler) {
            terminal.post(scheduleScreenUpdateRunnable)
        }
        return coalesced
    }

    private fun requestImmediateScreenRefresh() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            cancelPendingScreenUpdate()
            renderScreenUpdate(burstMode = false)
        } else {
            terminal.post {
                cancelPendingScreenUpdate()
                renderScreenUpdate(burstMode = false)
            }
        }
    }

    private fun renderScreenUpdate(burstMode: Boolean) {
        val started = SystemClock.uptimeMillis()
        terminal.onScreenUpdated()
        TerminalRenderPerformanceMetrics.recordFrame(
            durationMs = SystemClock.uptimeMillis() - started,
            burst = burstMode
        )
    }

    private fun cancelPendingScreenUpdate() {
        synchronized(screenUpdateLock) {
            screenUpdateScheduled = false
            pendingScreenUpdateDelayMs = TEXT_UPDATE_COALESCE_DELAY_MS
        }
        terminal.removeCallbacks(scheduleScreenUpdateRunnable)
        terminal.removeCallbacks(screenUpdateRunnable)
    }

    companion object {
        private const val USER_INPUT_COALESCE_DELAY_MS = 0L
        private const val TEXT_UPDATE_COALESCE_DELAY_MS = 16L
        private const val USER_INPUT_IMMEDIATE_WINDOW_MS = 120L
    }
}
