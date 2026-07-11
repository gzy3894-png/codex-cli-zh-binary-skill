package com.rk.terminal.session

/**
 * Persisted metadata for one terminal tab.
 * [id] is the stable in-process session key (e.g. main / main1).
 * [displayName] is UI-only and may be renamed freely.
 * [agentResumeId] is the CLI UUID used for resume; never derived from displayName.
 */
data class SessionRecord(
    val id: String,
    val displayName: String,
    val agentKind: AgentKind = AgentKind.CODEX,
    val workingMode: Int = 0,
    val agentResumeId: String = "",
    val autoNamed: Boolean = true,
    val createdAt: Long = System.currentTimeMillis(),
    val lastActiveAt: Long = System.currentTimeMillis(),
) {
    fun withDisplayName(name: String, autoNamed: Boolean = this.autoNamed): SessionRecord =
        copy(
            displayName = name.trim().ifBlank { displayName },
            autoNamed = autoNamed,
            lastActiveAt = System.currentTimeMillis(),
        )

    fun withResumeId(resumeId: String): SessionRecord =
        copy(
            agentResumeId = resumeId.trim(),
            lastActiveAt = System.currentTimeMillis(),
        )

    fun touch(): SessionRecord = copy(lastActiveAt = System.currentTimeMillis())
}
