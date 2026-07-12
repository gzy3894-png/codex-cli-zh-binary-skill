package com.rk.terminal.ui.screens.terminal

import com.rk.settings.Settings
import com.rk.terminal.service.SessionService
import com.rk.terminal.session.SessionIsolation
import com.rk.terminal.session.WindowRole
import com.termux.terminal.TerminalSession
import com.termux.view.TerminalView

/**
 * Resolves one explicit live PTY target from SessionService, the process-local
 * authority for window selection. UI callers pass the result downstream
 * instead of consulting TerminalView.currentSession again.
 */
data class ResolvedSessionTarget(
    val id: String,
    val mode: Int,
    val role: WindowRole,
    val session: TerminalSession,
)

object SessionTargetResolver {
    fun resolveCurrent(
        binder: SessionService.SessionBinder?,
    ): ResolvedSessionTarget? {
        val resolvedBinder = binder ?: return null
        val service = resolvedBinder.getService()
        val id = service.currentSession.value.first
        if (id.isBlank() || !service.sessionList.containsKey(id)) return null
        val session = resolvedBinder.getSession(id) ?: return null
        if (!session.isRunning) return null
        return ResolvedSessionTarget(
            id = id,
            mode = service.sessionList[id] ?: Settings.working_Mode,
            role = SessionIsolation.record(id)?.role ?: WindowRole.SHELL_WORKER,
            session = session,
        )
    }

    fun isAttached(
        terminalView: TerminalView?,
        target: ResolvedSessionTarget?,
    ): Boolean = target != null && terminalView?.currentSession === target.session
}
