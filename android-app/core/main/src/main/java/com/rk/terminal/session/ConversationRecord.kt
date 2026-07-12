package com.rk.terminal.session

/**
 * A CLI conversation is independent from a terminal window.
 *
 * [id] is the UUID written by Codex/Claude. Closing a PTY must never remove
 * this record; [archived] is the only UI-level removal state.
 */
data class ConversationRecord(
    val id: String,
    val agentKind: AgentKind,
    val displayName: String,
    val workingDirectory: String = "",
    val sourcePath: String = "",
    val lastActivityAt: Long = System.currentTimeMillis(),
    val archived: Boolean = false,
) {
    fun archive(): ConversationRecord = copy(archived = true)

    fun touch(): ConversationRecord =
        copy(lastActivityAt = System.currentTimeMillis())
}
