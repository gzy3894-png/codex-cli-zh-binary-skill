package com.rk.terminal.session

import android.content.Context
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshots.SnapshotStateMap
import com.rk.libcommons.child
import com.rk.libcommons.localDir
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

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
    private val bindingExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "codex-window-binding").apply { isDaemon = true }
    }

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
            ConversationManager.init(app)
            AgentCatalog.init(app)
            runCatching {
                app.localDir().child("session-bind").apply {
                    if (exists()) deleteRecursively()
                    mkdirs()
                }
            }
            // PTY windows are process-local runtime state. Restoring old shell
            // rows after a crash only recreates same-named fresh shells and can
            // resurrect a broken native PTY forever. Conversation history has
            // its own durable registry and is intentionally unaffected.
            records.clear()
            displayNames.clear()
            currentId = ""
            s.save(SessionRegistryStore.Snapshot())
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
        agentId: String = agentKind.prefix,
        role: WindowRole = WindowRole.SHELL_WORKER,
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
                            ?: if (existing.agentId != agentId) {
                                SessionNaming.buildDisplayName(
                                    agentId,
                                    SessionNaming.stripPrefix(
                                        existing.displayName,
                                        existing.agentId,
                                    ),
                                )
                            } else {
                                existing.displayName
                            }
                        existing.copy(
                            workingMode = workingMode,
                            agentKind = agentKind,
                            agentId = agentId,
                            role = role,
                            // Explicit identity replacement must also clear a stale UUID.
                            // Session IDs are reusable after a failed/closed PTY; inheriting
                            // the previous row binds a new window to the wrong conversation.
                            agentResumeId = agentResumeId,
                            displayName = resolvedName,
                            autoNamed = if (preferredDisplayName != null) autoNamed else existing.autoNamed,
                        ).touch()
                    }
                } else {
                    val ordinal = records.size + 1
                    val rawName = preferredDisplayName?.takeIf { it.isNotBlank() }
                        ?: "$agentId-新会话$ordinal"
                    SessionRecord(
                        id = sessionId,
                        displayName = SessionNaming.buildDisplayName(agentId, rawName),
                        agentKind = agentKind,
                        agentId = agentId,
                        role = role,
                        workingMode = workingMode,
                        agentResumeId = agentResumeId,
                        autoNamed = autoNamed,
                    )
                }
                putLocked(rec)
                if (rec.agentResumeId.isNotBlank()) {
                    ConversationManager.ensure(
                        id = rec.agentResumeId,
                        agentKind = rec.agentKind,
                        displayName = rec.displayName,
                    )
                }
                if (currentId.isBlank()) currentId = sessionId
                persistLocked()
                rec
            }
        }.getOrElse {
            val fallback = SessionRecord(
                id = sessionId,
                displayName = "$agentId-$sessionId",
                agentKind = agentKind,
                agentId = agentId,
                role = role,
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
            currentId = ""
            persistLocked()
            bumpLocked()
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
                    name = SessionNaming.buildDisplayName(existing.agentId, title),
                    autoNamed = false,
                )
                putLocked(next)
                persistLocked()
                next
            }
        }.getOrNull()
    }

    fun setAgentKind(sessionId: String, kind: AgentKind): SessionRecord? {
        return setAgentIdentity(sessionId, kind.prefix, kind)
    }

    fun setAgentIdentity(
        sessionId: String,
        agentId: String,
        kind: AgentKind,
        role: WindowRole = WindowRole.AGENT_WORKER,
    ): SessionRecord? {
        if (!enabled) return null
        return runCatching {
            synchronized(lock) {
                val existing = records[sessionId] ?: return null
                if (existing.agentKind == kind && existing.agentId == agentId) return existing
                val next = existing.copy(
                    agentKind = kind,
                    agentId = agentId,
                    role = role,
                    agentResumeId = "",
                    displayName = SessionNaming.buildDisplayName(agentId, "新会话"),
                    autoNamed = true,
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
            val launch = AgentCatalog.detectLaunch(line)
            if (launch != null) {
                val changed = setAgentIdentity(
                    sessionId,
                    launch.definition.id,
                    launch.definition.kind,
                ) != null
                val explicitResumeId = AgentKind.detectResumeId(line)
                if (explicitResumeId != null) {
                    bindAgentResumeId(sessionId, explicitResumeId)
                }
                changed
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
                val nextName = SessionNaming.fromFirstUserMessage(existing.agentId, text)
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
            ConversationManager.ensure(
                id = id,
                agentKind = next.agentKind,
                displayName = next.displayName,
            )
            return next
        }
    }

    /**
     * Consume only the SessionStart event carrying this worker's launch token.
     * This is deterministic under concurrent Codex launches and never scans for
     * a globally "latest" transcript.
     */
    fun expectCodexBinding(sessionId: String, windowToken: String) {
        if (!enabled || windowToken.isBlank()) return
        val context = appContext ?: return
        val event = context.localDir().child("session-bind").child(windowToken)
        listOf(1L, 2L, 4L, 8L, 15L, 30L).forEach { delay ->
            bindingExecutor.schedule({
                if (record(sessionId)?.agentResumeId?.isNotBlank() != false) return@schedule
                val resumeId = runCatching { event.readText().trim() }.getOrNull()
                    ?.takeIf { it.matches(UUID_PATTERN) }
                    ?: return@schedule
                if (bindAgentResumeId(sessionId, resumeId) != null) {
                    runCatching { event.delete() }
                }
            }, delay, TimeUnit.SECONDS)
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

    private val UUID_PATTERN = Regex(
        "(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-" +
            "[0-9a-f]{4}-[0-9a-f]{12}$"
    )

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
            ConversationManager.resetForTests()
            revision.value = 0
        }
    }
}
