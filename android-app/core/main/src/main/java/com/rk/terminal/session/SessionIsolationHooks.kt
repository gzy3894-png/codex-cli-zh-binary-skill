package com.rk.terminal.session

import android.content.Context

/**
 * Thin integration helpers so call sites stay one-liners.
 * No dependency on SessionService / ViewModel — callers pass lambdas.
 * Safe no-ops when [SessionIsolation.enabled] is false.
 */
object SessionIsolationHooks {

    fun ensureInit(context: Context) {
        if (!SessionIsolation.enabled) return
        SessionIsolation.init(context)
    }

    fun notifyCreated(sessionId: String, workingMode: Int, agentKind: AgentKind = AgentKind.CODEX) {
        if (!SessionIsolation.enabled) return
        SessionIsolation.onSessionCreated(sessionId, workingMode, agentKind)
    }

    fun notifyTerminated(sessionId: String) {
        if (!SessionIsolation.enabled) return
        SessionIsolation.onSessionTerminated(sessionId)
    }

    fun notifyCurrent(sessionId: String) {
        if (!SessionIsolation.enabled) return
        SessionIsolation.onCurrentChanged(sessionId)
    }

    fun titleOf(sessionId: String): String =
        if (SessionIsolation.enabled) SessionIsolation.displayName(sessionId) else sessionId

    fun nextId(existingIds: Collection<String>): String =
        if (SessionIsolation.enabled) {
            SessionIsolation.nextSessionId(existingIds)
        } else {
            SessionNaming.nextLegacySessionId(existingIds)
        }

    fun onUserSubmittedLine(sessionId: String, text: String) {
        if (!SessionIsolation.enabled) return
        SessionIsolation.applyFirstUserMessage(sessionId, text)
    }

    /**
     * When the live session map is empty, return registry rows to recreate.
     * Uses cold-start snapshot first; if the service died mid-process, falls back to in-memory records.
     */
    fun pendingRestoreIfEmpty(liveSessionCount: Int): List<SessionRecord> {
        if (!SessionIsolation.enabled) return emptyList()
        if (liveSessionCount > 0) return emptyList()
        val cold = SessionIsolation.consumePendingRestore()
        if (cold.isNotEmpty()) return cold
        return SessionIsolation.allRecords()
    }

    /**
     * Best-effort: inject `codex resume <uuid>` / `claude --resume <uuid>` once after restore.
     * Does nothing when UUID is missing.
     */
    fun maybeInjectResume(sessionId: String, write: (String) -> Unit) {
        if (!SessionIsolation.enabled) return
        val cmd = SessionIsolation.takeResumeCommandForInject(sessionId) ?: return
        write(cmd + "\n")
    }
}
