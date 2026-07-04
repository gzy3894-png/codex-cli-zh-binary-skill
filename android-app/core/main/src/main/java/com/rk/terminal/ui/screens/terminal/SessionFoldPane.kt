package com.rk.terminal.ui.screens.terminal

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.io.File

@Composable
fun SessionFoldTimeline(
    runs: List<TerminalSessionFoldRun>,
    onToggle: (String) -> Unit,
    onRemove: (String) -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (runs.isEmpty()) return

    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val maxHeight = (screenHeight * 0.34f).coerceIn(104.dp, 280.dp)

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(max = maxHeight)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.76f),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.18f))
    ) {
        Column(modifier = Modifier.padding(vertical = 6.dp)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 10.dp, end = 6.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "会话",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Text(
                    text = "${runs.size}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                TextButton(onClick = onClear) {
                    Text("清空")
                }
            }
            HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outline.copy(alpha = 0.16f))
            LazyColumn(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(runs.asReversed(), key = { it.id }) { run ->
                    SessionFoldRunRow(
                        run = run,
                        onToggle = { onToggle(run.id) },
                        onRemove = { onRemove(run.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun SessionFoldRunRow(
    run: TerminalSessionFoldRun,
    onToggle: () -> Unit,
    onRemove: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 2.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onToggle)
                .padding(start = 2.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = if (run.collapsed) ">" else "v",
                modifier = Modifier.widthIn(min = 18.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold
            )
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = sessionFoldHeader(run),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = "  ${run.items.size}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                val subtitle = run.summary.ifBlank { run.title }
                if (subtitle.isNotBlank()) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            IconButton(onClick = onRemove) {
                Icon(Icons.Filled.Close, contentDescription = "删除会话折叠")
            }
        }
        if (!run.collapsed) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 22.dp, end = 4.dp, bottom = 4.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                run.items.forEach { item ->
                    SessionFoldItemRow(item)
                }
            }
        }
    }
}

@Composable
private fun SessionFoldItemRow(item: TerminalSessionFoldItem) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(6.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.28f)
    ) {
        Column(modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = sessionFoldKindLabel(item.kind),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "  ${item.title}",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = item.status,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1
                )
            }
            val detail = item.summary.ifBlank {
                item.path.takeIf { it.isNotBlank() }?.let { File(it).name }.orEmpty()
            }
            if (detail.isNotBlank()) {
                Text(
                    text = detail,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

private fun sessionFoldHeader(run: TerminalSessionFoldRun): String {
    val label = if (run.status == "running") "处理中" else "已处理"
    val elapsed = sessionFoldElapsed(run)
    return if (elapsed.isBlank()) label else "$label  $elapsed"
}

private fun sessionFoldElapsed(run: TerminalSessionFoldRun): String {
    val end = if (run.endedAt > 0) run.endedAt else System.currentTimeMillis()
    val seconds = ((end - run.startedAt) / 1000).coerceAtLeast(0)
    if (seconds <= 0) return ""
    if (seconds < 60) return "${seconds}s"
    val minutes = seconds / 60
    val remain = seconds % 60
    if (minutes < 60) {
        return if (remain == 0L) "${minutes}m" else "${minutes}m ${remain}s"
    }
    val hours = minutes / 60
    val remainMinutes = minutes % 60
    return if (remainMinutes == 0L) "${hours}h" else "${hours}h ${remainMinutes}m"
}

private fun sessionFoldKindLabel(kind: TerminalSessionFoldItemKind): String {
    return when (kind) {
        TerminalSessionFoldItemKind.THINKING -> "思考"
        TerminalSessionFoldItemKind.TOOL -> "工具"
        TerminalSessionFoldItemKind.TEXT -> "文本"
        TerminalSessionFoldItemKind.FILE -> "文件"
        TerminalSessionFoldItemKind.BROWSER -> "网页"
        TerminalSessionFoldItemKind.FINAL -> "结果"
    }
}
