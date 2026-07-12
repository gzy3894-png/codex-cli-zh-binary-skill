package com.rk.terminal.session

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Disk-backed registry for session isolation metadata.
 * File: filesDir/session-isolation/registry.json
 */
class SessionRegistryStore(context: Context) {
    private val dir = File(context.applicationContext.filesDir, DIR_NAME).also { it.mkdirs() }
    private val file = File(dir, FILE_NAME)

    data class Snapshot(
        val version: Int = VERSION,
        val currentId: String = "",
        val sessions: List<SessionRecord> = emptyList(),
    )

    fun load(): Snapshot {
        if (!file.exists() || file.length() <= 0L) return Snapshot()
        return runCatching {
            val root = JSONObject(file.readText())
            val version = root.optInt("version", VERSION)
            val currentId = root.optString("currentId", "")
            val arr = root.optJSONArray("sessions") ?: JSONArray()
            val sessions = buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val id = o.optString("id").trim()
                    if (id.isEmpty()) continue
                    add(
                        SessionRecord(
                            id = id,
                            displayName = o.optString("displayName").ifBlank { id },
                            agentKind = AgentKind.fromRaw(o.optString("agentKind")),
                            agentId = o.optString("agentId")
                                .trim()
                                .ifBlank {
                                    AgentKind.fromRaw(o.optString("agentKind")).prefix
                                },
                            role = runCatching {
                                WindowRole.valueOf(
                                    o.optString("role", WindowRole.SHELL_WORKER.name)
                                )
                            }.getOrDefault(WindowRole.SHELL_WORKER),
                            workingMode = o.optInt("workingMode", 0),
                            agentResumeId = o.optString("agentResumeId", ""),
                            autoNamed = o.optBoolean("autoNamed", true),
                            createdAt = o.optLong("createdAt", System.currentTimeMillis()),
                            lastActiveAt = o.optLong("lastActiveAt", System.currentTimeMillis()),
                        )
                    )
                }
            }
            Snapshot(version = version, currentId = currentId, sessions = sessions)
        }.getOrElse { Snapshot() }
    }

    fun save(snapshot: Snapshot) {
        runCatching {
            val arr = JSONArray()
            snapshot.sessions.forEach { rec ->
                arr.put(
                    JSONObject()
                        .put("id", rec.id)
                        .put("displayName", rec.displayName)
                        .put("agentKind", rec.agentKind.prefix)
                        .put("agentId", rec.agentId)
                        .put("role", rec.role.name)
                        .put("workingMode", rec.workingMode)
                        .put("agentResumeId", rec.agentResumeId)
                        .put("autoNamed", rec.autoNamed)
                        .put("createdAt", rec.createdAt)
                        .put("lastActiveAt", rec.lastActiveAt)
                )
            }
            val root = JSONObject()
                .put("version", VERSION)
                .put("currentId", snapshot.currentId)
                .put("sessions", arr)
            val tmp = File(dir, "$FILE_NAME.tmp")
            tmp.writeText(root.toString())
            if (!tmp.renameTo(file)) {
                file.writeText(root.toString())
                tmp.delete()
            }
        }
    }

    companion object {
        private const val DIR_NAME = "session-isolation"
        private const val FILE_NAME = "registry.json"
        const val VERSION = 2
    }
}
