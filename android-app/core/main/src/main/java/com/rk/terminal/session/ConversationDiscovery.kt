package com.rk.terminal.session

import android.content.Context
import com.rk.libcommons.alpineHomeDir
import com.rk.libcommons.child
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Read-only adapter for the two CLI transcript layouts shipped in the app.
 *
 * Codex stores `sessions/**/rollout-<uuid>.jsonl`; Claude stores UUID-named
 * JSONL files below `.claude/projects`. The scanner never edits transcript
 * contents and bounds parsing to the first few records.
 */
class ConversationDiscovery(private val context: Context) {
    fun scan(): List<ConversationRecord> {
        val home = context.applicationContext.alpineHomeDir()
        val found = linkedMapOf<String, ConversationRecord>()
        scanTree(
            root = home.child(".codex").child("sessions"),
            kind = AgentKind.CODEX,
            found = found,
        )
        scanTree(
            root = home.child(".claude").child("projects"),
            kind = AgentKind.CLAUDE,
            found = found,
        )
        scanGrok(
            root = home.child(".grok").child("sessions"),
            found = found,
        )
        return found.values.sortedByDescending { it.lastActivityAt }
    }

    private fun scanGrok(
        root: File,
        found: MutableMap<String, ConversationRecord>,
    ) {
        if (!root.isDirectory) return
        root.walkTopDown()
            .filter { it.isFile && it.name == "summary.json" }
            .take(MAX_FILES)
            .forEach { summary ->
                val id = extractConversationId(summary.parentFile?.name.orEmpty())
                    ?: return@forEach
                val rootJson = runCatching { JSONObject(summary.readText()) }.getOrNull()
                val cwd = rootJson
                    ?.optJSONObject("info")
                    ?.optString("cwd")
                    .orEmpty()
                val history = summary.parentFile?.child("chat_history.jsonl")
                val title = history
                    ?.takeIf { it.isFile }
                    ?.let { parseMetadata(it, AgentKind.GROK).first }
                    ?: rootJson?.optString("session_summary")?.takeIf { it.isNotBlank() }
                val activity = maxOf(
                    summary.lastModified(),
                    history?.lastModified() ?: 0L,
                )
                val record = ConversationRecord(
                    id = id,
                    agentKind = AgentKind.GROK,
                    displayName = SessionNaming.buildDisplayName(
                        AgentKind.GROK,
                        title ?: "历史会话",
                    ),
                    workingDirectory = cwd,
                    sourcePath = summary.absolutePath,
                    lastActivityAt = activity.coerceAtLeast(0L),
                )
                val previous = found[id]
                if (previous == null || record.lastActivityAt >= previous.lastActivityAt) {
                    found[id] = record
                }
            }
    }

    private fun scanTree(
        root: File,
        kind: AgentKind,
        found: MutableMap<String, ConversationRecord>,
    ) {
        if (!root.isDirectory) return
        root.walkTopDown()
            .filter { it.isFile && it.extension.equals("jsonl", ignoreCase = true) }
            .take(MAX_FILES)
            .forEach { file ->
                val id = extractConversationId(file.name) ?: return@forEach
                val metadata = parseMetadata(file, kind)
                val record = ConversationRecord(
                    id = id,
                    agentKind = kind,
                    displayName = metadata.first
                        ?: SessionNaming.buildDisplayName(kind, "历史会话"),
                    workingDirectory = metadata.second.orEmpty(),
                    sourcePath = file.absolutePath,
                    lastActivityAt = file.lastModified().coerceAtLeast(0L),
                )
                val previous = found[id]
                if (previous == null || record.lastActivityAt >= previous.lastActivityAt) {
                    found[id] = record
                }
            }
    }

    private fun extractConversationId(name: String): String? {
        val candidate = UUID_PATTERN.find(name)?.value ?: return null
        return runCatching { UUID.fromString(candidate).toString() }.getOrNull()
    }

    private fun parseMetadata(file: File, kind: AgentKind): Pair<String?, String?> {
        var title: String? = null
        var cwd: String? = null
        runCatching {
            file.bufferedReader(Charsets.UTF_8).useLines { lines ->
                lines.take(MAX_RECORDS).forEach { line ->
                    if (title != null && cwd != null) return@forEach
                    val root = runCatching { JSONObject(line) }.getOrNull() ?: return@forEach
                    if (cwd == null) cwd = firstString(root, CWD_KEYS)
                    if (title == null && isUserRecord(root, kind)) {
                        firstUserText(root)?.let {
                            title = SessionNaming.fromFirstUserMessage(kind, it)
                        }
                    }
                }
            }
        }
        return title to cwd
    }

    private fun isUserRecord(root: JSONObject, kind: AgentKind): Boolean {
        val type = root.optString("type").lowercase()
        val payload = root.optJSONObject("payload")
        val payloadType = payload?.optString("type").orEmpty().lowercase()
        val message = root.optJSONObject("message")
        val role = message?.optString("role")?.lowercase()
            ?: root.optString("role").lowercase()
        return role == "user" ||
            type == "user" ||
            payloadType == "user_message" ||
            (kind == AgentKind.CLAUDE && type == "human")
    }

    private fun firstUserText(root: JSONObject): String? {
        val candidates = sequenceOf(
            root.optJSONObject("message"),
            root.optJSONObject("payload"),
            root,
        ).filterNotNull()
        for (candidate in candidates) {
            extractText(candidate)?.takeIf { it.isNotBlank() }?.let { return it }
        }
        return null
    }

    private fun extractText(value: JSONObject): String? {
        val directKeys = listOf("text", "prompt", "input", "content", "message")
        directKeys.forEach { key ->
            val item = value.opt(key)
            when (item) {
                is String -> if (item.isNotBlank()) return item
                is JSONArray -> {
                    val text = buildString {
                        for (index in 0 until item.length()) {
                            val child = item.opt(index)
                            if (child is String) append(child).append('\n')
                            if (child is JSONObject) {
                                child.optString("text").takeIf { it.isNotBlank() }
                                    ?.let { append(it).append('\n') }
                            }
                        }
                    }.trim()
                    if (text.isNotBlank()) return text
                }
                is JSONObject -> extractText(item)?.let { return it }
            }
        }
        value.optJSONObject("message")?.let { extractText(it)?.let { text -> return text } }
        return null
    }

    companion object {
        private const val MAX_FILES = 512
        private const val MAX_RECORDS = 96
        private val UUID_PATTERN = Regex(
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-" +
                "[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        )
        private val CWD_KEYS = listOf("cwd", "working_directory", "project_dir")

        private fun firstString(root: JSONObject, keys: List<String>): String? {
            keys.forEach { key ->
                root.optString(key).takeIf { it.isNotBlank() }?.let { return it }
                root.optJSONObject("payload")?.optString(key)
                    ?.takeIf { it.isNotBlank() }?.let { return it }
                root.optJSONObject("message")?.optString(key)
                    ?.takeIf { it.isNotBlank() }?.let { return it }
            }
            return null
        }
    }
}
