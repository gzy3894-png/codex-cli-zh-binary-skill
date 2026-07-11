package com.rk.terminal.ui.screens.terminal

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.rk.resources.strings
import com.rk.terminal.service.SessionService
import com.rk.terminal.session.AgentKind
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
    onSessionSelected: (String) -> Unit
) {
    val isolationRevision = SessionIsolation.revision.value
    var renameTarget by remember { mutableStateOf<String?>(null) }
    var renameDraft by remember { mutableStateOf("") }

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
                    text = stringResource(strings.session),
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
                        Icon(imageVector = Icons.Default.Add, contentDescription = null)
                    }
                }
            }

            @Suppress("UNUSED_EXPRESSION")
            isolationRevision

            sessionBinder?.getService()?.sessionList?.keys?.toList()?.let { sessions ->
                LazyColumn {
                    items(sessions, key = { it }) { sessionId ->
                        val isSelected = sessionId == sessionBinder.getService().currentSession.value.first
                        val title = SessionIsolationHooks.titleOf(sessionId)
                        SelectableCard(
                            selected = isSelected,
                            onSelect = { onSessionSelected(sessionId) },
                            onLongClick = {
                                renameTarget = sessionId
                                val prefix = SessionIsolation.record(sessionId)?.agentKind?.prefix ?: AgentKind.CODEX.prefix
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

                                if (!isSelected) {
                                    IconButton(
                                        onClick = { sessionBinder.terminateSession(sessionId) },
                                        modifier = Modifier.size(24.dp)
                                    ) {
                                        Icon(
                                            imageVector = Icons.Outlined.Delete,
                                            contentDescription = null,
                                            modifier = Modifier.size(20.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    renameTarget?.let { targetId ->
        AlertDialog(
            onDismissRequest = { renameTarget = null },
            title = { Text("重命名会话") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = "前缀固定为 ${SessionIsolation.record(targetId)?.agentKind?.prefix ?: "codex"}-",
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
