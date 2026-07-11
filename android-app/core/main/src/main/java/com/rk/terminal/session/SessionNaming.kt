package com.rk.terminal.session

/**
 * Pure helpers for session display names. No Android dependency.
 *
 * IMPORTANT: Do not compile Unicode property classes in Regex here.
 * Android ICU rejects malformed property patterns and can crash during
 * class init (PatternSyntaxException -> ExceptionInInitializerError on
 * 2.5.0 cold start). Prefer Char.isLetterOrDigit / explicit allow-list.
 */
object SessionNaming {
    private val unsafeChars = Regex("[\\r\\n\\t]+")
    private val multiSpace = Regex("\\s+")

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

    /** Strip a known agent prefix from a display name; returns body only. */
    fun stripPrefix(displayName: String): String {
        val cleaned = displayName.trim()
        AgentKind.entries.forEach { k ->
            val p = "${k.prefix}-"
            if (cleaned.lowercase().startsWith(p)) {
                return cleaned.substring(p.length).trim().ifBlank { "新会话" }
            }
            if (cleaned.equals(k.prefix, ignoreCase = true)) {
                return "新会话"
            }
        }
        return cleaned.ifBlank { "新会话" }
    }

    /**
     * Build a prefixed display name. If [title] already has a known prefix, keep/normalize it.
     */
    fun buildDisplayName(kind: AgentKind, title: String): String {
        val cleaned = sanitizeTitle(title)
        if (cleaned.isEmpty()) return defaultTitle(kind)
        val lower = cleaned.lowercase()
        val stripped = stripPrefix(cleaned)
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
        val normalized = raw.replace(unsafeChars, " ")
        val filtered = buildString(normalized.length) {
            for (c in normalized) {
                append(if (isAllowedTitleChar(c)) c else ' ')
            }
        }
        return filtered
            .replace(multiSpace, " ")
            .trim()
            .trim('-', '.', '_')
            .take(MAX_TITLE_LEN)
            .trim()
    }

    /** Letters, digits, space, and a small punctuation allow-list for titles. */
    private fun isAllowedTitleChar(c: Char): Boolean {
        return c.isLetterOrDigit() ||
            c.isWhitespace() ||
            c == '.' ||
            c == '_' ||
            c == '-'
    }

    /** Lines that should not become the session title (launch cmds / shell noise). */
    fun isNoiseForAutoName(message: String): Boolean {
        val t = message.trim()
        if (t.length < 2) return true
        if (AgentKind.detectLaunch(t) != null) return true
        val first = t.substringBefore(' ').lowercase()
        if (first in setOf(
                "exit", "logout", "clear", "reset", "cd", "ls", "pwd",
                "export", "unset", "source", ".", "bash", "sh", "zsh",
                "history", "true", "false", ":",
            )
        ) {
            return true
        }
        return false
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
