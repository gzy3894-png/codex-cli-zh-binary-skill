package com.rk.terminal.ui.screens.terminal

import com.rk.terminal.session.AgentBindingStrategy
import com.rk.terminal.session.AgentCatalog
import com.rk.terminal.session.AgentKind
import com.rk.terminal.session.SessionIsolation
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
        val explicitResumeId = AgentKind.detectResumeId(line)
        val generatedId = if (
            launch.definition.bindingStrategy == AgentBindingStrategy.EXPLICIT_SESSION_ID &&
            explicitResumeId == null
        ) UUID.randomUUID().toString() else null
        val command = generatedId?.let { "$line --session-id $it" } ?: line
        val windowToken = if (
            launch.definition.bindingStrategy == AgentBindingStrategy.CODEX_SESSION_HOOK
        ) UUID.randomUUID().toString() else null

        if (eraseEchoedInput) runCatching { sourceSession.write("\u0015") }
        val workerId = WorkerCommandLauncher.launch(
            activity = activity,
            terminal = terminal,
            agentKind = launch.definition.kind,
            agentId = launch.definition.id,
            command = command,
            env = windowToken?.let { listOf("CODEX_TUI_WINDOW_TOKEN=$it") }.orEmpty(),
            agentResumeId = generatedId ?: explicitResumeId.orEmpty(),
            switchWindow = switchWindow,
        ) ?: return false
        windowToken?.let { SessionIsolation.expectCodexBinding(workerId, it) }
        return true
    }
}
