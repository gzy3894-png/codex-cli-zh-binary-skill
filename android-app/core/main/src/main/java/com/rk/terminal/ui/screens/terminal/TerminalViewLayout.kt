package com.rk.terminal.ui.screens.terminal

import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.widget.doOnTextChanged
import com.rk.libcommons.child
import com.rk.libcommons.dpToPx
import com.rk.libcommons.localDir
import com.rk.settings.Settings
import com.rk.terminal.service.SessionService
import com.rk.terminal.session.SessionIsolation
import com.rk.terminal.session.SessionIsolationHooks
import com.rk.terminal.ui.activities.terminal.MainActivity
import com.rk.terminal.ui.screens.terminal.virtualkeys.*
import com.termux.terminal.TerminalColors
import com.termux.view.TerminalView
import java.io.FileInputStream
import java.util.*

@Composable
fun TerminalViewLayout(
    viewModel: TerminalViewModel,
    mainActivity: MainActivity,
    sessionBinder: SessionService.SessionBinder,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        AndroidView(
            factory = { ctx ->
                TerminalView(ctx, null).apply {
                    viewModel.setTerminalView(this)
                    setTextSize(dpToPx(Settings.terminal_font_size.toFloat(), ctx))
                    setBackgroundColor(android.graphics.Color.TRANSPARENT)

                    val service = sessionBinder.getService()
                    SessionIsolationHooks.ensureInit(ctx)

                    // Cold restore before default "main" is created, so process death
                    // can bring back previous tabs without changing the normal first-run path.
                    var restoredIds = emptySet<String>()
                    if (service.sessionList.isEmpty()) {
                        val pending = SessionIsolationHooks.pendingRestoreIfEmpty(0)
                        pending.forEach { rec ->
                            val restoreClient = TerminalBackEnd(this, mainActivity, rec.id)
                            if (sessionBinder.getSession(rec.id) == null) {
                                sessionBinder.createSession(rec.id, restoreClient, rec.workingMode)
                            }
                            // Re-apply full restored identity after createSession preserve path.
                            SessionIsolation.onSessionCreated(
                                sessionId = rec.id,
                                workingMode = rec.workingMode,
                                agentKind = rec.agentKind,
                                preferredDisplayName = rec.displayName,
                                agentResumeId = rec.agentResumeId,
                                autoNamed = rec.autoNamed,
                                preserveExistingIdentity = false,
                            )
                        }
                        restoredIds = pending.map { it.id }.toSet()
                        if (pending.isNotEmpty()) {
                            val preferred = SessionIsolation.preferredCurrentId(pending.first().id)
                            val livePreferred = when {
                                service.sessionList.containsKey(preferred) -> preferred
                                else -> service.sessionList.keys.firstOrNull()
                            }
                            if (livePreferred != null) {
                                service.currentSession.value =
                                    livePreferred to (service.sessionList[livePreferred]
                                        ?: Settings.working_Mode)
                            }
                        }
                    }

                    // Prefer restored current; never invent a bare "main" beside restored tabs.
                    val sessionId = service.currentSession.value.first.let { current ->
                        when {
                            service.sessionList.containsKey(current) -> current
                            restoredIds.isNotEmpty() ->
                                service.sessionList.keys.firstOrNull() ?: current
                            else -> current
                        }
                    }
                    val client = TerminalBackEnd(this, mainActivity, sessionId)

                    val session = sessionBinder.getSession(sessionId)
                        ?: if (restoredIds.isEmpty()) {
                            sessionBinder.createSession(
                                sessionId,
                                client,
                                Settings.working_Mode
                            )
                        } else {
                            // Restore produced live tabs but preferred id missing — attach first live.
                            val fallbackId = service.sessionList.keys.first()
                            service.currentSession.value =
                                fallbackId to (service.sessionList[fallbackId] ?: Settings.working_Mode)
                            sessionBinder.getSession(fallbackId)
                                ?: sessionBinder.createSession(
                                    fallbackId,
                                    TerminalBackEnd(this, mainActivity, fallbackId),
                                    Settings.working_Mode
                                )
                        }

                    val activeId = service.currentSession.value.first
                    val activeClient =
                        if (activeId == sessionId) client
                        else TerminalBackEnd(this, mainActivity, activeId)

                    session.updateTerminalSessionClient(activeClient)
                    attachSession(session)
                    setTerminalViewClient(activeClient)
                    setTypeface(TerminalUtils.typeface)
                    SessionIsolationHooks.notifyCurrent(activeId)

                    // One-shot resume inject when UUID is known; no-op otherwise.
                    post {
                        SessionIsolationHooks.maybeInjectResume(activeId) { line ->
                            runCatching { session.write(line) }
                        }
                    }

                    post {
                        val color = TerminalUtils.getViewColor()
                        val bgColor = TerminalUtils.getBackgroundColor()
                        keepScreenOn = true
                        requestFocus()
                        isFocusableInTouchMode = true

                        applyTerminalDynamicColors(color, bgColor)

                        val colorsFile = ctx.localDir().child("colors.properties")
                        if (colorsFile.exists() && colorsFile.isFile) {
                            val props = Properties()
                            FileInputStream(colorsFile).use { props.load(it) }
                            TerminalColors.COLOR_SCHEME.updateWith(props)
                        }
                    }
                }
            },
            modifier = Modifier.fillMaxWidth().weight(1f),
            update = { view ->
                val color = TerminalUtils.getViewColor()
                val bgColor = TerminalUtils.getBackgroundColor()
                if (view.applyTerminalDynamicColors(color, bgColor)) {
                    view.postInvalidateOnAnimation()
                }
            }
        )

        if (viewModel.showVirtualKeys) {
            VirtualKeysPager(viewModel, mainActivity)
        }
    }
}

private fun TerminalView.applyTerminalDynamicColors(
    color: Int = TerminalUtils.getViewColor(),
    bgColor: Int = TerminalUtils.getBackgroundColor()
): Boolean {
    var changed = false
    mEmulator?.mColors?.mCurrentColors?.apply {
        changed = get(256) != color || get(257) != bgColor || get(258) != color
        if (changed) {
            set(256, color)
            set(257, bgColor)
            set(258, color)
        }
    }
    return changed
}

@Composable
private fun VirtualKeysPager(viewModel: TerminalViewModel, mainActivity: MainActivity) {
    val pagerState = rememberPagerState(pageCount = { 2 })
    val onSurfaceColor = MaterialTheme.colorScheme.onSurface.toArgb()

    HorizontalPager(
        state = pagerState,
        modifier = Modifier.fillMaxWidth().height(75.dp)
    ) { page ->
        when (page) {
            0 -> {
                AndroidView(
                    factory = { ctx ->
                        VirtualKeysView(ctx, null).apply {
                            viewModel.setVirtualKeysView(this)
                            virtualKeysViewClient = viewModel.terminalView?.mTermSession?.let {
                                VirtualKeysListener(it)
                            }
                            buttonTextColor = onSurfaceColor
                            reload(VirtualKeysInfo(VIRTUAL_KEYS, "", VirtualKeysConstants.CONTROL_CHARS_ALIASES))
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(75.dp)
                )
            }
            1 -> {
                var text by rememberSaveable { mutableStateOf("") }
                AndroidView(
                    modifier = Modifier.fillMaxWidth().height(75.dp),
                    factory = { ctx ->
                        EditText(ctx).apply {
                            maxLines = 1
                            isSingleLine = true
                            imeOptions = EditorInfo.IME_ACTION_DONE
                            doOnTextChanged { t, _, _, _ -> text = t.toString() }
                            setOnEditorActionListener { _, actionId, _ ->
                                if (actionId == EditorInfo.IME_ACTION_DONE) {
                                    val terminal = viewModel.terminalView
                                    if (text.isEmpty()) {
                                        terminal?.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                                        terminal?.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
                                    } else {
                                        val sid = mainActivity.viewModel.sessionBinder
                                            ?.getService()
                                            ?.currentSession
                                            ?.value
                                            ?.first
                                        if (sid != null) {
                                            SessionIsolationHooks.onUserSubmittedLine(sid, text)
                                        }
                                        terminal?.currentSession?.write(text)
                                        setText("")
                                    }
                                    true
                                } else false
                            }
                        }
                    },
                    update = { editText ->
                        if (editText.text.toString() != text) {
                            editText.setText(text)
                            editText.setSelection(text.length)
                        }
                    }
                )
            }
        }
    }
}
