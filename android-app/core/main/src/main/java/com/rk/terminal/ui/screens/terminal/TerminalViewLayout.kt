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
import com.rk.terminal.session.WindowRole
import com.rk.terminal.session.LAUNCHER_WINDOW_ID
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

                    // A process always starts from one fresh, non-deletable launcher.
                    // Historical conversations are resumed lazily when selected;
                    // stale PTY rows are deliberately never reconstructed.
                    val launcherId = LAUNCHER_WINDOW_ID
                    val launcherClient = TerminalBackEnd(this, mainActivity, launcherId)
                    if (sessionBinder.getSession(launcherId) == null) {
                        sessionBinder.createSession(
                            launcherId,
                            launcherClient,
                            Settings.working_Mode,
                        )
                    }
                    SessionIsolation.onSessionCreated(
                        sessionId = launcherId,
                        workingMode = Settings.working_Mode,
                        agentKind = com.rk.terminal.session.AgentKind.SHELL,
                        role = WindowRole.LAUNCHER,
                        preferredDisplayName = "启动台",
                        autoNamed = false,
                        preserveExistingIdentity = false,
                    )

                    // Cold process start falls back to the permanent launcher.
                    // Activity/TerminalView reconstruction in the same process
                    // reattaches the still-live service target instead of
                    // silently stealing selection from a worker window.
                    val requestedId = service.currentSession.value.first
                    val activeId = requestedId.takeIf {
                        it.isNotBlank() &&
                            service.sessionList.containsKey(it) &&
                            sessionBinder.getSession(it) != null
                    } ?: launcherId
                    val activeClient = if (activeId == launcherId) {
                        launcherClient
                    } else {
                        TerminalBackEnd(this, mainActivity, activeId)
                    }
                    val session = sessionBinder.getSession(activeId)
                        ?: sessionBinder.createSession(
                            activeId,
                            activeClient,
                            Settings.working_Mode,
                        )
                    service.currentSession.value =
                        activeId to (service.sessionList[activeId] ?: Settings.working_Mode)

                    session.updateTerminalSessionClient(activeClient)
                    attachSession(session)
                    setTerminalViewClient(activeClient)
                    setTypeface(TerminalUtils.typeface)
                    SessionIsolationHooks.notifyCurrent(activeId)


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
                                    val binder = mainActivity.viewModel.sessionBinder
                                    val target = SessionTargetResolver.resolveCurrent(binder)
                                    if (text.isEmpty()) {
                                        if (SessionTargetResolver.isAttached(terminal, target)) {
                                            terminal?.dispatchKeyEvent(
                                                KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER)
                                            )
                                            terminal?.dispatchKeyEvent(
                                                KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER)
                                            )
                                        } else {
                                            target?.session?.write("\r")
                                        }
                                    } else {
                                        val routed = if (
                                            binder != null && target != null && terminal != null
                                        ) {
                                            AgentWindowCoordinator.route(
                                                mainActivity,
                                                terminal,
                                                target.id,
                                                text,
                                                target.session,
                                                false,
                                            ) { workerId ->
                                                viewModel.changeSession(mainActivity, binder, workerId)
                                            }
                                        } else {
                                            false
                                        }
                                        if (!routed) {
                                            if (target != null) {
                                                SessionIsolationHooks.onUserSubmittedLine(
                                                    target.id,
                                                    text,
                                                )
                                                target.session.write(text)
                                            }
                                        }
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
