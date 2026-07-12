package com.rk.terminal.ui.screens.terminal

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.rk.terminal.service.SessionService
import com.rk.terminal.session.AgentKind
import com.rk.terminal.session.ConversationManager
import com.rk.terminal.session.ConversationRecord
import com.rk.terminal.session.SessionIsolation
import com.rk.terminal.session.SessionIsolationHooks
import com.rk.terminal.ui.routes.MainActivityRoutes

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TerminalDrawer(
    drawerWidth: androidx.compose.ui.unit.Dp,
    sessionBinder: SessionService.SessionBinder?,
    navController: NavController,
    onAddSession: () -> Unit,
    onSessionSelected: (String) -> Unit,
    onConversationSelected: (ConversationRecord) -> Unit = {},
    onConversationArchived: (String) -> Unit = {},
    /** Close a terminal window (kill PTY). Not an agent-session delete. */
    onCloseWindow: (String) -> Unit = {},
) {
    val isolationRevision = SessionIsolation.revision.value
    val conversationRevision = ConversationManager.revision.value
    var renameTarget by remember { mutableStateOf<String?>(null) }
    var renameDraft by remember { mutableStateOf("") }
    // Snapshot keys for LazyColumn — never iterate the live map during remove.
    val sessions = sessionBinder?.getService()?.sessionList?.keys?.toList().orEmpty()
    val currentId = sessionBinder?.getService()?.currentSession?.value?.first.orEmpty()
    @Suppress("UNUSED_VARIABLE")
    val _isolationTick = isolationRevision
    @Suppress("UNUSED_VARIABLE")
    val _conversationTick = conversationRevision
    val conversations = ConversationManager.visible.toList()
    val codexConversations = conversations.filter { it.agentKind == AgentKind.CODEX }
    val claudeConversations = conversations.filter { it.agentKind == AgentKind.CLAUDE }
    var codexExpanded by rememberSaveable { mutableStateOf(true) }
    var claudeExpanded by rememberSaveable { mutableStateOf(true) }
    var windowsExpanded by rememberSaveable { mutableStateOf(true) }
    val currentConversationId = sessionBinder
        ?.getService()
        ?.currentSession
        ?.value
        ?.first
        ?.let { SessionIsolation.record(it)?.agentResumeId }
        .orEmpty()

    ModalDrawerSheet(modifier = Modifier.width(drawerWidth)) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "对话",
                    style = MaterialTheme.typography.titleLarge
                )

                Row {
                    val keyboardController = LocalSoftwareKeyboardController.current
                    IconButton(onClick = {
                        navController.navigate(MainActivityRoutes.Settings.route)
                        keyboardController?.hide()
                    }) {
                        Icon(imageVector = Icons.Outlined.Settings, contentDescription = null)
                    }

                    IconButton(onClick = onAddSession) {
                        Icon(imageVector = Icons.Default.Add, contentDescription = "新建窗口")
                    }
                }
            }

            LazyColumn {
                if (conversations.isEmpty()) {
                    item {
                        Text(
                            text = "未发现 Codex/Claude 历史；在终端启动 agent 后会自动导入。",
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(horizontal = 16.dp)
                        )
                    }
                }
                item(key = "codex-section") {
                    ConversationSectionHeader(
                        title = "Codex 对话",
                        count = codexConversations.size,
                        expanded = codexExpanded,
                        onToggle = { codexExpanded = !codexExpanded },
                    )
                }
                if (codexExpanded) {
                    items(codexConversations, key = { "codex-conversation-${it.id}" }) { conversation ->
                        ConversationCard(
                            conversation = conversation,
                            selected = conversation.id == currentConversationId,
                            onSelect = { onConversationSelected(conversation) },
                            onArchive = { onConversationArchived(conversation.id) },
                        )
                    }
                }

                item(key = "claude-section") {
                    ConversationSectionHeader(
                        title = "Claude 对话",
                        count = claudeConversations.size,
                        expanded = claudeExpanded,
                        onToggle = { claudeExpanded = !claudeExpanded },
                    )
                }
                if (claudeExpanded) {
                    items(claudeConversations, key = { "claude-conversation-${it.id}" }) { conversation ->
                        ConversationCard(
                            conversation = conversation,
                            selected = conversation.id == currentConversationId,
                            onSelect = { onConversationSelected(conversation) },
                            onArchive = { onConversationArchived(conversation.id) },
                        )
                    }
                }

                if (sessions.isNotEmpty()) {
                    item(key = "window-section") {
                        ConversationSectionHeader(
                            title = "终端窗口",
                            count = sessions.size,
                            expanded = windowsExpanded,
                            onToggle = { windowsExpanded = !windowsExpanded },
                        )
                    }
                    if (windowsExpanded) {
                        items(sessions, key = { "window-$it" }) { sessionId ->
                            val isSelected = sessionId == currentId
                            val title = SessionIsolationHooks.titleOf(sessionId)
                            SelectableCard(
                                selected = isSelected,
                                onSelect = { onSessionSelected(sessionId) },
                                onLongClick = {
                                    renameTarget = sessionId
                                    val prefix = SessionIsolation.record(sessionId)?.agentKind?.prefix
                                        ?: AgentKind.SHELL.prefix
                                    renameDraft = title
                                        .removePrefix("$prefix-")
                                        .ifBlank { title }
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(8.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        text = title,
                                        style = MaterialTheme.typography.bodyLarge,
                                        modifier = Modifier.weight(1f)
                                    )
                                    IconButton(
                                        onClick = { onCloseWindow(sessionId) },
                                        modifier = Modifier.size(24.dp)
                                    ) {
                                        Icon(
                                            imageVector = Icons.Outlined.Delete,
                                            contentDescription = "关闭窗口",
                                            modifier = Modifier.size(20.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                } else {
                    item(key = "window-section-empty") {
                        ConversationSectionHeader(
                            title = "终端窗口",
                            count = 0,
                            expanded = windowsExpanded,
                            onToggle = { windowsExpanded = !windowsExpanded },
                        )
                    }
                    if (windowsExpanded) {
                        item(key = "window-empty") {
                            Text(
                                text = "暂无终端窗口",
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                            )
                        }
                    }
                }
            }
        }
    }

    renameTarget?.let { targetId ->
        AlertDialog(
            onDismissRequest = { renameTarget = null },
            title = { Text("重命名窗口") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = "窗口标签前缀固定为 ${SessionIsolation.record(targetId)?.agentKind?.prefix ?: "shell"}-（关闭窗口不会删除对话）",
                        style = MaterialTheme.typography.bodySmall
                    )
                    OutlinedTextField(
                        value = renameDraft,
                        onValueChange = { renameDraft = it },
                        singleLine = true,
                        label = { Text("名称") }
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        SessionIsolation.rename(targetId, renameDraft)
                        renameTarget = null
                    }
                ) { Text("保存") }
            },
            dismissButton = {
                TextButton(onClick = { renameTarget = null }) { Text("取消") }
            }
        )
    }
}

@Composable
private fun ConversationSectionHeader(
    title: String,
    count: Int,
    expanded: Boolean,
    onToggle: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "$title ($count)",
            style = MaterialTheme.typography.titleMedium,
        )
        Icon(
            imageVector = if (expanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
            contentDescription = if (expanded) "折叠$title" else "展开$title",
        )
    }
}

@Composable
private fun ConversationCard(
    conversation: ConversationRecord,
    selected: Boolean,
    onSelect: () -> Unit,
    onArchive: () -> Unit,
) {
    SelectableCard(
        selected = selected,
        onSelect = onSelect,
        modifier = Modifier
            .fillMaxWidth()
            .padding(8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = conversation.displayName,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f),
            )
            IconButton(
                onClick = onArchive,
                modifier = Modifier.size(24.dp),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Delete,
                    contentDescription = "归档对话",
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SelectableCard(
    selected: Boolean,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onLongClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    val containerColor by animateColorAsState(
        targetValue = when {
            selected -> MaterialTheme.colorScheme.primaryContainer
            else -> MaterialTheme.colorScheme.surface
        },
        label = "containerColor"
    )

    val colors = CardDefaults.cardColors(
        containerColor = containerColor,
        contentColor = if (selected) {
            MaterialTheme.colorScheme.onPrimaryContainer
        } else {
            MaterialTheme.colorScheme.onSurface
        }
    )
    val elevation = CardDefaults.cardElevation(
        defaultElevation = if (selected) 8.dp else 2.dp
    )

    if (onLongClick != null) {
        Card(
            modifier = modifier.combinedClickable(
                enabled = enabled,
                onClick = onSelect,
                onLongClick = onLongClick
            ),
            colors = colors,
            elevation = elevation
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                content()
            }
        }
    } else {
        Card(
            modifier = modifier,
            colors = colors,
            elevation = elevation,
            enabled = enabled,
            onClick = onSelect
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                content()
            }
        }
    }
}
