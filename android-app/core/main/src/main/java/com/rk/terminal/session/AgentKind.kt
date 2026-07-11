package com.rk.terminal.session

/**
 * Fixed agent prefix for terminal session labels.
 * Display names always start with one of these prefixes; resume identity uses UUID separately.
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
                ?: CODEX
        }

        fun fromDisplayName(displayName: String): AgentKind {
            val lower = displayName.trim().lowercase()
            return entries.firstOrNull { lower.startsWith("${it.prefix}-") || lower == it.prefix }
                ?: CODEX
        }
    }
}
