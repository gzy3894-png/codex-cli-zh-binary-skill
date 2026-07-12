package com.rk.terminal.session

import android.content.Context
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import java.util.concurrent.Executors

/**
 * Owns imported CLI conversations, independently from live PTY windows.
 */
object ConversationManager {
    private val lock = Any()
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "codex-conversation-scan").apply { isDaemon = true }
    }
    private var context: Context? = null
    private var store: ConversationRegistryStore? = null
    private var discovery: ConversationDiscovery? = null
    private val records = linkedMapOf<String, ConversationRecord>()

    val visible: MutableList<ConversationRecord> = mutableStateListOf()
    val revision = mutableStateOf(0)

    fun init(context: Context) {
        synchronized(lock) {
            if (store != null) return
            val app = context.applicationContext
            this.context = app
            store = ConversationRegistryStore(app)
            discovery = ConversationDiscovery(app)
            records.clear()
            store?.load()?.forEach { records[it.id] = it }
            publishLocked()
        }
        refreshAsync()
    }

    fun refreshAsync() {
        executor.execute { refreshNow() }
    }

    fun refreshNow(): List<ConversationRecord> {
        val discovered = runCatching { discovery?.scan().orEmpty() }.getOrDefault(emptyList())
        synchronized(lock) {
            discovered.forEach { item ->
                val previous = records[item.id]
                records[item.id] = if (previous == null) {
                    item
                } else {
                    item.copy(
                        displayName = if (previous.agentKind == item.agentKind) {
                            previous.displayName
                        } else {
                            SessionNaming.buildDisplayName(item.agentKind, previous.displayName)
                        },
                        archived = previous.archived,
                    )
                }
            }
            persistLocked()
            publishLocked()
            return records.values.toList()
        }
    }

    fun all(): List<ConversationRecord> = synchronized(lock) { records.values.toList() }

    fun find(id: String): ConversationRecord? =
        synchronized(lock) { records[id] }

    fun ensure(
        id: String,
        agentKind: AgentKind,
        displayName: String,
        workingDirectory: String = "",
    ): ConversationRecord {
        synchronized(lock) {
            val existing = records[id]
            if (existing != null) return existing
            val created = ConversationRecord(
                id = id,
                agentKind = agentKind,
                displayName = SessionNaming.buildDisplayName(agentKind, displayName),
                workingDirectory = workingDirectory,
            )
            records[id] = created
            persistLocked()
            publishLocked()
            return created
        }
    }

    fun archive(id: String): Boolean {
        synchronized(lock) {
            val existing = records[id] ?: return false
            records[id] = existing.archive()
            persistLocked()
            publishLocked()
            return true
        }
    }

    fun unarchived(): List<ConversationRecord> =
        synchronized(lock) { records.values.filterNot { it.archived } }

    fun resetForTests() {
        synchronized(lock) {
            context = null
            store = null
            discovery = null
            records.clear()
            visible.clear()
            revision.value = 0
        }
    }

    private fun persistLocked() {
        store?.save(records.values)
    }

    private fun publishLocked() {
        visible.clear()
        visible.addAll(records.values.filterNot { it.archived }.sortedByDescending { it.lastActivityAt })
        revision.value += 1
    }

}
