package com.rk.terminal.session

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Durable conversation index. CLI transcript files remain the source of truth;
 * this file only stores display/archive metadata and the last discovered path.
 */
class ConversationRegistryStore(context: Context) {
    private val dir = File(context.applicationContext.filesDir, DIR_NAME).also { it.mkdirs() }
    private val file = File(dir, FILE_NAME)

    fun load(): List<ConversationRecord> {
        if (!file.isFile || file.length() <= 0L) return emptyList()
        return runCatching {
            val root = JSONObject(file.readText())
            val items = root.optJSONArray("conversations") ?: JSONArray()
            buildList {
                for (index in 0 until items.length()) {
                    val item = items.optJSONObject(index) ?: continue
                    val id = item.optString("id").trim()
                    if (id.isBlank()) continue
                    add(
                        ConversationRecord(
                            id = id,
                            agentKind = AgentKind.fromRaw(item.optString("agentKind")),
                            displayName = item.optString("displayName").ifBlank { id },
                            workingDirectory = item.optString("workingDirectory"),
                            sourcePath = item.optString("sourcePath"),
                            lastActivityAt = item.optLong(
                                "lastActivityAt",
                                System.currentTimeMillis(),
                            ),
                            archived = item.optBoolean("archived", false),
                        )
                    )
                }
            }
        }.getOrElse { emptyList() }
    }

    fun save(records: Collection<ConversationRecord>) {
        runCatching {
            val items = JSONArray()
            records.forEach { record ->
                items.put(
                    JSONObject()
                        .put("id", record.id)
                        .put("agentKind", record.agentKind.prefix)
                        .put("displayName", record.displayName)
                        .put("workingDirectory", record.workingDirectory)
                        .put("sourcePath", record.sourcePath)
                        .put("lastActivityAt", record.lastActivityAt)
                        .put("archived", record.archived)
                )
            }
            val root = JSONObject()
                .put("version", VERSION)
                .put("conversations", items)
            val tmp = File(dir, "$FILE_NAME.tmp")
            tmp.writeText(root.toString())
            if (!tmp.renameTo(file)) {
                file.writeText(root.toString())
                tmp.delete()
            }
        }
    }

    companion object {
        private const val DIR_NAME = "conversation-isolation"
        private const val FILE_NAME = "registry.json"
        const val VERSION = 1
    }
}
