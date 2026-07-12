package com.rk.terminal.session

import android.content.Context
import com.rk.libcommons.alpineHomeDir
import com.rk.libcommons.child
import org.json.JSONObject
import java.io.File

data class AgentDefinition(
    val id: String,
    val displayName: String,
    val commands: Set<String>,
    val kind: AgentKind = AgentKind.SHELL,
    val bindingStrategy: AgentBindingStrategy = AgentBindingStrategy.NONE,
)

enum class AgentBindingStrategy {
    NONE,
    EXPLICIT_SESSION_ID,
    CODEX_SESSION_HOOK,
}

data class AgentLaunch(
    val definition: AgentDefinition,
    val command: String,
)

/**
 * Data-driven launch recognition. Built-ins provide sensible defaults while
 * ~/.codex-for-tui/agents.json can add aliases without an APK update.
 */
object AgentCatalog {
    private val lock = Any()
    private var userFile: File? = null
    private var loadedMtime = Long.MIN_VALUE
    private var definitions: List<AgentDefinition> = builtIns()

    fun init(context: Context) {
        synchronized(lock) {
            userFile = context.applicationContext.alpineHomeDir()
                .child(".codex-for-tui")
                .child("agents.json")
            loadedMtime = Long.MIN_VALUE
            reloadLocked()
        }
    }

    fun all(): List<AgentDefinition> = synchronized(lock) {
        reloadLocked()
        definitions.toList()
    }

    fun find(id: String): AgentDefinition? {
        val key = normalize(id)
        return all().firstOrNull { it.id == key }
    }

    fun detectLaunch(line: String): AgentLaunch? {
        val command = firstCommand(line) ?: return null
        val definition = all().firstOrNull { command in it.commands } ?: return null
        return AgentLaunch(definition, command)
    }

    private fun reloadLocked() {
        val file = userFile
        val mtime = file?.takeIf { it.isFile }?.lastModified() ?: -1L
        if (mtime == loadedMtime) return
        loadedMtime = mtime
        val merged = linkedMapOf<String, AgentDefinition>()
        builtIns().forEach { merged[it.id] = it }
        if (file != null && file.isFile) {
            runCatching {
                val root = JSONObject(file.readText())
                val agents = root.optJSONArray("agents") ?: return@runCatching
                for (index in 0 until agents.length()) {
                    val item = agents.optJSONObject(index) ?: continue
                    val id = normalize(item.optString("id"))
                    if (id.isBlank() || id in merged) continue
                    val aliases = linkedSetOf<String>()
                    val commands = item.optJSONArray("commands")
                    if (commands != null) {
                        for (commandIndex in 0 until commands.length()) {
                            normalize(commands.optString(commandIndex))
                                .takeIf { it.isNotBlank() }
                                ?.let { aliases += it }
                        }
                    }
                    if (aliases.isEmpty()) aliases += id
                    if (aliases.any { alias ->
                            merged.values.any { alias in it.commands }
                        }
                    ) continue
                    merged[id] = AgentDefinition(
                        id = id,
                        displayName = item.optString("displayName")
                            .trim()
                            .ifBlank { id },
                        commands = aliases,
                        kind = AgentKind.SHELL,
                        bindingStrategy = AgentBindingStrategy.NONE,
                    )
                }
            }
        }
        definitions = merged.values.toList()
    }

    private fun firstCommand(line: String): String? {
        val trimmed = line.trim()
        if (trimmed.isEmpty()) return null
        // Compound shell input stays in the launcher. Routing it to another PTY
        // would change shell semantics and make clearing the launcher unsafe.
        if (Regex("""(^|[^\\])(?:[|;&<>])""").containsMatchIn(trimmed)) return null
        val withoutEnv = trimmed.replace(
            Regex("^(?:[A-Za-z_][A-Za-z0-9_]*=\\S*\\s+)+"),
            "",
        )
        val tokens = withoutEnv.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (tokens.isEmpty()) return null
        var index = 0
        while (index < tokens.size && tokens[index] in WRAPPERS) {
            val wrapper = tokens[index++]
            if (wrapper == "env") {
                while (index < tokens.size && tokens[index].contains('=')) index++
            }
        }
        if (index >= tokens.size) return null
        return normalize(tokens[index].substringAfterLast('/'))
    }

    private fun normalize(value: String): String =
        value.trim().lowercase().replace(Regex("[^a-z0-9._+-]"), "")

    private fun builtIns(): List<AgentDefinition> = listOf(
        AgentDefinition(
            "codex", "Codex", setOf("codex"), AgentKind.CODEX,
            AgentBindingStrategy.CODEX_SESSION_HOOK,
        ),
        AgentDefinition(
            "claude", "Claude", setOf("claude"), AgentKind.CLAUDE,
            AgentBindingStrategy.EXPLICIT_SESSION_ID,
        ),
        AgentDefinition(
            "grok", "Grok", setOf("grok"), AgentKind.GROK,
            AgentBindingStrategy.EXPLICIT_SESSION_ID,
        ),
        AgentDefinition("gemini", "Gemini", setOf("gemini")),
        AgentDefinition("opencode", "OpenCode", setOf("opencode", "open")),
        AgentDefinition("qwen-code", "Qwen Code", setOf("qwen", "qwen-code")),
        AgentDefinition("aider", "Aider", setOf("aider")),
        AgentDefinition("goose", "Goose", setOf("goose")),
        AgentDefinition("amp", "Amp", setOf("amp")),
        AgentDefinition("crush", "Crush", setOf("crush")),
        AgentDefinition("cursor-agent", "Cursor Agent", setOf("cursor-agent")),
        AgentDefinition("copilot", "Copilot", setOf("copilot", "github-copilot")),
        AgentDefinition("z", "Z", setOf("z")),
    )

    private val WRAPPERS = setOf("command", "env", "exec", "nice", "nohup")
}
