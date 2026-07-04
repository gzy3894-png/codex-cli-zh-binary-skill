package com.rk.terminal.ui.screens.terminal

import android.content.Context
import android.graphics.Typeface
import android.util.TypedValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.lifecycle.ViewModel
import com.google.android.material.R
import com.rk.settings.Settings
import com.rk.terminal.service.SessionService
import com.rk.terminal.ui.activities.terminal.MainActivity
import com.rk.terminal.ui.screens.terminal.virtualkeys.VirtualKeysListener
import com.rk.terminal.ui.screens.terminal.virtualkeys.VirtualKeysView
import com.termux.view.TerminalView
import java.lang.ref.WeakReference

class TerminalViewModel : ViewModel() {
    private var terminalViewRef = WeakReference<TerminalView>(null)
    private var virtualKeysViewRef = WeakReference<VirtualKeysView>(null)

    val terminalView: TerminalView? get() = terminalViewRef.get()
    val virtualKeysView: VirtualKeysView? get() = virtualKeysViewRef.get()

    fun setTerminalView(view: TerminalView?) { terminalViewRef = WeakReference(view) }
    fun setVirtualKeysView(view: VirtualKeysView?) { virtualKeysViewRef = WeakReference(view) }

    var bitmap by mutableStateOf<ImageBitmap?>(null)
    var wallAlpha by mutableFloatStateOf(Settings.wallTransparency)
    var backgroundBlur by mutableFloatStateOf(Settings.background_blur)

    var showToolbar by mutableStateOf(Settings.toolbar)
    var showVirtualKeys by mutableStateOf(Settings.virtualKeys)
    var showHorizontalToolbar by mutableStateOf(Settings.toolbar)
    val mediaPreviews = mutableStateListOf<TerminalMediaPreview>()
    var mediaPreviewExpanded by mutableStateOf(false)
    var browserSnapshot by mutableStateOf(TerminalBrowserSnapshot())
    var browserPanelExpanded by mutableStateOf(false)
    val sessionFoldRuns = mutableStateListOf<TerminalSessionFoldRun>()
    var activeSessionFoldRunId by mutableStateOf("")

    fun addMediaPreview(preview: TerminalMediaPreview) {
        mediaPreviews.removeAll { it.stamp == preview.stamp || it.path == preview.path }
        mediaPreviews.add(preview)
        while (mediaPreviews.size > MAX_MEDIA_PREVIEWS) {
            mediaPreviews.removeAt(0)
        }
    }

    fun clearMediaPreviews() {
        mediaPreviews.clear()
        mediaPreviewExpanded = false
    }

    fun removeMediaPreview(stamp: String) {
        mediaPreviews.removeAll { it.stamp == stamp }
        if (mediaPreviews.isEmpty()) {
            mediaPreviewExpanded = false
        }
    }

    fun updateBrowserSnapshot(snapshot: TerminalBrowserSnapshot) {
        browserSnapshot = snapshot
        if (!snapshot.available) {
            browserPanelExpanded = false
        }
    }

    fun upsertSessionFoldRun(
        runId: String,
        title: String,
        status: String,
        collapsed: Boolean? = null,
        summary: String = ""
    ): TerminalSessionFoldRun {
        val safeRunId = runId.trim().ifBlank { "run-${System.currentTimeMillis()}" }
        val now = System.currentTimeMillis()
        val index = sessionFoldRuns.indexOfFirst { it.id == safeRunId }
        val existing = sessionFoldRuns.getOrNull(index)
        val terminal = status == "done" || status == "failed" || status == "cancelled"
        val resolved = existing?.copy(
            title = title.ifBlank { existing.title },
            status = status.ifBlank { existing.status },
            collapsed = collapsed ?: if (terminal) true else existing.collapsed,
            summary = summary.ifBlank { existing.summary },
            endedAt = if (terminal) now else existing.endedAt
        ) ?: TerminalSessionFoldRun(
            id = safeRunId,
            title = title.ifBlank { "会话处理" },
            status = status.ifBlank { "running" },
            collapsed = collapsed ?: terminal,
            summary = summary,
            startedAt = now,
            endedAt = if (terminal) now else 0L
        )
        if (index == -1) {
            sessionFoldRuns.add(resolved)
        } else {
            sessionFoldRuns[index] = resolved
        }
        if (!terminal) {
            activeSessionFoldRunId = safeRunId
        } else if (activeSessionFoldRunId == safeRunId) {
            activeSessionFoldRunId = ""
        }
        while (sessionFoldRuns.size > MAX_SESSION_FOLD_RUNS) {
            sessionFoldRuns.removeAt(0)
        }
        return resolved
    }

    fun addSessionFoldItem(item: TerminalSessionFoldItem) {
        val runId = item.runId.trim().ifBlank { activeSessionFoldRunId }
        if (runId.isBlank()) return
        val index = sessionFoldRuns.indexOfFirst { it.id == runId }
        val run = if (index == -1) {
            upsertSessionFoldRun(
                runId = runId,
                title = "会话处理",
                status = "running",
                collapsed = false
            )
        } else {
            sessionFoldRuns[index]
        }
        val items = (run.items.filterNot { it.id == item.id } + item.copy(runId = runId))
            .takeLast(MAX_SESSION_FOLD_ITEMS)
        val updated = run.copy(items = items)
        val updatedIndex = sessionFoldRuns.indexOfFirst { it.id == runId }
        if (updatedIndex == -1) {
            sessionFoldRuns.add(updated)
        } else {
            sessionFoldRuns[updatedIndex] = updated
        }
    }

    fun setSessionFoldCollapsed(runId: String, collapsed: Boolean) {
        val index = sessionFoldRuns.indexOfFirst { it.id == runId }
        if (index >= 0) {
            sessionFoldRuns[index] = sessionFoldRuns[index].copy(collapsed = collapsed)
        }
    }

    fun removeSessionFoldRun(runId: String) {
        sessionFoldRuns.removeAll { it.id == runId }
        if (activeSessionFoldRunId == runId) {
            activeSessionFoldRunId = ""
        }
    }

    fun clearSessionFoldRuns() {
        sessionFoldRuns.clear()
        activeSessionFoldRunId = ""
    }

    fun setFont(typeface: Typeface) {
        TerminalUtils.typeface = typeface
        terminalView?.apply {
            setTypeface(typeface)
            onScreenUpdated()
        }
    }

    fun changeSession(context: Context, sessionBinder: SessionService.SessionBinder, sessionId: String) {
        val terminal = terminalView ?: return
        val activity = context as? MainActivity ?: return
        val client = TerminalBackEnd(terminal, activity)
        
        val session = sessionBinder.getSession(sessionId)
            ?: sessionBinder.createSession(sessionId, client, Settings.working_Mode)
            
        session.updateTerminalSessionClient(client)
        terminal.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        terminal.attachSession(session)
        terminal.setTerminalViewClient(client)
        
        terminal.post {
            val typedValue = TypedValue()
            context.theme.resolveAttribute(R.attr.colorOnSurface, typedValue, true)
            terminal.keepScreenOn = true
            terminal.requestFocus()
            terminal.isFocusableInTouchMode = true

            terminal.mEmulator?.mColors?.mCurrentColors?.apply {
                set(256, typedValue.data)
                set(257, TerminalUtils.getBackgroundColor())
                set(258, typedValue.data)
            }
        }
        
        virtualKeysView?.apply {
            virtualKeysViewClient = terminal.mTermSession?.let { VirtualKeysListener(it) }
        }
        
        sessionBinder.getService().currentSession.value = Pair(sessionId, sessionBinder.getService().sessionList[sessionId]!!)
    }
}

private const val MAX_MEDIA_PREVIEWS = 60
private const val MAX_SESSION_FOLD_RUNS = 40
private const val MAX_SESSION_FOLD_ITEMS = 80

enum class TerminalMediaPreviewKind {
    IMAGE,
    VIDEO,
    TEXT
}

enum class TerminalMediaPreviewSource {
    AGENT,
    USER
}

data class TerminalMediaPreview(
    val path: String,
    val name: String,
    val kind: TerminalMediaPreviewKind,
    val stamp: String,
    val width: Int? = null,
    val height: Int? = null,
    val sizeBytes: Long? = null,
    val mimeType: String = "",
    val textPreview: String? = null,
    val source: TerminalMediaPreviewSource = TerminalMediaPreviewSource.AGENT
)

data class TerminalSessionFoldRun(
    val id: String,
    val title: String,
    val status: String,
    val collapsed: Boolean,
    val summary: String = "",
    val startedAt: Long,
    val endedAt: Long = 0L,
    val items: List<TerminalSessionFoldItem> = emptyList()
)

enum class TerminalSessionFoldItemKind {
    THINKING,
    TOOL,
    TEXT,
    FILE,
    BROWSER,
    FINAL
}

data class TerminalSessionFoldItem(
    val id: String,
    val runId: String,
    val kind: TerminalSessionFoldItemKind,
    val title: String,
    val summary: String = "",
    val path: String = "",
    val status: String = "done",
    val stamp: Long = System.currentTimeMillis()
)
