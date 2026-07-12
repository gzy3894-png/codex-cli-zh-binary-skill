package com.rk.terminal.ui.screens.terminal

import com.rk.settings.Settings
import com.rk.terminal.session.AgentBindingStrategy
import com.rk.terminal.session.AgentCatalog
import com.rk.terminal.session.AgentKind
import com.rk.terminal.session.SessionIsolation
import com.rk.terminal.session.SessionIsolationHooks
import com.rk.terminal.session.WindowRole
import com.rk.terminal.ui.activities.terminal.MainActivity
import com.termux.terminal.TerminalSession
import com.termux.view.TerminalView
import java.util.UUID

/** Parameter-driven coordinator for creating one flat Agent worker window. */
object AgentWindowCoordinator {
    fun route(
        activity: MainActivity,
        terminal: TerminalView,
        sourceId: String,
        line: String,
        sourceSession: TerminalSession,
        eraseEchoedInput: Boolean,
        switchWindow: (String) -> Unit,
    ): Boolean {
        if (SessionIsolation.record(sourceId)?.role != WindowRole.LAUNCHER) return false
        val launch = AgentCatalog.detectLaunch(line) ?: return false
        val binder = activity.viewModel.sessionBinder ?: return false
        val service = binder.getService()
        val workerId = SessionIsolationHooks.nextId(service.sessionList.keys.toList())
        val explicitResumeId = AgentKind.detectResumeId(line)
        val generatedId = if (
            launch.definition.bindingStrategy == AgentBindingStrategy.EXPLICIT_SESSION_ID &&
            explicitResumeId == null
        ) UUID.randomUUID().toString() else null
        val command = generatedId?.let { "$line --session-id $it" } ?: line
        val windowToken = if (
            launch.definition.bindingStrategy == AgentBindingStrategy.CODEX_SESSION_HOOK
        ) UUID.randomUUID().toString() else null
        val client = TerminalBackEnd(terminal, activity, workerId)

        if (eraseEchoedInput) runCatching { sourceSession.write("\u0015") }
        binder.createSession(
            workerId,
            client,
            Settings.working_Mode,
            PendingCommand(
                command = command,
                workingDir = null,
                env = windowToken?.let { listOf("CODEX_TUI_WINDOW_TOKEN=$it") }.orEmpty(),
            ),
        )
        SessionIsolation.onSessionCreated(
            sessionId = workerId,
            workingMode = Settings.working_Mode,
            agentKind = launch.definition.kind,
            agentId = launch.definition.id,
            role = WindowRole.AGENT_WORKER,
            agentResumeId = generatedId ?: explicitResumeId.orEmpty(),
            preserveExistingIdentity = false,
        )
        windowToken?.let { SessionIsolation.expectCodexBinding(workerId, it) }
        switchWindow(workerId)
        return true
    }
}
