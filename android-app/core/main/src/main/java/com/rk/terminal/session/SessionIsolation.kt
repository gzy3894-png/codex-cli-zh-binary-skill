package com.rk.terminal.session

import android.content.Context
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshots.SnapshotStateMap
import java.util.concurrent.ConcurrentHashMap

/**
 * Standalone session-isolation facade.
 *
 * Keeps terminal tab metadata (display name, agent prefix, resume UUID) out of
 * SessionService / UI. Existing code continues to use sessionId strings; call into
 * this module only for naming, persistence, and resume command resolution.
 *
 * Resume identity is always [SessionRecord.agentResumeId] (UUID), never displayName.
 * Agent prefix is inferred from shell launches (claude/codex), not from a dialog chip.
 */
object SessionIsolation {
    private val lock = Any()
    private var appContext: Context? = null
    private var store: SessionRegistryStore? = null
    private val records = linkedMapOf<String, SessionRecord>()
    private var currentId: String = ""
    private var pendingRestore: List<SessionRecord> = emptyList()
    private var restoreConsumed = false
    /** Set by clearAll (EXIT); blocks mid-lifecycle allRecords resurrect until process re-init. */
    private var intentionallyWiped = false
    private val resumeInjected = ConcurrentHashMap.newKeySet<String>()

    /** Observable titles for Compose (sessionId → displayName). */
    val displayNames: SnapshotStateMap<String, String> = mutableStateMapOf()

    /** Bumps when registry mutates so drawers can recompose. */
    val revision = mutableStateOf(0)

    @Volatile
    var enabled: Boolean = true

    fun init(context: Context) {
        if (!enabled) return
        val app = context.applicationContext
        synchronized(lock) {
            appContext = app
            if (store != null) return
            val s = SessionRegistryStore(app)
            store = s
            val snap = s.load()
            records.clear()
            displayNames.clear()
            snap.sessions.forEach {
                records[it.id] = it
                displayNames[it.id] = it.displayName
            }
            currentId = snap.currentId
            pendingRestore = snap.sessions.toList()
            restoreConsumed = false
            intentionallyWiped = false
            resumeInjected.clear()
            bumpLocked()
        }
    }

    fun isReady(): Boolean = store != null

    fun displayName(sessionId: String): String {
        if (!enabled) return sessionId
        return displayNames[sessionId]
            ?: synchronized(lock) { records[sessionId]?.displayName }
            ?: sessionId
    }

    fun record(sessionId: String): SessionRecord? {
        if (!enabled) return null
        synchronized(lock) {
            return records[sessionId]
        }
    }

    fun allRecords(): List<SessionRecord> {
        synchronized(lock) {
            return records.values.toList()
        }
    }

    fun nextSessionId(existingIds: Collection<String>): String =
        SessionNaming.nextLegacySessionId(existingIds)

    /**
     * Ensure metadata exists when a live terminal session is created.
     *
     * Defaults to [AgentKind.SHELL] so create paths do not falsely stamp CODEX
     * before a real agent is launched. Pass explicit agentKind/resume fields
     * when restoring from registry.
     */
    fun onSessionCreated(
        sessionId: String,
        workingMode: Int,
        agentKind: AgentKind = AgentKind.SHELL,
        preferredDisplayName: String? = null,
        agentResumeId: String = "",
        autoNamed: Boolean = true,
        /** When false, do not overwrite an existing record's agentKind/displayName. */
        preserveExistingIdentity: Boolean = false,
    ): SessionRecord? {
        if (!enabled) return null
        // Never crash the terminal for naming/registry faults; fall back to raw id.
        return runCatching {
            ensureStore()
            synchronized(lock) {
                val existing = records[sessionId]
                val rec = if (existing != null) {
                    if (preserveExistingIdentity) {
                        existing.copy(workingMode = workingMode).touch()
                    } else {
                        val resolvedName = preferredDisplayName?.takeIf { it.isNotBlank() }
                            ?: if (existing.agentKind != agentKind) {
                                SessionNaming.buildDisplayName(
                                    agentKind,
                                    SessionNaming.stripPrefix(existing.displayName),
                                )
                            } else {
                                existing.displayName
                            }
                        existing.copy(
                            workingMode = workingMode,
                            agentKind = agentKind,
                            agentResumeId = agentResumeId.ifBlank { existing.agentResumeId },
                            displayName = resolvedName,
                            autoNamed = if (preferredDisplayName != null) autoNamed else existing.autoNamed,
                        ).touch()
                    }
                } else {
                    val ordinal = records.size + 1
                    val rawName = preferredDisplayName?.takeIf { it.isNotBlank() }
                        ?: SessionNaming.defaultTitle(agentKind, ordinal)
                    SessionRecord(
                        id = sessionId,
                        displayName = SessionNaming.buildDisplayName(agentKind, rawName),
                        agentKind = agentKind,
                        workingMode = workingMode,
                        agentResumeId = agentResumeId,
                        autoNamed = autoNamed,
                    )
                }
                putLocked(rec)
                if (currentId.isBlank()) currentId = sessionId
                persistLocked()
                rec
            }
        }.getOrElse {
            val fallback = SessionRecord(
                id = sessionId,
                displayName = "${agentKind.prefix}-$sessionId",
                agentKind = agentKind,
                workingMode = workingMode,
                agentResumeId = agentResumeId,
                autoNamed = autoNamed,
            )
            synchronized(lock) {
                putLocked(fallback)
                if (currentId.isBlank()) currentId = sessionId
            }
            fallback
        }
    }

    fun onSessionTerminated(sessionId: String) {
        if (!enabled) return
        synchronized(lock) {
            records.remove(sessionId)
            displayNames.remove(sessionId)
            resumeInjected.remove(sessionId)
            if (currentId == sessionId) {
                currentId = records.keys.lastOrNull().orEmpty()
            }
            persistLocked()
            bumpLocked()
        }
    }

    /** Drop every registry row (notification EXIT / explicit wipe). */
    fun clearAll() {
        if (!enabled) return
        synchronized(lock) {
            records.clear()
            displayNames.clear()
            resumeInjected.clear()
            currentId = ""
            pendingRestore = emptyList()
            restoreConsumed = true
            intentionallyWiped = true
            persistLocked()
            bumpLocked()
        }
    }

    /**
     * Sessions to recreate when live map is empty.
     * Cold snapshot first; if already consumed and not intentionally wiped,
     * fall back to in-memory records (service restart mid-process).
     */
    fun pendingRestoreIfEmpty(liveSessionCount: Int): List<SessionRecord> {
        if (!enabled) return emptyList()
        if (liveSessionCount > 0) return emptyList()
        synchronized(lock) {
            if (intentionallyWiped) return emptyList()
            if (!restoreConsumed) {
                restoreConsumed = true
                val list = pendingRestore
                pendingRestore = emptyList()
                if (list.isNotEmpty()) return list
            }
            return records.values.toList()
        }
    }

    fun onCurrentChanged(sessionId: String) {
        if (!enabled) return
        synchronized(lock) {
            if (currentId == sessionId) {
                // Still touch lastActive for restore preference, but skip redundant writes when possible.
                records[sessionId]?.let {
                    val next = it.touch()
                    records[sessionId] = next
                    // no displayNames change; still persist currentId if needed
                }
                persistLocked()
                return
            }
            currentId = sessionId
            records[sessionId]?.let { putLocked(it.touch()) }
            persistLocked()
        }
    }

    /**
     * User rename: keeps fixed agent prefix; body is free text.
     */
    fun rename(sessionId: String, title: String): SessionRecord? {
        if (!enabled) return null
        return runCatching {
            synchronized(lock) {
                val existing = records[sessionId] ?: return null
                val next = existing.withDisplayName(
                    name = SessionNaming.buildDisplayName(existing.agentKind, title),
                    autoNamed = false,
                )
                putLocked(next)
                persistLocked()
                next
            }
        }.getOrNull()
    }

    fun setAgentKind(sessionId: String, kind: AgentKind): SessionRecord? {
        if (!enabled) return null
        return runCatching {
            synchronized(lock) {
                val existing = records[sessionId] ?: return null
                if (existing.agentKind == kind) return existing
                val body = SessionNaming.stripPrefix(existing.displayName)
                val next = existing.copy(
                    agentKind = kind,
                    displayName = SessionNaming.buildDisplayName(kind, body),
                    lastActiveAt = System.currentTimeMillis(),
                )
                putLocked(next)
                persistLocked()
                next
            }
        }.getOrNull()
    }

    /**
     * Observe a user-submitted shell line:
     * 1) If it launches claude/codex, update agent prefix (even mid-session).
     * 2) Else if still autoNamed and not noise, name from first message.
     */
    fun onUserSubmittedLine(sessionId: String, text: String): Boolean {
        if (!enabled) return false
        val line = text.trim()
        if (line.isEmpty()) return false
        return runCatching {
            val launch = AgentKind.detectLaunch(line)
            if (launch != null) {
                setAgentKind(sessionId, launch) != null
            } else {
                applyFirstUserMessage(sessionId, line)
            }
        }.getOrDefault(false)
    }

    /**
     * Default name from the user's first message. Skips if user already renamed manually.
     */
    fun applyFirstUserMessage(sessionId: String, message: String): Boolean {
        if (!enabled) return false
        val text = message.trim()
        if (text.isEmpty()) return false
        if (SessionNaming.isNoiseForAutoName(text)) return false
        return runCatching {
            synchronized(lock) {
                val existing = records[sessionId] ?: return false
                if (!existing.autoNamed) return false
                val nextName = SessionNaming.fromFirstUserMessage(existing.agentKind, text)
                if (nextName == existing.displayName) {
                    putLocked(existing.copy(autoNamed = false))
                    persistLocked()
                    return false
                }
                putLocked(existing.withDisplayName(nextName, autoNamed = false))
                persistLocked()
                true
            }
        }.getOrDefault(false)
    }

    fun bindAgentResumeId(sessionId: String, resumeId: String): SessionRecord? {
        if (!enabled) return null
        val id = resumeId.trim()
        if (id.isEmpty()) return null
        synchronized(lock) {
            val existing = records[sessionId] ?: return null
            val next = existing.withResumeId(id)
            putLocked(next)
            persistLocked()
            return next
        }
    }

    /** Build shell resume command from UUID; null if missing or shell kind. */
    fun resumeCommand(sessionId: String): String? {
        if (!enabled) return null
        synchronized(lock) {
            val rec = records[sessionId] ?: return null
            return rec.agentKind.resumeCommand(rec.agentResumeId)
        }
    }

    /**
     * One-shot resume inject so restore does not spam resume on every attach.
     */
    fun takeResumeCommandForInject(sessionId: String): String? {
        val cmd = resumeCommand(sessionId) ?: return null
        if (!resumeInjected.add(sessionId)) return null
        return cmd
    }

    /** @deprecated Prefer [pendingRestoreIfEmpty]; kept for tests/callers. */
    fun consumePendingRestore(): List<SessionRecord> {
        return pendingRestoreIfEmpty(0)
    }

    fun preferredCurrentId(fallback: String): String {
        synchronized(lock) {
            return when {
                currentId.isNotBlank() && records.containsKey(currentId) -> currentId
                records.isNotEmpty() -> records.keys.last()
                else -> fallback
            }
        }
    }

    fun saveNow() {
        if (!enabled) return
        synchronized(lock) {
            persistLocked()
        }
    }

    private fun putLocked(rec: SessionRecord) {
        records[rec.id] = rec
        displayNames[rec.id] = rec.displayName
        bumpLocked()
    }

    private fun persistLocked() {
        val s = store ?: return
        s.save(
            SessionRegistryStore.Snapshot(
                currentId = currentId,
                sessions = records.values.toList(),
            )
        )
    }

    private fun bumpLocked() {
        revision.value = revision.value + 1
    }

    private fun ensureStore() {
        if (store != null) return
        val ctx = appContext ?: return
        val s = SessionRegistryStore(ctx)
        store = s
    }

    /** Test / debug helper */
    internal fun resetForTests() {
        synchronized(lock) {
            store = null
            appContext = null
            records.clear()
            displayNames.clear()
            currentId = ""
            pendingRestore = emptyList()
            restoreConsumed = false
            intentionallyWiped = false
            resumeInjected.clear()
            revision.value = 0
        }
    }
}
