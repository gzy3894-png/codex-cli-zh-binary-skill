package com.rk.terminal.ui.screens.terminal

import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.rk.terminal.service.SessionService
import com.rk.terminal.session.SessionIsolation
import com.rk.terminal.session.SessionIsolationHooks

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerminalTopBar(
    sessionBinder: SessionService.SessionBinder?,
    onMenuClick: () -> Unit,
    onAddClick: () -> Unit,
    color: Color,
    previewCount: Int = 0,
    latestPreview: TerminalMediaPreview? = null,
    previewExpanded: Boolean = false,
    onPreviewClick: () -> Unit = {},
    browserSnapshot: TerminalBrowserSnapshot = TerminalBrowserSnapshot(),
    browserExpanded: Boolean = false,
    onBrowserClick: () -> Unit = {}
) {
    TopAppBar(
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = Color.Transparent,
            scrolledContainerColor = Color.Transparent
        ),
        title = {
            Column {
                Text(text = "Codex for TUI", color = color)
                sessionBinder?.getService()?.currentSession?.value?.let { (id, mode) ->
                    @Suppress("UNUSED_VARIABLE")
                    val rev = SessionIsolation.revision.value
                    val title = SessionIsolationHooks.titleOf(id)
                    Text(
                        style = MaterialTheme.typography.bodySmall,
                        text = "$title (${TerminalUtils.getNameOfWorkingMode(mode)})",
                        color = color
                    )
                }
            }
        },
        navigationIcon = {
            IconButton(onClick = onMenuClick) {
                Icon(Icons.Default.Menu, null, tint = color)
            }
        },
        actions = {
            TerminalMediaPreviewTopBarButton(
                previewCount = previewCount,
                latestPreview = latestPreview,
                expanded = previewExpanded,
                color = color,
                onClick = onPreviewClick
            )
            TerminalBrowserTopBarButton(
                snapshot = browserSnapshot,
                expanded = browserExpanded,
                color = color,
                onClick = onBrowserClick
            )
            IconButton(onClick = onAddClick) {
                Icon(Icons.Default.Add, null, tint = color)
            }
        }
    )
}
