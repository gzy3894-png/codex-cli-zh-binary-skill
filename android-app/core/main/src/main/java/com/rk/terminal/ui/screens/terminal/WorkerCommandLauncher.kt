package com.rk.terminal.ui.screens.terminal

import android.os.Handler
import android.os.Looper
import com.rk.settings.Settings
import com.rk.terminal.session.AgentKind
import com.rk.terminal.session.SessionIsolation
import com.rk.terminal.session.SessionIsolationHooks
import com.rk.terminal.session.WindowRole
import com.rk.terminal.ui.activities.terminal.MainActivity
import com.termux.view.TerminalView
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Create a normal interactive worker shell, switch to it, then type the command
 * into the worker PTY after bootstrap. Never injects `/bin/sh -lc` via PendingCommand.
 */
object WorkerCommandLauncher {
    private val mainHandler = Handler(Looper.getMainLooper())

    // Bootstrap (init-host → proot → init → interactive ash) needs a short settle
    // window before the first typed command is accepted reliably.
    private val WRITE_ATTEMPT_DELAYS_MS = longArrayOf(900L, 1_600L, 2_600L, 4_000L, 6_000L)

    fun launch(
        activity: MainActivity,
        terminal: TerminalView,
        agentKind: AgentKind,
        agentId: String,
        command: String,
        env: List<String> = emptyList(),
        preferredDisplayName: String = "",
        agentResumeId: String = "",
        switchWindow: (String) -> Unit,
    ): String? {
        val binder = activity.viewModel.sessionBinder ?: return null
        val service = binder.getService()
        val workerId = SessionIsolationHooks.nextId(service.sessionList.keys.toList())
        val client = TerminalBackEnd(terminal, activity, workerId)
        val trimmed = command.trimEnd('\r', '\n')
        if (trimmed.isEmpty()) return null

        binder.createSession(
            workerId,
            client,
            Settings.working_Mode,
            pendingCommand = null,
            extraEnv = env,
        )
        SessionIsolation.onSessionCreated(
            sessionId = workerId,
            workingMode = Settings.working_Mode,
            agentKind = agentKind,
            agentId = agentId,
            role = WindowRole.AGENT_WORKER,
            preferredDisplayName = preferredDisplayName,
            agentResumeId = agentResumeId,
            preserveExistingIdentity = false,
        )
        switchWindow(workerId)
        schedulePtyCommand(binder, workerId, trimmed)
        return workerId
    }

    private fun schedulePtyCommand(
        binder: com.rk.terminal.service.SessionService.SessionBinder,
        workerId: String,
        command: String,
    ) {
        val payload = if (command.endsWith("\r")) command else "$command\r"
        val written = AtomicBoolean(false)
        WRITE_ATTEMPT_DELAYS_MS.forEach { delayMs ->
            mainHandler.postDelayed({
                if (!written.compareAndSet(false, true)) return@postDelayed
                val session = binder.getSession(workerId)
                if (session == null || !session.isRunning) {
                    written.set(false)
                    return@postDelayed
                }
                val ok = runCatching {
                    session.write(payload)
                    true
                }.getOrDefault(false)
                if (!ok) {
                    written.set(false)
                }
            }, delayMs)
        }
    }
}
