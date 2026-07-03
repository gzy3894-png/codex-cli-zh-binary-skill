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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.DividerDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
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
    if (previewCount <= 0 || latestPreview == null) return

    Surface(
        modifier = modifier
            .padding(end = 6.dp)
            .height(36.dp)
            .widthIn(min = 74.dp, max = 126.dp)
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
            modifier = Modifier.padding(horizontal = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            TopBarPreviewThumb(preview = latestPreview)
            Text(
                text = if (previewCount > 99) "99+" else previewCount.toString(),
                color = color,
                style = MaterialTheme.typography.labelLarge,
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
            .size(24.dp)
            .clip(RoundedCornerShape(12.dp))
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
        } else {
            Text(
                text = "视频",
                color = Color.White,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1
            )
        }
    }
}

@Composable
fun TerminalMediaPreviewTray(
    previews: SnapshotStateList<TerminalMediaPreview>,
    onCollapse: () -> Unit,
    onClear: () -> Unit,
    onRemove: (TerminalMediaPreview) -> Unit,
    modifier: Modifier = Modifier
) {
    if (previews.isEmpty()) return

    val listState = rememberLazyListState()
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val trayHeight = (screenHeight * 0.46f).coerceIn(240.dp, 460.dp)
    var dialogState by remember { mutableStateOf<PreviewDialogState?>(null) }
    val imagePreviews = previews.filter { it.kind == TerminalMediaPreviewKind.IMAGE }

    LaunchedEffect(previews.size) {
        if (previews.isNotEmpty()) {
            listState.animateScrollToItem(previews.lastIndex)
        }
    }

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .height(trayHeight)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
        tonalElevation = 3.dp,
        shadowElevation = 2.dp
    ) {
        Column {
            PreviewTrayHeader(
                count = previews.size,
                onCollapse = onCollapse,
                onClear = onClear
            )
            HorizontalDivider(
                color = DividerDefaults.color.copy(alpha = 0.7f),
                thickness = 0.5.dp
            )
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                itemsIndexed(
                    items = previews,
                    key = { _, item -> item.stamp }
                ) { _, preview ->
                    PreviewFeedCard(
                        preview = preview,
                        imagePreviews = imagePreviews,
                        onOpen = { dialogState = it },
                        onRemove = { onRemove(preview) }
                    )
                }
            }
        }
    }

    dialogState?.let { state ->
        MediaPreviewDialog(
            state = state,
            onDismiss = { dialogState = null }
        )
    }
}

@Composable
private fun PreviewTrayHeader(
    count: Int,
    onCollapse: () -> Unit,
    onClear: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(44.dp)
            .padding(start = 12.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "预览托盘",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
            Text(
                text = "共 $count 个媒体项，长按图片可分享",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        TextButton(onClick = onCollapse) {
            Text("折叠")
        }
        TextButton(onClick = onClear) {
            Text("清空")
        }
    }
}

@Composable
private fun PreviewFeedCard(
    preview: TerminalMediaPreview,
    imagePreviews: List<TerminalMediaPreview>,
    onOpen: (PreviewDialogState) -> Unit,
    onRemove: () -> Unit
) {
    val kindLabel = when (preview.kind) {
        TerminalMediaPreviewKind.IMAGE -> "图片"
        TerminalMediaPreviewKind.VIDEO -> "视频"
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
                        }
                    )
                }
                TerminalMediaPreviewKind.VIDEO -> {
                    VideoPreviewCard(
                        preview = preview,
                        onFullscreen = { onOpen(PreviewDialogState.Video(preview)) }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ImagePreviewCard(preview: TerminalMediaPreview, onClick: () -> Unit) {
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
                onLongClick = { sharePreview(context, preview) }
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
private fun MediaPreviewDialog(
    state: PreviewDialogState,
    onDismiss: () -> Unit
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
                onDismiss = onDismiss
            )
            is PreviewDialogState.Video -> VideoPreviewDialogContent(
                preview = state.preview,
                onDismiss = onDismiss
            )
        }
    }
}

@Composable
private fun ImagePreviewDialogContent(
    state: PreviewDialogState.Images,
    onDismiss: () -> Unit
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
                onLongPress = { sharePreview(context, preview) },
                modifier = Modifier.fillMaxSize()
            )
        }
        PreviewDialogTopBar(
            title = if (state.images.size > 1) {
                "${pagerState.currentPage + 1} / ${state.images.size}"
            } else {
                state.images.firstOrNull()?.name ?: "图片"
            },
            onShare = { sharePreview(context, state.images[pagerState.currentPage]) },
            onDismiss = onDismiss
        )
    }
}

@Composable
private fun VideoPreviewDialogContent(
    preview: TerminalMediaPreview,
    onDismiss: () -> Unit
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
            onShare = { sharePreview(context, preview) },
            onDismiss = onDismiss
        )
    }
}

@Composable
private fun PreviewDialogTopBar(
    title: String,
    onDismiss: () -> Unit,
    onShare: (() -> Unit)? = null
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

private fun sharePreview(context: Context, preview: TerminalMediaPreview) {
    try {
        val source = File(preview.path)
        if (!source.isFile || !source.canRead()) {
            toast("文件不可读，无法分享")
            return
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
        context.startActivity(Intent.createChooser(intent, "分享预览"))
    } catch (error: Exception) {
        toast("分享失败：${error.message}")
    }
}

private fun TerminalMediaPreview.mimeType(): String {
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
    }
}

private sealed class PreviewDialogState {
    data class Images(
        val images: List<TerminalMediaPreview>,
        val initialIndex: Int
    ) : PreviewDialogState()

    data class Video(val preview: TerminalMediaPreview) : PreviewDialogState()
}
