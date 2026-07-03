package com.rk.terminal.ui.screens.terminal

import android.widget.FrameLayout
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
            .padding(end = 6.dp)
            .height(36.dp)
            .widthIn(min = 82.dp, max = 136.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(18.dp),
        color = if (expanded) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)
        } else {
            MaterialTheme.colorScheme.surface.copy(alpha = 0.72f)
        },
        border = BorderStroke(1.dp, color.copy(alpha = 0.34f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(11.dp)
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
                style = MaterialTheme.typography.labelLarge,
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
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f),
        tonalElevation = 3.dp,
        shadowElevation = 2.dp
    ) {
        Column {
            BrowserTrayHeader(
                snapshot = snapshot,
                onCollapse = onCollapse,
                onClose = onClose,
                onUserDone = onUserDone
            )
            HorizontalDivider(thickness = 0.5.dp)
            BrowserWebViewHost(
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
    onUserDone: () -> Unit
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
    }
}

@Composable
private fun BrowserWebViewHost(
    browserSessionManager: TerminalBrowserSessionManager,
    modifier: Modifier = Modifier
) {
    var container by remember { mutableStateOf<FrameLayout?>(null) }
    DisposableEffect(container, browserSessionManager) {
        val attachedContainer = container
        onDispose {
            attachedContainer?.let { browserSessionManager.detachFrom(it) }
        }
    }
    AndroidView(
        factory = { context ->
            FrameLayout(context).also {
                container = it
                browserSessionManager.attachTo(it)
            }
        },
        update = {
            browserSessionManager.attachTo(it)
        },
        modifier = modifier
            .fillMaxSize()
            .background(Color.White)
    )
}
