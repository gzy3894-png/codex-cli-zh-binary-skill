package com.rk.terminal.ui.screens.terminal

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.media.MediaPlayer
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.lifecycle.ViewModelProvider
import com.blankj.utilcode.util.ClipboardUtils
import com.blankj.utilcode.util.KeyboardUtils
import com.rk.libcommons.child
import com.rk.settings.Settings
import com.rk.terminal.ui.activities.terminal.MainActivity
import com.rk.terminal.ui.screens.settings.InputMode
import com.rk.terminal.ui.screens.terminal.virtualkeys.SpecialButton
import com.termux.terminal.TerminalEmulator
import com.termux.terminal.TerminalSession
import com.termux.terminal.TerminalSessionClient
import com.termux.view.TerminalView
import com.termux.view.TerminalViewClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.FileOutputStream
import java.lang.ref.WeakReference

object TerminalRenderPerformanceMetrics {
    data class Snapshot(
        val renderRequests: Long,
        val renderFrames: Long,
        val coalescedRequests: Long,
        val burstMode: Boolean,
        val lastFrameMs: Long,
        val avgFrameMs: Long,
        val maxFrameMs: Long,
        val lastRequestMs: Long,
        val lastRequestAgeMs: Long,
        val lastRequestToFrameMs: Long,
        val inputEvents: Long,
        val lastInputMs: Long,
        val lastInputAgeMs: Long,
        val recentWindowMs: Long,
        val recentWindowAgeMs: Long,
        val recentInputEvents: Long,
        val recentRenderRequests: Long,
        val recentCoalescedRequests: Long,
        val slowFrames16Ms: Long,
        val slowFrames32Ms: Long
    ) {
        constructor(
            renderRequests: Long,
            renderFrames: Long,
            coalescedRequests: Long,
            burstMode: Boolean,
            lastFrameMs: Long
        ) : this(
            renderRequests = renderRequests,
            renderFrames = renderFrames,
            coalescedRequests = coalescedRequests,
            burstMode = burstMode,
            lastFrameMs = lastFrameMs,
            avgFrameMs = lastFrameMs,
            maxFrameMs = lastFrameMs,
            lastRequestMs = 0L,
            lastRequestAgeMs = UNKNOWN_AGE_MS,
            lastRequestToFrameMs = UNKNOWN_AGE_MS,
            inputEvents = 0L,
            lastInputMs = 0L,
            lastInputAgeMs = UNKNOWN_AGE_MS,
            recentWindowMs = RECENT_WINDOW_MS,
            recentWindowAgeMs = 0L,
            recentInputEvents = 0L,
            recentRenderRequests = 0L,
            recentCoalescedRequests = 0L,
            slowFrames16Ms = 0L,
            slowFrames32Ms = 0L
        )
    }

    private val lock = Any()
    private var renderRequests = 0L
    private var renderFrames = 0L
    private var coalescedRequests = 0L
    private var inputEvents = 0L
    private var burstMode = false
    private var lastFrameMs = 0L
    private var totalFrameMs = 0L
    private var maxFrameMs = 0L
    private var slowFrames16Ms = 0L
    private var slowFrames32Ms = 0L
    private var lastRequestMs = 0L
    private var lastInputMs = 0L
    private var lastRequestToFrameMs = UNKNOWN_AGE_MS
    private var recentWindowStartedMs = 0L
    private var recentInputEvents = 0L
    private var recentRenderRequests = 0L
    private var recentCoalescedRequests = 0L

    fun recordRequest(coalesced: Boolean) {
        val now = SystemClock.uptimeMillis()
        synchronized(lock) {
            rotateRecentWindowLocked(now)
            renderRequests += 1
            recentRenderRequests += 1
            lastRequestMs = now
            if (coalesced) {
                coalescedRequests += 1
                recentCoalescedRequests += 1
                burstMode = true
            }
        }
    }

    fun recordInput(uptimeMs: Long = SystemClock.uptimeMillis()) {
        synchronized(lock) {
            rotateRecentWindowLocked(uptimeMs)
            inputEvents += 1
            recentInputEvents += 1
            lastInputMs = uptimeMs
        }
    }

    fun recordFrame(durationMs: Long, burst: Boolean) {
        val now = SystemClock.uptimeMillis()
        synchronized(lock) {
            rotateRecentWindowLocked(now)
            val normalizedDurationMs = durationMs.coerceAtLeast(0L)
            renderFrames += 1
            lastFrameMs = normalizedDurationMs
            totalFrameMs += normalizedDurationMs
            maxFrameMs = maxOf(maxFrameMs, normalizedDurationMs)
            if (normalizedDurationMs > FRAME_BUDGET_MS) slowFrames16Ms += 1
            if (normalizedDurationMs > SLOW_FRAME_MS) slowFrames32Ms += 1
            lastRequestToFrameMs = ageSinceLocked(now, lastRequestMs)
            burstMode = burst
        }
    }

    fun snapshot(): Snapshot {
        val now = SystemClock.uptimeMillis()
        return synchronized(lock) {
            rotateRecentWindowLocked(now)
            val avgFrameMs = if (renderFrames > 0) {
                totalFrameMs / renderFrames
            } else {
                0L
            }
            val lastRequestAgeMs = ageSinceLocked(now, lastRequestMs)
            val lastInputAgeMs = ageSinceLocked(now, lastInputMs)
            val recentWindowAgeMs = if (recentWindowStartedMs > 0L) {
                (now - recentWindowStartedMs).coerceAtLeast(0L)
            } else {
                0L
            }
            Snapshot(
                renderRequests = renderRequests,
                renderFrames = renderFrames,
                coalescedRequests = coalescedRequests,
                burstMode = burstMode,
                lastFrameMs = lastFrameMs,
                avgFrameMs = avgFrameMs,
                maxFrameMs = maxFrameMs,
                lastRequestMs = lastRequestMs,
                lastRequestAgeMs = lastRequestAgeMs,
                lastRequestToFrameMs = lastRequestToFrameMs,
                inputEvents = inputEvents,
                lastInputMs = lastInputMs,
                lastInputAgeMs = lastInputAgeMs,
                recentWindowMs = RECENT_WINDOW_MS,
                recentWindowAgeMs = recentWindowAgeMs,
                recentInputEvents = recentInputEvents,
                recentRenderRequests = recentRenderRequests,
                recentCoalescedRequests = recentCoalescedRequests,
                slowFrames16Ms = slowFrames16Ms,
                slowFrames32Ms = slowFrames32Ms
            )
        }
    }

    private fun rotateRecentWindowLocked(now: Long) {
        if (recentWindowStartedMs <= 0L) {
            recentWindowStartedMs = now
            return
        }
        if (now - recentWindowStartedMs > RECENT_WINDOW_MS) {
            recentWindowStartedMs = now
            recentInputEvents = 0L
            recentRenderRequests = 0L
            recentCoalescedRequests = 0L
        }
    }

    private fun ageSinceLocked(now: Long, uptimeMs: Long): Long {
        return if (uptimeMs > 0L) {
            (now - uptimeMs).coerceAtLeast(0L)
        } else {
            UNKNOWN_AGE_MS
        }
    }

    private const val RECENT_WINDOW_MS = 2_000L
    private const val FRAME_BUDGET_MS = 16L
    private const val SLOW_FRAME_MS = 32L
    private const val UNKNOWN_AGE_MS = -1L
}

class TerminalBackEnd(
    terminal: TerminalView,
    activity: MainActivity,
    private val sessionId: String? = null
) : TerminalViewClient, TerminalSessionClient {

    private val terminalRef = WeakReference(terminal)
    private val activityRef = WeakReference(activity)
    private val appContext: Context = activity.applicationContext
    private val backendJob = SupervisorJob()
    private val coroutineScope = CoroutineScope(backendJob + Dispatchers.Main.immediate)
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
        val terminal = terminalRef.get() ?: return@Runnable
        terminal.removeCallbacks(screenUpdateRunnable)
        terminal.postOnAnimationDelayed(screenUpdateRunnable, delayMs)
    }

    override fun onTextChanged(changedSession: TerminalSession) {
        val terminal = terminalRef.get() ?: return
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
    override fun onSessionFinished(finishedSession: TerminalSession) {
        cancelPendingScreenUpdate()
        cleanupSessionTempDir()
        backendJob.cancel()
    }

    override fun onCopyTextToClipboard(session: TerminalSession, text: String) {
        ClipboardUtils.copyText("Terminal", text)
    }

    override fun onPasteTextFromClipboard(session: TerminalSession?) {
        val terminal = terminalRef.get() ?: return
        val clip = ClipboardUtils.getText().toString()
        if (clip.trim().isNotEmpty() && terminal.mEmulator != null) {
            noteUserInput()
            terminal.mEmulator.paste(clip)
        }
    }

    override fun onBell(session: TerminalSession) {
        if (!Settings.bell) return
        
        coroutineScope.launch {
            val bellFile = appContext.cacheDir.child("bell.oga")
            if (!bellFile.exists()) {
                withContext(Dispatchers.IO) {
                    appContext.assets.open("bell.oga").use { input ->
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
        terminalRef.get()?.let {
            it.setTextSize(fontScale.toInt())
            requestImmediateScreenRefresh()
        }
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
    // Stock termux TerminalView only exposes a boolean:
    // true  → TYPE_TEXT_VARIATION_VISIBLE_PASSWORD (Samsung char-based workaround)
    // false → TYPE_NULL (preferred; key events / live echo for most IMEs)
    // DEFAULT and TYPE_NULL both use TYPE_NULL so typing is visible char-by-char.
    // Only the explicit "Legacy Workaround" setting opts into VISIBLE_PASSWORD.
    override fun shouldEnforceCharBasedInput(): Boolean =
        Settings.input_mode == InputMode.VISIBLE_PASSWORD
    override fun shouldUseCtrlSpaceWorkaround(): Boolean = true
    override fun isTerminalViewSelected(): Boolean = true
    override fun copyModeChanged(copyMode: Boolean) {}

    override fun onKeyDown(keyCode: Int, e: KeyEvent, session: TerminalSession): Boolean {
        noteUserInput()
        val activity = activityRef.get() ?: return false
        if (KeyShortcutHandler.handle(keyCode, e, activity)) return true
        
        if (keyCode == KeyEvent.KEYCODE_ENTER && !session.isRunning) {
            val binder = activity.viewModel.sessionBinder ?: return false
            val service = binder.getService()
            val currentId = service.currentSession.value.first
            
            binder.terminateSession(currentId)
            
            if (service.sessionList.isEmpty()) {
                activity.finish()
            } else {
                terminalViewModel()?.changeSession(activity, binder, service.sessionList.keys.first())
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
        terminalViewModel()?.virtualKeysView?.readSpecialButton(SpecialButton.CTRL, true) == true

    override fun readAltKey(): Boolean =
        terminalViewModel()?.virtualKeysView?.readSpecialButton(SpecialButton.ALT, true) == true

    override fun readShiftKey(): Boolean =
        terminalViewModel()?.virtualKeysView?.readSpecialButton(SpecialButton.SHIFT, true) == true

    override fun readFnKey(): Boolean =
        terminalViewModel()?.virtualKeysView?.readSpecialButton(SpecialButton.FN, true) == true

    override fun onCodePoint(codePoint: Int, ctrlDown: Boolean, session: TerminalSession): Boolean {
        noteUserInput()
        return false
    }

    override fun onEmulatorSet() {
        val terminal = terminalRef.get() ?: return
        if (terminal.mEmulator != null) {
            terminal.setTerminalCursorBlinkerState(true, true)
            requestImmediateScreenRefresh()
        }
    }

    private fun showSoftInput() {
        val terminal = terminalRef.get() ?: return
        terminal.requestFocus()
        KeyboardUtils.showSoftInput(terminal)
    }

    private fun noteUserInput() {
        lastUserInputUptimeMs = SystemClock.uptimeMillis()
        TerminalRenderPerformanceMetrics.recordInput(lastUserInputUptimeMs)
    }

    private fun isRecentUserInput(): Boolean =
        SystemClock.uptimeMillis() - lastUserInputUptimeMs <= USER_INPUT_IMMEDIATE_WINDOW_MS

    private fun scheduleScreenUpdate(delayMs: Long): Boolean {
        val terminal = terminalRef.get() ?: return false
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
        val terminal = terminalRef.get() ?: return
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
        val terminal = terminalRef.get() ?: return
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
        terminalRef.get()?.let { terminal ->
            terminal.removeCallbacks(scheduleScreenUpdateRunnable)
            terminal.removeCallbacks(screenUpdateRunnable)
        }
    }

    private fun terminalViewModel(): TerminalViewModel? =
        activityRef.get()?.let { ViewModelProvider(it)[TerminalViewModel::class.java] }

    private fun cleanupSessionTempDir() {
        val id = sessionId ?: return
        runCatching {
            MkSession.sessionTempDir(appContext, id).takeIf { it.exists() }?.deleteRecursively()
        }
    }

    companion object {
        private const val USER_INPUT_COALESCE_DELAY_MS = 0L
        private const val TEXT_UPDATE_COALESCE_DELAY_MS = 16L
        private const val USER_INPUT_IMMEDIATE_WINDOW_MS = 120L
    }
}
