package com.rk.terminal.ui.screens.terminal

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DividerDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.load
import com.github.chrisbanes.photoview.PhotoView
import com.rk.libcommons.toast
import java.io.File

@Composable
fun TerminalMediaPreviewTopBarButton(
    previewCount: Int,
    latestPreview: TerminalMediaPreview?,
    expanded: Boolean,
    color: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .padding(end = 4.dp)
            .height(28.dp)
            .widthIn(min = 52.dp, max = 82.dp)
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
            if (latestPreview != null) {
                TopBarPreviewThumb(preview = latestPreview)
            } else {
                Box(
                    modifier = Modifier
                        .size(18.dp)
                        .clip(RoundedCornerShape(9.dp))
                        .background(Color.Black.copy(alpha = 0.18f)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "+",
                        color = color,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1
                    )
                }
            }
            Text(
                text = if (previewCount <= 0) "文件" else if (previewCount > 99) "99+" else previewCount.toString(),
                color = color,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
        }
    }
}

@Composable
private fun TopBarPreviewThumb(preview: TerminalMediaPreview) {
    Box(
        modifier = Modifier
            .size(18.dp)
            .clip(RoundedCornerShape(9.dp))
            .background(Color.Black.copy(alpha = 0.18f)),
        contentAlignment = Alignment.Center
    ) {
        if (preview.kind == TerminalMediaPreviewKind.IMAGE) {
            val mediaFile = remember(preview.path) { File(preview.path) }
            AndroidView(
                factory = { viewContext ->
                    ImageView(viewContext).apply {
                        scaleType = ImageView.ScaleType.CENTER_CROP
                        load(mediaFile) { crossfade(true) }
                    }
                },
                update = { imageView ->
                    imageView.load(mediaFile) { crossfade(true) }
                },
                modifier = Modifier.fillMaxSize()
            )
        } else if (preview.kind == TerminalMediaPreviewKind.VIDEO) {
            Text(
                text = "视",
                color = Color.White,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1
            )
        } else {
            Text(
                text = "文",
                color = Color.White,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
        }
    }
}

@Composable
fun TerminalMediaPreviewTray(
    previews: SnapshotStateList<TerminalMediaPreview>,
    onCollapse: () -> Unit,
    onPickFile: () -> Unit,
    onClear: () -> Unit,
    onRemove: (TerminalMediaPreview) -> Unit,
    onSendToAi: (TerminalMediaPreview, String) -> Unit,
    onSendManyToAi: (List<TerminalMediaPreview>, String) -> Unit = { items, message ->
        items.forEach { onSendToAi(it, message) }
    },
    onSendText: (String) -> Boolean,
    onPreviewOpened: (TerminalMediaPreview) -> Unit,
    onPreviewClosed: (TerminalMediaPreview?) -> Unit,
    onPreviewShared: (TerminalMediaPreview) -> Unit,
    modifier: Modifier = Modifier
) {
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val trayHeight = (screenHeight * 0.42f).coerceIn(220.dp, 420.dp)
    var dialogState by remember { mutableStateOf<PreviewDialogState?>(null) }
    var showBatchSendDialog by remember { mutableStateOf(false) }
    var selectedStamps by remember { mutableStateOf(setOf<String>()) }
    val displayNames = remember(previews.toList()) { buildPreviewDisplayNames(previews) }
    val imagePreviews = previews.filter { it.kind == TerminalMediaPreviewKind.IMAGE }
    val selectedPreviews = previews.filter { selectedStamps.contains(it.stamp) }
    val openPreview = { preview: TerminalMediaPreview, state: PreviewDialogState ->
        dialogState = state
        onPreviewOpened(preview)
    }
    val toggleSelected = { preview: TerminalMediaPreview ->
        selectedStamps = if (selectedStamps.contains(preview.stamp)) {
            selectedStamps - preview.stamp
        } else {
            selectedStamps + preview.stamp
        }
    }

    // Drop selections for items that no longer exist in the tray.
    val liveStamps = previews.map { it.stamp }.toSet()
    LaunchedEffect(liveStamps) {
        val pruned = selectedStamps.intersect(liveStamps)
        if (pruned != selectedStamps) {
            selectedStamps = pruned
        }
    }

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
            PreviewTrayHeader(
                count = previews.size,
                selectedCount = selectedPreviews.size,
                onCollapse = onCollapse,
                onPickFile = onPickFile,
                onClear = {
                    selectedStamps = emptySet()
                    onClear()
                },
                onSend = {
                    if (selectedPreviews.isEmpty()) {
                        toast("请先勾选要发送的文件")
                    } else {
                        showBatchSendDialog = true
                    }
                },
                onSelectAll = {
                    selectedStamps = if (selectedStamps.size == previews.size && previews.isNotEmpty()) {
                        emptySet()
                    } else {
                        previews.map { it.stamp }.toSet()
                    }
                }
            )
            HorizontalDivider(
                color = DividerDefaults.color.copy(alpha = 0.7f),
                thickness = 0.5.dp
            )
            LazyVerticalGrid(
                columns = GridCells.Adaptive(108.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                item(key = "text-composer") {
                    TextComposerTile(onSendText = onSendText)
                }
                items(
                    items = previews,
                    key = { item -> item.stamp }
                ) { preview ->
                    val displayName = displayNames[preview.stamp] ?: shortPreviewDisplayName(preview, 1)
                    PreviewThumbTile(
                        preview = preview,
                        displayName = displayName,
                        selected = selectedStamps.contains(preview.stamp),
                        imagePreviews = imagePreviews,
                        onOpen = { openPreview(preview, it) },
                        onRemove = {
                            selectedStamps = selectedStamps - preview.stamp
                            onRemove(preview)
                        },
                        onToggleSelect = { toggleSelected(preview) },
                        onShare = { onPreviewShared(preview) }
                    )
                }
            }
        }
    }

    dialogState?.let { state ->
        MediaPreviewDialog(
            state = state,
            onDismiss = {
                onPreviewClosed(state.primaryPreview())
                dialogState = null
            },
            onShare = onPreviewShared
        )
    }

    if (showBatchSendDialog) {
        SendSelectedPreviewsDialog(
            previews = selectedPreviews,
            displayNames = displayNames,
            onDismiss = { showBatchSendDialog = false },
            onConfirm = { message ->
                onSendManyToAi(selectedPreviews, message)
                selectedStamps = emptySet()
                showBatchSendDialog = false
            }
        )
    }
}

@Composable
private fun SendSelectedPreviewsDialog(
    previews: List<TerminalMediaPreview>,
    displayNames: Map<String, String>,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var message by remember(previews.map { it.stamp }.joinToString()) { mutableStateOf("") }
    val labels = previews.map { displayNames[it.stamp] ?: shortPreviewDisplayName(it, 1) }
    val summary = when {
        labels.isEmpty() -> "未选择文件"
        labels.size <= 3 -> labels.joinToString("、")
        else -> labels.take(3).joinToString("、") + " 等 ${labels.size} 项"
    }
    val send = { onConfirm(message.trim()) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("发送已选文件") },
        text = {
            Column {
                Text(
                    text = summary,
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(10.dp))
                OutlinedTextField(
                    value = message,
                    onValueChange = { message = it },
                    label = { Text("附加说明（可选）") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    keyboardActions = KeyboardActions(onDone = { send() }),
                    keyboardOptions = KeyboardOptions.Default.copy(imeAction = ImeAction.Done)
                )
            }
        },
        confirmButton = {
            Button(onClick = send, enabled = previews.isNotEmpty()) {
                Text("发送")
            }
        },
        dismissButton = {
            OutlinedButton(onClick = onDismiss) {
                Text("取消")
            }
        }
    )
}

internal fun buildPreviewDisplayNames(previews: List<TerminalMediaPreview>): Map<String, String> {
    val counters = mutableMapOf<TerminalMediaPreviewKind, Int>()
    val names = linkedMapOf<String, String>()
    previews.forEach { preview ->
        val index = (counters[preview.kind] ?: 0) + 1
        counters[preview.kind] = index
        names[preview.stamp] = shortPreviewDisplayName(preview, index)
    }
    return names
}

internal fun shortPreviewDisplayName(preview: TerminalMediaPreview, index: Int): String {
    val kindLabel = when (preview.kind) {
        TerminalMediaPreviewKind.IMAGE -> "图片"
        TerminalMediaPreviewKind.VIDEO -> "视频"
        TerminalMediaPreviewKind.TEXT -> "文本"
    }
    return "$kindLabel$index"
}

@Composable
private fun TextComposerTile(onSendText: (String) -> Boolean) {
    var text by remember { mutableStateOf("") }
    val send = {
        if (onSendText(text)) {
            text = ""
        }
    }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(154.dp),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f),
        tonalElevation = 1.dp,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.18f))
    ) {
        Column(
            modifier = Modifier.padding(6.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Text(
                text = "文本",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(84.dp),
                placeholder = { Text("输入后发送") },
                textStyle = MaterialTheme.typography.labelSmall,
                minLines = 2,
                maxLines = 3,
                keyboardOptions = KeyboardOptions.Default.copy(imeAction = ImeAction.Default)
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(
                    onClick = send,
                    enabled = text.isNotBlank(),
                    modifier = Modifier.height(30.dp),
                    contentPadding = PaddingValues(horizontal = 8.dp)
                ) {
                    Text("发送", style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}

@Composable
private fun PreviewTrayHeader(
    count: Int,
    selectedCount: Int,
    onCollapse: () -> Unit,
    onPickFile: () -> Unit,
    onClear: () -> Unit,
    onSend: () -> Unit,
    onSelectAll: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 12.dp, end = 4.dp, top = 4.dp, bottom = 2.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(36.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "文件",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1
                )
                Text(
                    text = if (selectedCount > 0) {
                        "已选 $selectedCount / $count"
                    } else {
                        "共 $count 项 · 勾选后点发送"
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Button(
                onClick = onSend,
                enabled = selectedCount > 0,
                modifier = Modifier.height(32.dp),
                contentPadding = PaddingValues(horizontal = 12.dp)
            ) {
                Text(if (selectedCount > 0) "发送($selectedCount)" else "发送")
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(32.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.End
        ) {
            TextButton(onClick = onSelectAll, enabled = count > 0) {
                Text(if (selectedCount == count && count > 0) "取消全选" else "全选")
            }
            TextButton(onClick = onPickFile) {
                Text("添加")
            }
            TextButton(onClick = onCollapse) {
                Text("折叠")
            }
            TextButton(onClick = onClear) {
                Text("清空")
            }
        }
    }
}

@Composable
private fun EmptyPreviewTray(onPickFile: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "暂无文件",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1
            )
            Spacer(modifier = Modifier.height(8.dp))
            TextButton(onClick = onPickFile) {
                Text("添加文件")
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PreviewThumbTile(
    preview: TerminalMediaPreview,
    displayName: String,
    selected: Boolean,
    imagePreviews: List<TerminalMediaPreview>,
    onOpen: (PreviewDialogState) -> Unit,
    onRemove: () -> Unit,
    onToggleSelect: () -> Unit,
    onShare: () -> Unit
) {
    val context = LocalContext.current
    val sourceLabel = when (preview.source) {
        TerminalMediaPreviewSource.AGENT -> "AI"
        TerminalMediaPreviewSource.USER -> "用户"
    }
    val initialIndex = imagePreviews.indexOfFirst { it.stamp == preview.stamp }.coerceAtLeast(0)
    val open = {
        when (preview.kind) {
            TerminalMediaPreviewKind.IMAGE -> onOpen(
                PreviewDialogState.Images(
                    images = imagePreviews,
                    initialIndex = initialIndex
                )
            )
            TerminalMediaPreviewKind.VIDEO -> onOpen(PreviewDialogState.Video(preview))
            TerminalMediaPreviewKind.TEXT -> onOpen(PreviewDialogState.Text(preview))
        }
    }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(154.dp),
        shape = RoundedCornerShape(8.dp),
        color = if (selected) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
        } else {
            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.42f)
        },
        tonalElevation = 1.dp,
        border = if (selected) {
            BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.55f))
        } else {
            null
        }
    ) {
        Column(modifier = Modifier.padding(6.dp)) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(92.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .combinedClickable(
                        onClick = open,
                        onLongClick = {
                            // TEXT: long-press copies body (selection UI is in dialog).
                            // IMAGE/VIDEO: long-press shares file.
                            if (preview.kind == TerminalMediaPreviewKind.TEXT) {
                                if (copyPreviewText(context, preview)) {
                                    onShare()
                                }
                            } else if (sharePreview(context, preview)) {
                                onShare()
                            }
                        }
                    )
                    .background(MaterialTheme.colorScheme.surface),
                contentAlignment = Alignment.Center
            ) {
                PreviewThumbContent(preview = preview, displayName = displayName)
                Text(
                    text = sourceLabel,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(5.dp)
                        .background(
                            Color.Black.copy(alpha = 0.46f),
                            RoundedCornerShape(4.dp)
                        )
                        .padding(horizontal = 5.dp, vertical = 2.dp),
                    color = Color.White,
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1
                )
                Checkbox(
                    checked = selected,
                    onCheckedChange = { onToggleSelect() },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .size(28.dp)
                        .padding(2.dp)
                )
            }
            Spacer(modifier = Modifier.height(5.dp))
            Text(
                text = displayName,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onToggleSelect),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onRemove, modifier = Modifier.size(32.dp)) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "删除预览",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun PreviewThumbContent(preview: TerminalMediaPreview, displayName: String = preview.name) {
    when (preview.kind) {
        TerminalMediaPreviewKind.IMAGE -> {
            val mediaFile = remember(preview.path) { File(preview.path) }
            AndroidView(
                factory = { viewContext ->
                    ImageView(viewContext).apply {
                        scaleType = ImageView.ScaleType.CENTER_CROP
                        contentDescription = displayName
                        load(mediaFile) { crossfade(true) }
                    }
                },
                update = { imageView ->
                    imageView.contentDescription = displayName
                    imageView.load(mediaFile) { crossfade(true) }
                },
                modifier = Modifier.fillMaxSize()
            )
        }
        TerminalMediaPreviewKind.VIDEO -> {
            Text(
                text = displayName.ifBlank { "视频" },
                color = MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
        }
        TerminalMediaPreviewKind.TEXT -> {
            Text(
                text = preview.textPreview.orEmpty()
                    .ifBlank { displayName.ifBlank { "文本" } },
                modifier = Modifier.padding(8.dp),
                color = MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 5,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun PreviewFeedCard(
    preview: TerminalMediaPreview,
    imagePreviews: List<TerminalMediaPreview>,
    onOpen: (PreviewDialogState) -> Unit,
    onRemove: () -> Unit,
    onSendToAi: () -> Unit,
    onShare: (TerminalMediaPreview) -> Unit
) {
    val kindLabel = when (preview.kind) {
        TerminalMediaPreviewKind.IMAGE -> "图片"
        TerminalMediaPreviewKind.VIDEO -> "视频"
        TerminalMediaPreviewKind.TEXT -> "文本"
    }
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.42f),
        tonalElevation = 1.dp
    ) {
        Column(modifier = Modifier.padding(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = kindLabel,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "  ${preview.name}",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                TextButton(onClick = onSendToAi) {
                    Text("发送")
                }
                IconButton(
                    onClick = onRemove,
                    modifier = Modifier.size(32.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "删除预览",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            when (preview.kind) {
                TerminalMediaPreviewKind.IMAGE -> {
                    val initialIndex = imagePreviews.indexOfFirst { it.stamp == preview.stamp }
                        .coerceAtLeast(0)
                    ImagePreviewCard(
                        preview = preview,
                        onClick = {
                            onOpen(
                                PreviewDialogState.Images(
                                    images = imagePreviews,
                                    initialIndex = initialIndex
                                )
                            )
                        },
                        onShare = onShare
                    )
                }
                TerminalMediaPreviewKind.VIDEO -> {
                    VideoPreviewCard(
                        preview = preview,
                        onFullscreen = { onOpen(PreviewDialogState.Video(preview)) }
                    )
                }
                TerminalMediaPreviewKind.TEXT -> {
                    TextPreviewCard(
                        preview = preview,
                        onClick = { onOpen(PreviewDialogState.Text(preview)) }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ImagePreviewCard(
    preview: TerminalMediaPreview,
    onClick: () -> Unit,
    onShare: (TerminalMediaPreview) -> Unit
) {
    val context = LocalContext.current
    val mediaFile = remember(preview.path) { File(preview.path) }
    val ratio = remember(preview.width, preview.height) {
        val width = preview.width ?: 0
        val height = preview.height ?: 0
        if (width > 0 && height > 0) {
            (width.toFloat() / height.toFloat()).coerceIn(0.48f, 2.4f)
        } else {
            16f / 10f
        }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .combinedClickable(
                onClick = onClick,
                onLongClick = {
                    if (sharePreview(context, preview)) {
                        onShare(preview)
                    }
                }
            )
            .background(MaterialTheme.colorScheme.surface)
    ) {
        val targetHeight = (maxWidth.value / ratio).dp.coerceIn(140.dp, 300.dp)
        AndroidView(
            factory = { viewContext ->
                ImageView(viewContext).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    contentDescription = preview.name
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    adjustViewBounds = true
                    load(mediaFile) { crossfade(true) }
                }
            },
            update = { imageView ->
                imageView.contentDescription = preview.name
                imageView.load(mediaFile) { crossfade(true) }
            },
            modifier = Modifier
                .fillMaxWidth()
                .height(targetHeight)
        )
    }
}

@Composable
private fun VideoPreviewCard(
    preview: TerminalMediaPreview,
    onFullscreen: () -> Unit
) {
    Column {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 180.dp, max = 260.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color.Black),
            contentAlignment = Alignment.Center
        ) {
            VideoPlayerSurface(
                preview = preview,
                modifier = Modifier.fillMaxSize()
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End
        ) {
            TextButton(onClick = onFullscreen) {
                Text("全屏")
            }
        }
    }
}

@Composable
private fun TextPreviewCard(
    preview: TerminalMediaPreview,
    onClick: () -> Unit
) {
    val text = preview.textPreview.orEmpty()
    val sizeLabel = remember(preview.sizeBytes) {
        preview.sizeBytes?.let { formatBytes(it) }.orEmpty()
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .background(MaterialTheme.colorScheme.surface)
            .padding(12.dp)
    ) {
        if (sizeLabel.isNotBlank()) {
            Text(
                text = sizeLabel,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1
            )
            Spacer(modifier = Modifier.height(6.dp))
        }
        Text(
            text = text.ifBlank { "空文本或无法预览编码，文件仍可发送。" },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 8,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun MediaPreviewDialog(
    state: PreviewDialogState,
    onDismiss: () -> Unit,
    onShare: (TerminalMediaPreview) -> Unit
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false
        )
    ) {
        when (state) {
            is PreviewDialogState.Images -> ImagePreviewDialogContent(
                state = state,
                onDismiss = onDismiss,
                onShare = onShare
            )
            is PreviewDialogState.Video -> VideoPreviewDialogContent(
                preview = state.preview,
                onDismiss = onDismiss,
                onShare = onShare
            )
            is PreviewDialogState.Text -> TextPreviewDialogContent(
                preview = state.preview,
                onDismiss = onDismiss,
                onShare = onShare
            )
        }
    }
}

@Composable
private fun ImagePreviewDialogContent(
    state: PreviewDialogState.Images,
    onDismiss: () -> Unit,
    onShare: (TerminalMediaPreview) -> Unit
) {
    if (state.images.isEmpty()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
        ) {
            PreviewDialogTopBar(title = "图片", onDismiss = onDismiss)
        }
        return
    }

    val context = LocalContext.current
    val pagerState = rememberPagerState(
        initialPage = state.initialIndex.coerceIn(0, state.images.lastIndex),
        pageCount = { state.images.size }
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize()
        ) { page ->
            val preview = state.images[page]
            PhotoViewSurface(
                preview = preview,
                onLongPress = {
                    if (sharePreview(context, preview)) {
                        onShare(preview)
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
        }
        PreviewDialogTopBar(
            title = if (state.images.size > 1) {
                "${pagerState.currentPage + 1} / ${state.images.size}"
            } else {
                state.images.firstOrNull()?.name ?: "图片"
            },
            onShare = {
                val preview = state.images[pagerState.currentPage]
                if (sharePreview(context, preview)) {
                    onShare(preview)
                }
            },
            onDismiss = onDismiss
        )
    }
}

@Composable
private fun VideoPreviewDialogContent(
    preview: TerminalMediaPreview,
    onDismiss: () -> Unit,
    onShare: (TerminalMediaPreview) -> Unit
) {
    val context = LocalContext.current
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        VideoPlayerSurface(
            preview = preview,
            modifier = Modifier.fillMaxSize()
        )
        PreviewDialogTopBar(
            title = preview.name,
            onShare = {
                if (sharePreview(context, preview)) {
                    onShare(preview)
                }
            },
            onDismiss = onDismiss
        )
    }
}

@Composable
private fun TextPreviewDialogContent(
    preview: TerminalMediaPreview,
    onDismiss: () -> Unit,
    onShare: (TerminalMediaPreview) -> Unit
) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    // Prefer full file body for dialog so copy/selection is not stuck on the 12KB preview slice.
    val body = remember(preview.path, preview.textPreview) {
        loadPreviewTextBody(preview)
    }
    val displayText = body.ifBlank { "空文本或无法预览编码，文件仍可发送。" }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
    ) {
        SelectionContainer(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = 56.dp, start = 16.dp, end = 16.dp, bottom = 16.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    text = displayText,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
        }
        PreviewDialogTopBar(
            title = preview.name,
            onCopy = {
                val text = loadPreviewTextBody(preview)
                if (text.isBlank()) {
                    toast("没有可复制的文本")
                } else {
                    clipboard.setText(AnnotatedString(text))
                    toast("已复制 ${text.length} 字")
                }
            },
            onShare = {
                if (sharePreview(context, preview)) {
                    onShare(preview)
                }
            },
            onDismiss = onDismiss
        )
    }
}

@Composable
private fun PreviewDialogTopBar(
    title: String,
    onDismiss: () -> Unit,
    onShare: (() -> Unit)? = null,
    onCopy: (() -> Unit)? = null
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .background(Color.Black.copy(alpha = 0.42f))
            .padding(start = 16.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            modifier = Modifier.weight(1f),
            color = Color.White,
            style = MaterialTheme.typography.titleSmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        if (onCopy != null) {
            TextButton(onClick = onCopy) {
                Text("复制", color = Color.White)
            }
        }
        if (onShare != null) {
            TextButton(onClick = onShare) {
                Text("分享", color = Color.White)
            }
        }
        IconButton(onClick = onDismiss, modifier = Modifier.size(48.dp)) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "关闭",
                tint = Color.White
            )
        }
    }
}

@Composable
private fun PhotoViewSurface(
    preview: TerminalMediaPreview,
    onLongPress: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val mediaFile = remember(preview.path) { File(preview.path) }
    AndroidView(
        factory = { viewContext ->
            PhotoView(viewContext).apply {
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
                contentDescription = preview.name
                scaleType = ImageView.ScaleType.FIT_CENTER
                setMaximumScale(8f)
                setMediumScale(3f)
                setOnLongClickListener {
                    onLongPress?.invoke()
                    onLongPress != null
                }
                load(mediaFile) { crossfade(true) }
            }
        },
        update = { photoView ->
            photoView.contentDescription = preview.name
            photoView.setOnLongClickListener {
                onLongPress?.invoke()
                onLongPress != null
            }
            photoView.load(mediaFile) { crossfade(true) }
        },
        modifier = modifier
    )
}

@Composable
private fun VideoPlayerSurface(
    preview: TerminalMediaPreview,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val mediaFile = remember(preview.path) { File(preview.path) }
    val player = remember(preview.path) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(Uri.fromFile(mediaFile)))
            playWhenReady = false
            prepare()
        }
    }

    DisposableEffect(player) {
        onDispose {
            player.release()
        }
    }

    AndroidView(
        factory = { viewContext ->
            PlayerView(viewContext).apply {
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                useController = true
                this.player = player
            }
        },
        update = { playerView ->
            playerView.player = player
        },
        modifier = modifier
    )
}

/** Clipboard/share body for TEXT previews. Prefer on-disk file over truncated textPreview. */
private fun loadPreviewTextBody(preview: TerminalMediaPreview, maxChars: Int = 2 * 1024 * 1024): String {
    val file = File(preview.path)
    if (file.isFile && file.canRead()) {
        return runCatching {
            // minSdk 24: avoid InputStream.readNBytes (API 33). Cap by bytes then chars.
            val maxBytes = (maxChars.coerceAtLeast(1) * 4).coerceAtMost(8 * 1024 * 1024)
            file.inputStream().use { input ->
                val buf = ByteArray(maxBytes)
                var n = 0
                while (n < buf.size) {
                    val r = input.read(buf, n, buf.size - n)
                    if (r < 0) break
                    n += r
                }
                String(buf, 0, n, Charsets.UTF_8)
                    .filter { it.code != 0 }
                    .let { if (it.length > maxChars) it.take(maxChars) else it }
            }
        }.getOrElse {
            preview.textPreview.orEmpty()
        }
    }
    return preview.textPreview.orEmpty()
}

private fun copyPreviewText(context: Context, preview: TerminalMediaPreview): Boolean {
    val text = loadPreviewTextBody(preview)
    if (text.isBlank()) {
        toast("没有可复制的文本")
        return false
    }
    return try {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        clipboard.setPrimaryClip(
            android.content.ClipData.newPlainText(preview.name.ifBlank { "codex-preview" }, text)
        )
        toast("已复制 ${text.length} 字")
        true
    } catch (error: Exception) {
        toast("复制失败：${error.message}")
        false
    }
}

private fun sharePreview(context: Context, preview: TerminalMediaPreview): Boolean {
    try {
        val source = File(preview.path)
        if (!source.isFile || !source.canRead()) {
            toast("文件不可读，无法分享")
            return false
        }
        val shareDir = File(context.cacheDir, "media-preview-share").apply { mkdirs() }
        val fileName = preview.name
            .replace(Regex("""[\\/:*?"<>|]"""), "_")
            .ifBlank { source.name.ifBlank { "codex-preview" } }
        val target = File(shareDir, fileName)
        source.copyTo(target, overwrite = true)

        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            target
        )
        val intent = Intent(Intent.ACTION_SEND)
            .setType(preview.mimeType())
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        // Also put plain text for TEXT so share targets that only accept text still work.
        if (preview.kind == TerminalMediaPreviewKind.TEXT) {
            val body = loadPreviewTextBody(preview, maxChars = 256 * 1024)
            if (body.isNotBlank()) {
                intent.putExtra(Intent.EXTRA_TEXT, body)
            }
        }
        context.startActivity(Intent.createChooser(intent, "分享预览"))
        return true
    } catch (error: Exception) {
        toast("分享失败：${error.message}")
        return false
    }
}

private fun TerminalMediaPreview.mimeType(): String {
    if (mimeType.isNotBlank()) return mimeType
    val lower = name.lowercase()
    return when (kind) {
        TerminalMediaPreviewKind.IMAGE -> when {
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".webp") -> "image/webp"
            lower.endsWith(".gif") -> "image/gif"
            lower.endsWith(".bmp") -> "image/bmp"
            else -> "image/png"
        }
        TerminalMediaPreviewKind.VIDEO -> when {
            lower.endsWith(".webm") -> "video/webm"
            lower.endsWith(".mov") -> "video/quicktime"
            lower.endsWith(".3gp") -> "video/3gpp"
            else -> "video/mp4"
        }
        TerminalMediaPreviewKind.TEXT -> when {
            lower.endsWith(".md") || lower.endsWith(".markdown") -> "text/markdown"
            lower.endsWith(".json") -> "application/json"
            lower.endsWith(".csv") -> "text/csv"
            else -> "text/plain"
        }
    }
}

private fun formatBytes(bytes: Long): String {
    if (bytes < 1024) return "$bytes B"
    val kb = bytes / 1024.0
    if (kb < 1024) return String.format("%.1f KB", kb)
    val mb = kb / 1024.0
    if (mb < 1024) return String.format("%.1f MB", mb)
    return String.format("%.1f GB", mb / 1024.0)
}

private sealed class PreviewDialogState {
    data class Images(
        val images: List<TerminalMediaPreview>,
        val initialIndex: Int
    ) : PreviewDialogState()

    data class Video(val preview: TerminalMediaPreview) : PreviewDialogState()

    data class Text(val preview: TerminalMediaPreview) : PreviewDialogState()
}

private fun PreviewDialogState.primaryPreview(): TerminalMediaPreview? {
    return when (this) {
        is PreviewDialogState.Images -> images.getOrNull(initialIndex)
        is PreviewDialogState.Video -> preview
        is PreviewDialogState.Text -> preview
    }
}
