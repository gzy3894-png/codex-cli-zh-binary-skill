package com.rk.terminal.ui.screens.terminal

import android.net.Uri
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.load
import com.github.chrisbanes.photoview.PhotoView
import java.io.File

@Composable
fun MediaPreviewPane(
    preview: TerminalMediaPreview?,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    preview ?: return

    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val targetHeight = screenHeight * 0.36f
    val paneHeight = when {
        targetHeight < 150.dp -> 150.dp
        targetHeight > 360.dp -> 360.dp
        else -> targetHeight
    }
    val shape = RoundedCornerShape(8.dp)

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 6.dp),
        shape = shape,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 4.dp,
        shadowElevation = 2.dp
    ) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(40.dp)
                    .padding(start = 12.dp, end = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                val kindLabel = when (preview.kind) {
                    TerminalMediaPreviewKind.IMAGE -> "图片"
                    TerminalMediaPreviewKind.VIDEO -> "视频"
                }
                Text(
                    text = "$kindLabel  ${preview.name}",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                IconButton(onClick = onClose) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "关闭预览"
                    )
                }
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(paneHeight)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)),
                contentAlignment = Alignment.Center
            ) {
                when (preview.kind) {
                    TerminalMediaPreviewKind.IMAGE -> ImagePreview(preview)
                    TerminalMediaPreviewKind.VIDEO -> VideoPreview(preview)
                }
            }
        }
    }
}

@Composable
private fun ImagePreview(preview: TerminalMediaPreview) {
    val mediaFile = remember(preview.path) { File(preview.path) }
    AndroidView(
        factory = { viewContext ->
            PhotoView(viewContext).apply {
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
                contentDescription = preview.name
                scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
                setMaximumScale(8f)
                setMediumScale(3f)
                load(mediaFile) {
                    crossfade(true)
                }
            }
        },
        update = { photoView ->
            photoView.contentDescription = preview.name
            photoView.load(mediaFile) {
                crossfade(true)
            }
        },
        modifier = Modifier.fillMaxSize()
    )
}

@Composable
private fun VideoPreview(preview: TerminalMediaPreview) {
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
        modifier = Modifier.fillMaxSize()
    )
}
