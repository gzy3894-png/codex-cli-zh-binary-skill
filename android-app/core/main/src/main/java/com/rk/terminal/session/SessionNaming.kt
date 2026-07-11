package com.rk.terminal.session

/**
 * Pure helpers for session display names. No Android dependency.
 */
object SessionNaming {
    private val unsafeChars = Regex("[\\r\\n\\t]+")
    private val multiSpace = Regex("\\s+")
    private val nonLabel = Regex("[^\\p{L}\\p{N._\\-\\s]+")

    const val MAX_TITLE_LEN = 32

    fun defaultTitle(kind: AgentKind, ordinal: Int? = null): String {
        val base = when (kind) {
            AgentKind.CODEX -> "新会话"
            AgentKind.CLAUDE -> "新会话"
            AgentKind.SHELL -> "shell"
        }
        return if (ordinal != null && ordinal > 0) {
            "${kind.prefix}-$base$ordinal"
        } else {
            "${kind.prefix}-$base"
        }
    }

    /**
     * Build a prefixed display name. If [title] already has a known prefix, keep/normalize it.
     */
    fun buildDisplayName(kind: AgentKind, title: String): String {
        val cleaned = sanitizeTitle(title)
        if (cleaned.isEmpty()) return defaultTitle(kind)
        val lower = cleaned.lowercase()
        val stripped = AgentKind.entries.fold(cleaned) { acc, k ->
            val p = "${k.prefix}-"
            if (acc.lowercase().startsWith(p)) acc.substring(p.length).trim() else acc
        }.ifBlank { cleaned }
        // If user typed only a known prefix word, keep default body.
        if (AgentKind.entries.any { it.prefix == lower }) {
            return defaultTitle(kind)
        }
        return "${kind.prefix}-${sanitizeTitle(stripped).ifBlank { "会话" }}"
    }

    fun fromFirstUserMessage(kind: AgentKind, message: String): String {
        val line = message
            .lineSequence()
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() }
            .orEmpty()
        return buildDisplayName(kind, line.ifBlank { "新会话" })
    }

    fun sanitizeTitle(raw: String): String {
        return raw
            .replace(unsafeChars, " ")
            .replace(nonLabel, " ")
            .replace(multiSpace, " ")
            .trim()
            .trim('-', '.', '_')
            .take(MAX_TITLE_LEN)
            .trim()
    }

    /** Legacy terminal ids: main, main1, main2... */
    fun nextLegacySessionId(existingIds: Collection<String>): String {
        if ("main" !in existingIds) return "main"
        var index = 1
        while ("main$index" in existingIds) {
            index++
        }
        return "main$index"
    }
}
