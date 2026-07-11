package com.rk.terminal.session

/**
 * Fixed agent prefix for terminal session labels.
 * Display names always start with one of these prefixes; resume identity uses UUID separately.
 *
 * Kind is inferred from what the user launches in the shell (or from restore metadata),
 * not from a manual chip in the add-session dialog.
 */
enum class AgentKind(val prefix: String) {
    CODEX("codex"),
    CLAUDE("claude"),
    SHELL("shell");

    fun resumeCommand(resumeId: String): String? {
        val id = resumeId.trim()
        if (id.isEmpty()) return null
        return when (this) {
            CODEX -> "codex resume $id"
            CLAUDE -> "claude --resume $id"
            SHELL -> null
        }
    }

    companion object {
        fun fromRaw(raw: String?): AgentKind {
            val key = raw?.trim()?.lowercase().orEmpty()
            return entries.firstOrNull { it.prefix == key || it.name.equals(key, ignoreCase = true) }
                ?: SHELL
        }

        fun fromDisplayName(displayName: String): AgentKind {
            val lower = displayName.trim().lowercase()
            return entries.firstOrNull { lower.startsWith("${it.prefix}-") || lower == it.prefix }
                ?: SHELL
        }

        /**
         * Infer agent from a shell command line the user submitted.
         * Returns null when the line is not a clear agent launch.
         */
        fun detectLaunch(line: String): AgentKind? {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) return null
            // Strip simple env assignments: FOO=bar claude ...
            val withoutEnv = trimmed.replace(Regex("^(?:[A-Za-z_][A-Za-z0-9_]*=\\S*\\s+)+"), "")
            val tokens = withoutEnv.split(Regex("\\s+")).filter { it.isNotEmpty() }
            if (tokens.isEmpty()) return null
            var i = 0
            // common wrappers
            while (i < tokens.size && tokens[i] in setOf("command", "env", "exec", "nice", "nohup")) {
                i++
                if (i < tokens.size && tokens[i - 1] == "env") {
                    while (i < tokens.size && tokens[i].contains('=')) i++
                }
            }
            if (i >= tokens.size) return null
            val cmd = tokens[i].substringAfterLast('/').lowercase()
            return when {
                cmd == "claude" || cmd.startsWith("claude-") -> CLAUDE
                cmd == "codex" || cmd.startsWith("codex-") -> CODEX
                else -> null
            }
        }
    }
}
