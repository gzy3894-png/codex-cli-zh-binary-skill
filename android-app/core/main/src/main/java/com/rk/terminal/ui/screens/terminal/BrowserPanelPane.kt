package com.rk.terminal.ui.screens.terminal

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

@Composable
fun TerminalBrowserTopBarButton(
    snapshot: TerminalBrowserSnapshot,
    expanded: Boolean,
    color: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (!snapshot.available) return

    Surface(
        modifier = modifier
            .padding(end = 4.dp)
            .height(28.dp)
            .widthIn(min = 62.dp, max = 92.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(14.dp),
        color = if (expanded) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)
        } else {
            MaterialTheme.colorScheme.surface.copy(alpha = 0.62f)
        },
        border = BorderStroke(1.dp, color.copy(alpha = 0.34f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(7.dp)
                    .background(
                        if (snapshot.needsUser) {
                            Color(0xFFE09A21)
                        } else if (snapshot.isLoading) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            Color(0xFF2EAD5B)
                        },
                        RoundedCornerShape(6.dp)
                    )
            )
            Text(
                text = "浏览器",
                color = color,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
        }
    }
}

@Composable
fun TerminalBrowserTray(
    snapshot: TerminalBrowserSnapshot,
    browserSessionManager: TerminalBrowserSessionManager,
    onCollapse: () -> Unit,
    onClose: () -> Unit,
    onUserDone: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (!snapshot.available) return

    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val trayHeight = (screenHeight * 0.58f).coerceIn(280.dp, 560.dp)

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .height(trayHeight)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.90f),
        tonalElevation = 3.dp,
        shadowElevation = 2.dp
    ) {
        Column {
            BrowserTrayHeader(
                snapshot = snapshot,
                onCollapse = onCollapse,
                onClose = onClose,
                onUserDone = onUserDone,
                onSelectTab = browserSessionManager::selectTabFromUi,
                onCloseTab = browserSessionManager::closeTabFromUi
            )
            HorizontalDivider(thickness = 0.5.dp)
            BrowserWebViewHost(
                activeTabId = snapshot.activeTabId,
                browserSessionManager = browserSessionManager,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            )
        }
    }
}

@Composable
private fun BrowserTrayHeader(
    snapshot: TerminalBrowserSnapshot,
    onCollapse: () -> Unit,
    onClose: () -> Unit,
    onUserDone: () -> Unit,
    onSelectTab: (Int) -> Unit,
    onCloseTab: (Int) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 12.dp, top = 8.dp, end = 4.dp, bottom = 6.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (snapshot.title.isBlank()) "Agent Browser" else snapshot.title,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = snapshot.currentUrl.ifBlank { snapshot.message },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            TextButton(onClick = onCollapse) {
                Text("折叠")
            }
            IconButton(onClick = onClose, modifier = Modifier.size(42.dp)) {
                Icon(Icons.Filled.Close, contentDescription = "关闭浏览器")
            }
        }
        if (snapshot.needsUser || snapshot.message.isNotBlank()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = snapshot.message.ifBlank { "等待页面操作" },
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelSmall,
                    color = if (snapshot.needsUser) Color(0xFFE09A21) else MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                if (snapshot.needsUser) {
                    Spacer(modifier = Modifier.size(8.dp))
                    TextButton(onClick = onUserDone) {
                        Text("继续")
                    }
                }
            }
        }
        if (snapshot.tabs.size > 1) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                snapshot.tabs.forEach { tab ->
                    BrowserTabChip(
                        tab = tab,
                        active = tab.id == snapshot.activeTabId,
                        onSelect = { onSelectTab(tab.id) },
                        onClose = { onCloseTab(tab.id) },
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun BrowserTabChip(
    tab: TerminalBrowserTabSnapshot,
    active: Boolean,
    onSelect: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .height(30.dp)
            .clickable(onClick = onSelect),
        shape = RoundedCornerShape(7.dp),
        color = if (active) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.16f)
        } else {
            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.30f)
        },
        border = BorderStroke(
            1.dp,
            if (active) {
                MaterialTheme.colorScheme.primary.copy(alpha = 0.32f)
            } else {
                MaterialTheme.colorScheme.outline.copy(alpha = 0.18f)
            }
        )
    ) {
        Row(
            modifier = Modifier.padding(start = 7.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .background(
                        if (tab.isLoading) MaterialTheme.colorScheme.primary else Color(0xFF2EAD5B),
                        RoundedCornerShape(3.dp)
                    )
            )
            Text(
                text = tab.title.ifBlank { tab.url.ifBlank { "标签 ${tab.id}" } },
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Box(
                modifier = Modifier
                    .size(20.dp)
                    .clickable(onClick = onClose),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "关闭标签",
                    modifier = Modifier.size(13.dp)
                )
            }
        }
    }
}

@Composable
private fun BrowserWebViewHost(
    activeTabId: Int?,
    browserSessionManager: TerminalBrowserSessionManager,
    modifier: Modifier = Modifier
) {
    DisposableEffect(activeTabId, browserSessionManager) {
        onDispose {
            browserSessionManager.releaseHostedTab(activeTabId)
        }
    }
    key(activeTabId) {
        AndroidView(
            factory = { context ->
                browserSessionManager.hostWebView(context)
            },
            update = {
                browserSessionManager.updateHostedWebView(it)
            },
            modifier = modifier
                .fillMaxSize()
                .background(Color.White)
        )
    }
}
