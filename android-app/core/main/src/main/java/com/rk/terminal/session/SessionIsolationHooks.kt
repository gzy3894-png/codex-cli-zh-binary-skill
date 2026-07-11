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

    /**
     * Register a newly created live session.
     * Default agent is SHELL; real claude/codex is applied when the user launches them.
     * [preserveExistingIdentity] defaults true so createSession cannot clobber restored rows.
     */
    fun notifyCreated(
        sessionId: String,
        workingMode: Int,
        agentKind: AgentKind = AgentKind.SHELL,
        preserveExistingIdentity: Boolean = true,
    ) {
        if (!SessionIsolation.enabled) return
        SessionIsolation.onSessionCreated(
            sessionId = sessionId,
            workingMode = workingMode,
            agentKind = agentKind,
            preserveExistingIdentity = preserveExistingIdentity,
        )
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
        SessionIsolation.onUserSubmittedLine(sessionId, text)
    }

    /**
     * When the live session map is empty, return registry rows to recreate.
     * See [SessionIsolation.pendingRestoreIfEmpty].
     */
    fun pendingRestoreIfEmpty(liveSessionCount: Int): List<SessionRecord> {
        if (!SessionIsolation.enabled) return emptyList()
        return SessionIsolation.pendingRestoreIfEmpty(liveSessionCount)
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

    fun clearAll() {
        if (!SessionIsolation.enabled) return
        SessionIsolation.clearAll()
    }
}
