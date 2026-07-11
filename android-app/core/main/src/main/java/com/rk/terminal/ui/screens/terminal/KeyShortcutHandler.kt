package com.rk.terminal.ui.screens.terminal

import android.view.KeyEvent
import androidx.lifecycle.ViewModelProvider
import com.blankj.utilcode.util.ClipboardUtils
import com.rk.settings.Settings
import com.rk.terminal.session.SessionIsolationHooks
import com.rk.terminal.ui.activities.terminal.MainActivity

object KeyShortcutHandler {

    fun handle(keyCode: Int, event: KeyEvent, activity: MainActivity): Boolean {
        if (!Settings.shortcuts_enabled) return false

        for (action in ShortcutAction.entries) {
            val binding = Settings.getShortcutBinding(action)
            if (binding.matches(event)) {
                return dispatch(action, activity)
            }
        }
        return false
    }

    private fun dispatch(action: ShortcutAction, activity: MainActivity): Boolean {
        val terminalViewModel = ViewModelProvider(activity)[TerminalViewModel::class.java]
        
        return when (action) {
            ShortcutAction.PASTE -> handlePaste(terminalViewModel)
            ShortcutAction.NEW_SESSION -> handleNewSession(activity, terminalViewModel)
            ShortcutAction.CLOSE_SESSION -> handleCloseSession(activity, terminalViewModel)
            ShortcutAction.SWITCH_SESSION_PREV -> handleSwitchSession(activity, terminalViewModel, forward = false)
            ShortcutAction.SWITCH_SESSION_NEXT -> handleSwitchSession(activity, terminalViewModel, forward = true)
        }
    }

    private fun handlePaste(viewModel: TerminalViewModel): Boolean {
        val clip = ClipboardUtils.getText()?.toString() ?: return true
        if (clip.trim().isNotEmpty()) {
            viewModel.terminalView?.mEmulator?.paste(clip)
        }
        return true
    }

    private fun handleNewSession(activity: MainActivity, viewModel: TerminalViewModel): Boolean {
        val binder = activity.viewModel.sessionBinder ?: return true
        val service = binder.getService()

        val sessionId = SessionIsolationHooks.nextId(service.sessionList.keys.toList())
        viewModel.terminalView?.let {
            val client = TerminalBackEnd(it, activity, sessionId)
            binder.createSession(sessionId, client, Settings.working_Mode)
        }
        viewModel.changeSession(activity, binder, sessionId)
        return true
    }

    private fun handleCloseSession(activity: MainActivity, viewModel: TerminalViewModel): Boolean {
        val binder = activity.viewModel.sessionBinder ?: return true
        val service = binder.getService()
        val currentId = service.currentSession.value.first
        // Close current terminal window only — same path as drawer delete button.
        viewModel.closeWindow(activity, binder, currentId)
        // If no windows remain, leave activity open; user can add another window.
        // Avoid finish() here: it raced with service stopSelf and crashed on delete.
        if (service.sessionList.isEmpty()) {
            return true
        }
        return true
    }

    private fun handleSwitchSession(activity: MainActivity, viewModel: TerminalViewModel, forward: Boolean): Boolean {
        val binder = activity.viewModel.sessionBinder ?: return true
        val service = binder.getService()
        val sessionKeys = service.sessionList.keys.toList()

        if (sessionKeys.size <= 1) return true

        val currentId = service.currentSession.value.first
        val currentIndex = sessionKeys.indexOf(currentId)

        val nextIndex = if (forward) {
            (currentIndex + 1) % sessionKeys.size
        } else {
            (currentIndex - 1 + sessionKeys.size) % sessionKeys.size
        }

        viewModel.changeSession(activity, binder, sessionKeys[nextIndex])
        return true
    }

    }
