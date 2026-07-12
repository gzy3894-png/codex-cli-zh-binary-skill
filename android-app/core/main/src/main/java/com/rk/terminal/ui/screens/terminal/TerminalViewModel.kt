package com.rk.terminal.ui.screens.terminal

import android.content.Context
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
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
import com.rk.terminal.session.SessionIsolation
import com.rk.terminal.session.SessionIsolationHooks
import com.rk.terminal.session.WindowRole
import com.rk.terminal.session.LAUNCHER_WINDOW_ID
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
    private val mediaPreviewExpandedState = mutableStateOf(false)
    var mediaPreviewExpanded: Boolean
        get() = mediaPreviewExpandedState.value
        set(value) {
            if (mediaPreviewExpandedState.value != value) {
                mediaPreviewExpandedState.value = value
            }
        }
    private val browserSnapshotState = mutableStateOf(TerminalBrowserSnapshot())
    var browserSnapshot: TerminalBrowserSnapshot
        get() = browserSnapshotState.value
        private set(value) {
            if (browserSnapshotState.value != value) {
                browserSnapshotState.value = value
            }
        }
    private val browserPanelExpandedState = mutableStateOf(false)
    var browserPanelExpanded: Boolean
        get() = browserPanelExpandedState.value
        set(value) {
            if (browserPanelExpandedState.value != value) {
                browserPanelExpandedState.value = value
            }
        }
    val sessionFoldRuns = mutableStateListOf<TerminalSessionFoldRun>()
    var activeSessionFoldRunId by mutableStateOf("")
    private val sessionFoldTimelineCollapsedState = mutableStateOf(false)
    var sessionFoldTimelineCollapsed: Boolean
        get() = sessionFoldTimelineCollapsedState.value
        private set(value) {
            if (sessionFoldTimelineCollapsedState.value != value) {
                sessionFoldTimelineCollapsedState.value = value
            }
        }

    fun addMediaPreview(preview: TerminalMediaPreview): List<TerminalMediaPreview> {
        if (mediaPreviews.lastOrNull() == preview) return emptyList()
        mediaPreviews.removeAll { it.stamp == preview.stamp || it.path == preview.path }
        mediaPreviews.add(preview)
        val evicted = mutableListOf<TerminalMediaPreview>()
        while (mediaPreviews.size > MAX_MEDIA_PREVIEWS) {
            evicted.add(mediaPreviews.removeAt(0))
        }
        return evicted
    }

    fun clearMediaPreviews() {
        if (mediaPreviews.isNotEmpty()) {
            mediaPreviews.clear()
        }
        if (mediaPreviewExpanded) {
            mediaPreviewExpanded = false
        }
    }

    fun removeMediaPreview(stamp: String) {
        mediaPreviews.removeAll { it.stamp == stamp }
        if (mediaPreviews.isEmpty() && mediaPreviewExpanded) {
            mediaPreviewExpanded = false
        }
    }

    fun updateBrowserSnapshot(snapshot: TerminalBrowserSnapshot) {
        browserSnapshot = snapshot
        if (!snapshot.available && browserPanelExpanded) {
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
            endedAt = if (terminal) existing.endedAt.takeIf { it > 0L } ?: now else existing.endedAt
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
        } else if (existing != resolved) {
            sessionFoldRuns[index] = resolved
        }
        if (!terminal) {
            if (activeSessionFoldRunId != safeRunId) {
                activeSessionFoldRunId = safeRunId
            }
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
        val resolvedItem = item.copy(runId = runId)
        val existingItem = run.items.firstOrNull { it.id == resolvedItem.id }
        val itemForUpdate = if (existingItem != null && existingItem.sameContentAs(resolvedItem)) {
            existingItem
        } else {
            resolvedItem
        }
        val items = (run.items.filterNot { it.id == itemForUpdate.id } + itemForUpdate)
            .takeLast(MAX_SESSION_FOLD_ITEMS)
        if (items == run.items) return
        val updated = run.copy(items = items)
        val updatedIndex = sessionFoldRuns.indexOfFirst { it.id == runId }
        if (updatedIndex == -1) {
            sessionFoldRuns.add(updated)
        } else if (sessionFoldRuns[updatedIndex] != updated) {
            sessionFoldRuns[updatedIndex] = updated
        }
    }

    fun setSessionFoldCollapsed(runId: String, collapsed: Boolean) {
        val index = sessionFoldRuns.indexOfFirst { it.id == runId }
        if (index >= 0 && sessionFoldRuns[index].collapsed != collapsed) {
            sessionFoldRuns[index] = sessionFoldRuns[index].copy(collapsed = collapsed)
        }
    }

    fun updateSessionFoldTimelineCollapsed(collapsed: Boolean) {
        sessionFoldTimelineCollapsed = collapsed
    }

    fun removeSessionFoldRun(runId: String) {
        sessionFoldRuns.removeAll { it.id == runId }
        if (activeSessionFoldRunId == runId) {
            activeSessionFoldRunId = ""
        }
    }

    fun clearSessionFoldRuns() {
        if (sessionFoldRuns.isNotEmpty()) {
            sessionFoldRuns.clear()
        }
        if (activeSessionFoldRunId.isNotBlank()) {
            activeSessionFoldRunId = ""
        }
        if (sessionFoldTimelineCollapsed) {
            sessionFoldTimelineCollapsed = false
        }
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
        val service = sessionBinder.getService()
        // Never crash UI when the target window disappeared mid-click.
        if (!service.sessionList.containsKey(sessionId) && sessionBinder.getSession(sessionId) == null) {
            val fallback = service.sessionList.keys.lastOrNull() ?: return
            if (fallback != sessionId) {
                changeSession(context, sessionBinder, fallback)
            }
            return
        }
        val client = TerminalBackEnd(terminal, activity, sessionId)

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

        val mode = service.sessionList[sessionId] ?: Settings.working_Mode
        service.currentSession.value = Pair(sessionId, mode)
        SessionIsolationHooks.notifyCurrent(sessionId)

    }

    /**
     * Close one terminal window (kill its PTY). PowerShell multi-window model:
     * the drawer entry is a process/window, not an agent conversation row.
     *
     * Order matters for crash safety:
     * 1) Switch/detach UI off the dying PTY while Compose click is still active.
     * 2) Defer terminateSession to the next main-loop turn so drawer recomposition
     *    does not run against a session mid-teardown.
     * 3) terminateSession persists registry drop and requests SIGTERM; user-close
     *    never calls native force teardown.
     */
    fun closeWindow(context: Context, sessionBinder: SessionService.SessionBinder, sessionId: String) {
        val service = sessionBinder.getService()
        if (
            sessionId == LAUNCHER_WINDOW_ID ||
            SessionIsolation.record(sessionId)?.role == WindowRole.LAUNCHER
        ) {
            return
        }
        if (!service.sessionList.containsKey(sessionId) && sessionBinder.getSession(sessionId) == null) {
            return
        }
        val wasCurrent = service.currentSession.value.first == sessionId
        val others = service.sessionList.keys.filter { it != sessionId }

        // Move the TerminalView off the dying PTY before kill.
        if (wasCurrent) {
            val next = others.lastOrNull()
            if (next != null) {
                runCatching { changeSession(context, sessionBinder, next) }
            } else {
                // Defensive fallback: launcher should always be in [others],
                // but detach before removal if lifecycle state is incomplete.
                runCatching {
                    val session = sessionBinder.getSession(sessionId)
                    val terminal = terminalView
                    if (session != null && terminal != null && terminal.currentSession === session) {
                        // Detach the Java view before the PTY reader can invoke
                        // emulator/JNI cleanup. Termux's attachSession(null)
                        // clears mTermSession and makes updateSize() a no-op;
                        // the service drops registry/maps before requesting exit.
                        terminal.attachSession(null)
                    }
                }
            }
        }

        // Defer terminate until after the current Compose frame / click handler returns.
        // terminateSession drops registry before requesting graceful exit.
        Handler(Looper.getMainLooper()).post {
            runCatching {
                sessionBinder.terminateSession(sessionId)
            }.onFailure {
                android.util.Log.e("TerminalViewModel", "closeWindow terminate failed for $sessionId", it)
            }
        }
    }
}

private const val MAX_MEDIA_PREVIEWS = 60
private const val MAX_SESSION_FOLD_RUNS = 40
private const val MAX_SESSION_FOLD_ITEMS = 80

private fun TerminalSessionFoldItem.sameContentAs(other: TerminalSessionFoldItem): Boolean {
    return id == other.id &&
        runId == other.runId &&
        kind == other.kind &&
        title == other.title &&
        summary == other.summary &&
        path == other.path &&
        status == other.status
}

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
