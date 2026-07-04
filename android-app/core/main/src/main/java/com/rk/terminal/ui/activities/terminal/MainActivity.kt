package com.rk.terminal.ui.activities.terminal

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.OpenableColumns
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.webkit.MimeTypeMap
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.rk.settings.Settings
import com.rk.libcommons.child
import com.rk.libcommons.localDir
import com.rk.libcommons.toast
import com.rk.terminal.ui.navHosts.MainActivityNavHost
import com.rk.terminal.ui.routes.MainActivityRoutes
import com.rk.terminal.ui.screens.terminal.TerminalBrowserSnapshot
import com.rk.terminal.ui.screens.terminal.TerminalBrowserSessionManager
import com.rk.terminal.ui.screens.terminal.TerminalMediaPreview
import com.rk.terminal.ui.screens.terminal.TerminalMediaPreviewKind
import com.rk.terminal.ui.screens.terminal.TerminalMediaPreviewSource
import com.rk.terminal.ui.screens.terminal.TerminalSessionFoldItem
import com.rk.terminal.ui.screens.terminal.TerminalSessionFoldItemKind
import com.rk.terminal.ui.screens.terminal.TerminalViewModel
import com.rk.terminal.ui.theme.KarbonTheme
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

class MainActivity : ComponentActivity() {
    val viewModel: MainViewModel by viewModels()
    lateinit var browserSessionManager: TerminalBrowserSessionManager
        private set
    private val terminalViewModel: TerminalViewModel by viewModels()
    private var isKeyboardVisible = false
    private var wasKeyboardOpen = false
    private var mediaPreviewJob: Job? = null
    private var browserBridgeJob: Job? = null
    private var sessionFoldJob: Job? = null
    private var lastMediaPreviewRequest = ""
    private var lastBrowserRequest = ""
    private var lastSessionFoldRequest = ""
    private var lastBrowserNeedsUserEventKey = ""
    private var browserFileChooserCallback: ((Array<Uri>?) -> Unit)? = null

    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { isGranted ->
            if (!isGranted) {
                // Optional: Handle permission denied
            }
        }

    private val pickPreviewFiles =
        registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
            if (uris.isEmpty()) {
                writeAgentPanelEvent(source = "files", type = "user_file_picker_cancelled", state = "cancelled", reason = "file_picker")
                writeAgentPanelStatus(source = "files", state = "cancelled", reason = "file_picker")
                return@registerForActivityResult
            }
            lifecycleScope.launch {
                uris.forEach { uri ->
                    try {
                        ingestPickedPreviewFile(uri)
                    } catch (error: Exception) {
                        val reason = error.message.orEmpty().ifBlank { error::class.java.simpleName }
                        writeAgentPanelEvent(
                            source = "files",
                            type = "user_file_ingest_failed",
                            state = "error",
                            reason = reason,
                            extra = mapOf("uri" to uri.toString())
                        )
                        writeAgentPanelStatus(
                            source = "files",
                            state = "error",
                            reason = reason,
                            extra = mapOf("uri" to uri.toString())
                        )
                        toast("无法读取文件：$reason")
                    }
                }
            }
        }

    private val pickBrowserUploadFiles =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val callback = browserFileChooserCallback
            browserFileChooserCallback = null
            val data = result.data
            val uris = if (result.resultCode == android.app.Activity.RESULT_OK && data != null) {
                when {
                    data.clipData != null -> {
                        val clipData = data.clipData!!
                        Array(clipData.itemCount) { index -> clipData.getItemAt(index).uri }
                    }
                    data.data != null -> arrayOf(data.data!!)
                    else -> null
                }
            } else {
                null
            }
            writeAgentPanelEvent(
                source = "browser",
                type = if (uris.isNullOrEmpty()) "user_upload_cancelled" else "user_upload_selected",
                state = if (uris.isNullOrEmpty()) "cancelled" else "done",
                reason = "browser_file_chooser",
                extra = mapOf("selected_count" to (uris?.size ?: 0).toString())
            )
            writeAgentPanelStatus(
                source = "browser",
                state = if (uris.isNullOrEmpty()) "cancelled" else "done",
                reason = "browser_file_chooser",
                extra = mapOf("selected_count" to (uris?.size ?: 0).toString())
            )
            callback?.invoke(uris)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        requestPermission()
        browserSessionManager = TerminalBrowserSessionManager(
            context = this,
            onSnapshot = { snapshot ->
                val previous = terminalViewModel.browserSnapshot
                terminalViewModel.updateBrowserSnapshot(snapshot)
                writeBrowserNeedsUserTransition(previous, snapshot)
            },
            launchFileChooser = ::launchBrowserFileChooser
        )

        if (intent.hasExtra("awake_intent")) {
            moveTaskToBack(true)
        }

        setContent {
            KarbonTheme {
                Surface {
                    val navController = rememberNavController()
                    if (viewModel.isBound) {
                        MainActivityNavHost(
                            navController = navController,
                            mainActivity = this@MainActivity
                        )
                    }

                    val backStackEntry by navController.currentBackStackEntryAsState()
                    val focusManager = LocalFocusManager.current
                    val keyboardController = LocalSoftwareKeyboardController.current

                    LaunchedEffect(backStackEntry?.destination?.route) {
                        if (backStackEntry?.destination?.route != MainActivityRoutes.MainScreen.route) {
                            focusManager.clearFocus(force = true)
                            terminalViewModel.terminalView?.clearFocus()
                            keyboardController?.hide()
                        }
                    }
                }
            }
        }
        
        primeMediaPreviewRequestCache()
        primeBrowserRequestCache()
        primeSessionFoldRequestCache()
        setupKeyboardListener()
    }

    override fun onStart() {
        super.onStart()
        viewModel.startAndBindService(this)
        startMediaPreviewBridge()
        startBrowserBridge()
        startSessionFoldBridge()
    }

    override fun onStop() {
        super.onStop()
        mediaPreviewJob?.cancel()
        mediaPreviewJob = null
        browserBridgeJob?.cancel()
        browserBridgeJob = null
        sessionFoldJob?.cancel()
        sessionFoldJob = null
        viewModel.unbindService(this)
    }

    override fun onPause() {
        super.onPause()
        wasKeyboardOpen = isKeyboardVisible
    }

    override fun onResume() {
        super.onResume()
        if (wasKeyboardOpen && !isKeyboardVisible) {
            terminalViewModel.terminalView?.let { terminalView ->
                val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
                imm.showSoftInput(terminalView, InputMethodManager.SHOW_IMPLICIT)
            }
        }
        lifecycleScope.launch {
            pollMediaPreviewRequest()
            pollBrowserRequest()
            pollSessionFoldRequest()
        }
    }

    private fun requestPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                requestNotificationPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        requestAllFilesAccessIfNeeded()
    }

    private fun requestAllFilesAccessIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (Environment.isExternalStorageManager()) return
        if (Settings.ignore_storage_permission) return

        val intent = Intent(
            android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:$packageName")
        )
        runCatching {
            startActivity(intent)
        }.onFailure {
            runCatching {
                startActivity(Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        }
    }

    private fun panelEventId(): String {
        return "${System.currentTimeMillis()}.${(0..9999).random()}"
    }

    private fun writeAgentPanelStatus(
        source: String,
        state: String,
        reason: String = "",
        requestId: String = "",
        itemId: String = "",
        extra: Map<String, String> = emptyMap()
    ) {
        try {
            val visible = when (source) {
                "browser" -> terminalViewModel.browserPanelExpanded
                else -> terminalViewModel.mediaPreviewExpanded
            }
            val mode = if (source == "browser") "browser" else "files"
            val activeItem = itemId.ifBlank {
                if (source == "browser") {
                    terminalViewModel.browserSnapshot.activeTabId?.toString().orEmpty()
                } else {
                    terminalViewModel.mediaPreviews.lastOrNull()?.stamp.orEmpty()
                }
            }
            val extras = panelExtrasFor(source, itemId) + extra
            val status = buildString {
                append("source=").append(source).append('\n')
                append("mode=").append(mode).append('\n')
                append("state=").append(state).append('\n')
                append("visible=").append(if (visible) "1" else "0").append('\n')
                append("collapsed=").append(if (visible) "0" else "1").append('\n')
                append("reason=").append(refValue(reason)).append('\n')
                append("request_id=").append(refValue(requestId)).append('\n')
                append("item_id=").append(refValue(itemId)).append('\n')
                append("active_item=").append(refValue(activeItem)).append('\n')
                appendPanelExtras(extras)
                append("stamp=").append(panelEventId()).append('\n')
            }
            localDir().child("agent-panel").apply { mkdirs() }.child("status").writeText(status)
        } catch (_: Exception) {
            // Best-effort bridge status for terminal-side automation.
        }
    }

    private fun writeAgentPanelEvent(
        source: String,
        type: String,
        state: String = "done",
        reason: String = "",
        requestId: String = "",
        itemId: String = "",
        extra: Map<String, String> = emptyMap()
    ) {
        try {
            val visible = when (source) {
                "browser" -> terminalViewModel.browserPanelExpanded
                else -> terminalViewModel.mediaPreviewExpanded
            }
            val activeItem = if (source == "browser") {
                terminalViewModel.browserSnapshot.activeTabId?.toString().orEmpty()
            } else {
                terminalViewModel.mediaPreviews.lastOrNull()?.stamp.orEmpty()
            }
            val extras = panelExtrasFor(source, itemId) + extra
            val event = buildString {
                append("event_id=").append(panelEventId()).append('\n')
                append("source=").append(source).append('\n')
                append("type=").append(type).append('\n')
                append("state=").append(state).append('\n')
                append("reason=").append(refValue(reason)).append('\n')
                append("request_id=").append(refValue(requestId)).append('\n')
                append("item_id=").append(refValue(itemId)).append('\n')
                append("active_item=").append(refValue(activeItem)).append('\n')
                append("visible=").append(if (visible) "1" else "0").append('\n')
                append("collapsed=").append(if (visible) "0" else "1").append('\n')
                appendPanelExtras(extras)
                append("---\n")
            }
            localDir().child("agent-panel").apply { mkdirs() }.child("events").appendText(event)
        } catch (_: Exception) {
            // Best-effort event bridge for terminal-side automation.
        }
    }

    private fun StringBuilder.appendPanelExtras(extras: Map<String, String>) {
        val reserved = setOf(
            "event_id", "source", "mode", "type", "state", "reason", "request_id",
            "item_id", "active_item", "visible", "collapsed", "stamp"
        )
        extras.toSortedMap().forEach { (key, value) ->
            if (key.isNotBlank() && key !in reserved) {
                append(key).append('=').append(refValue(value)).append('\n')
            }
        }
    }

    private fun panelExtrasFor(source: String, itemId: String): Map<String, String> {
        return if (source == "browser") {
            browserSnapshotExtras(terminalViewModel.browserSnapshot)
        } else {
            val preview = mediaPreviewByRef(itemId) ?: terminalViewModel.mediaPreviews.lastOrNull()
            mediaPreviewExtras(preview)
        }
    }

    private fun mediaPreviewByRef(refId: String): TerminalMediaPreview? {
        if (refId.isBlank()) return null
        return terminalViewModel.mediaPreviews.firstOrNull {
            it.stamp == refId || previewReferenceId(it) == refId
        }
    }

    private fun mediaPreviewExtras(preview: TerminalMediaPreview?): Map<String, String> {
        val extras = mutableMapOf(
            "remaining" to terminalViewModel.mediaPreviews.size.toString()
        )
        if (preview != null) {
            extras["kind"] = preview.kind.name.lowercase(Locale.ROOT)
            extras["path"] = preview.path
            extras["name"] = preview.name
            extras["stamp"] = preview.stamp
            extras["origin"] = preview.source.name.lowercase(Locale.ROOT)
            preview.sizeBytes?.let { extras["size_bytes"] = it.toString() }
            preview.textPreview?.let { extras["text_length"] = it.length.toString() }
        }
        return extras
    }

    private fun browserSnapshotExtras(snapshot: TerminalBrowserSnapshot): Map<String, String> {
        return mapOf(
            "tab_id" to snapshot.activeTabId?.toString().orEmpty(),
            "url" to snapshot.currentUrl,
            "title" to snapshot.title,
            "needs_user" to if (snapshot.needsUser) "1" else "0",
            "tabs_count" to snapshot.tabs.size.toString()
        )
    }

    private fun browserJsonExtras(snapshot: JSONObject?): Map<String, String> {
        return mapOf(
            "tab_id" to snapshot?.opt("activeTabId")?.toString().orEmpty(),
            "url" to snapshot?.optString("currentUrl").orEmpty(),
            "title" to snapshot?.optString("title").orEmpty(),
            "needs_user" to if (snapshot?.optBoolean("needsUser") == true) "1" else "0",
            "tabs_count" to (snapshot?.optJSONArray("tabs")?.length() ?: 0).toString()
        )
    }

    private fun writeSessionFoldStatus(
        state: String,
        reason: String = "",
        requestId: String = "",
        runId: String = "",
        itemId: String = "",
        extra: Map<String, String> = emptyMap()
    ) {
        try {
            val activeRun = runId.ifBlank { terminalViewModel.activeSessionFoldRunId }
            val run = terminalViewModel.sessionFoldRuns.firstOrNull { it.id == activeRun }
                ?: terminalViewModel.sessionFoldRuns.lastOrNull()
            val totalItems = terminalViewModel.sessionFoldRuns.sumOf { it.items.size }
            localDir().child("session-fold").apply { mkdirs() }.child("status").writeText(
                buildString {
                    append("source=session\n")
                    append("state=").append(refValue(state)).append('\n')
                    append("reason=").append(refValue(reason)).append('\n')
                    append("request_id=").append(refValue(requestId)).append('\n')
                    append("run_id=").append(refValue(run?.id ?: activeRun)).append('\n')
                    append("item_id=").append(refValue(itemId)).append('\n')
                    append("active_run=").append(refValue(terminalViewModel.activeSessionFoldRunId)).append('\n')
                    append("collapsed=").append(if (run?.collapsed == true) "1" else "0").append('\n')
                    append("runs=").append(terminalViewModel.sessionFoldRuns.size).append('\n')
                    append("items=").append(totalItems).append('\n')
                    appendSessionFoldExtras(extra)
                    append("stamp=").append(panelEventId()).append('\n')
                }
            )
        } catch (_: Exception) {
            // Best-effort session-fold bridge status.
        }
    }

    private fun writeSessionFoldEvent(
        type: String,
        state: String = "done",
        reason: String = "",
        requestId: String = "",
        runId: String = "",
        itemId: String = "",
        extra: Map<String, String> = emptyMap()
    ) {
        try {
            val run = terminalViewModel.sessionFoldRuns.firstOrNull { it.id == runId }
            val event = buildString {
                append("event_id=").append(panelEventId()).append('\n')
                append("source=session\n")
                append("type=").append(type).append('\n')
                append("state=").append(state).append('\n')
                append("reason=").append(refValue(reason)).append('\n')
                append("request_id=").append(refValue(requestId)).append('\n')
                append("run_id=").append(refValue(runId)).append('\n')
                append("item_id=").append(refValue(itemId)).append('\n')
                append("active_run=").append(refValue(terminalViewModel.activeSessionFoldRunId)).append('\n')
                append("collapsed=").append(if (run?.collapsed == true) "1" else "0").append('\n')
                appendSessionFoldExtras(extra)
                append("---\n")
            }
            localDir().child("session-fold").apply { mkdirs() }.child("events").appendText(event)
        } catch (_: Exception) {
            // Best-effort session-fold event bridge.
        }
    }

    private fun writeSessionFoldResult(
        requestId: String,
        action: String,
        ok: Boolean,
        state: String,
        reason: String,
        runId: String = "",
        itemId: String = "",
        error: String = "",
        extra: Map<String, String> = emptyMap()
    ) {
        try {
            val run = terminalViewModel.sessionFoldRuns.firstOrNull { it.id == runId }
            localDir().child("session-fold").apply { mkdirs() }.child("result").writeText(
                buildString {
                    append("request_id=").append(refValue(requestId)).append('\n')
                    append("action=").append(refValue(action)).append('\n')
                    append("ok=").append(if (ok) "1" else "0").append('\n')
                    append("state=").append(refValue(state)).append('\n')
                    append("reason=").append(refValue(reason)).append('\n')
                    append("run_id=").append(refValue(runId)).append('\n')
                    append("item_id=").append(refValue(itemId)).append('\n')
                    append("active_run=").append(refValue(terminalViewModel.activeSessionFoldRunId)).append('\n')
                    append("collapsed=").append(if (run?.collapsed == true) "1" else "0").append('\n')
                    if (error.isNotBlank()) append("error=").append(refValue(error)).append('\n')
                    appendSessionFoldExtras(extra)
                }
            )
        } catch (_: Exception) {
            // Best-effort session-fold result bridge.
        }
    }

    private fun StringBuilder.appendSessionFoldExtras(extras: Map<String, String>) {
        val reserved = setOf(
            "event_id", "source", "type", "state", "reason", "request_id", "run_id",
            "item_id", "active_run", "collapsed", "runs", "items", "stamp", "ok", "action"
        )
        extras.toSortedMap().forEach { (key, value) ->
            if (key.isNotBlank() && key !in reserved) {
                append(key).append('=').append(refValue(value)).append('\n')
            }
        }
    }

    private fun setupKeyboardListener() {
        val rootView = findViewById<View>(android.R.id.content)
        rootView.viewTreeObserver.addOnGlobalLayoutListener {
            val rect = Rect()
            rootView.getWindowVisibleDisplayFrame(rect)
            val screenHeight = rootView.rootView.height
            val keypadHeight = screenHeight - rect.bottom
            isKeyboardVisible = keypadHeight > screenHeight * 0.15
        }
    }

    fun dismissMediaPreview() {
        val paths = terminalViewModel.mediaPreviews.map { it.path }
        terminalViewModel.clearMediaPreviews()
        lifecycleScope.launch(Dispatchers.IO) {
            paths.forEach { path -> runCatching { File(path).delete() } }
            runCatching { localDir().child("media-preview").child("files").deleteRecursively() }
            runCatching { localDir().child("media-preview").child("refs").deleteRecursively() }
        }
        writeMediaPreviewStatus(localDir().child("media-preview"), "closed=1\n")
        writeAgentPanelEvent(source = "files", type = "user_cleared", state = "closed", reason = "clear")
        writeAgentPanelStatus(source = "files", state = "closed", reason = "clear")
    }

    fun removeMediaPreview(preview: TerminalMediaPreview) {
        val refId = previewReferenceId(preview)
        val previewExtras = mediaPreviewExtras(preview)
        terminalViewModel.removeMediaPreview(preview.stamp)
        lifecycleScope.launch(Dispatchers.IO) {
            runCatching { File(preview.path).delete() }
            runCatching { removePreviewReference(preview) }
        }
        syncMediaPreviewStatus(reason = "delete_item", state = "ready")
        writeAgentPanelEvent(
            source = "files",
            type = "user_deleted",
            state = "ready",
            reason = "delete_item",
            itemId = refId,
            extra = previewExtras + mapOf("remaining" to terminalViewModel.mediaPreviews.size.toString())
        )
        writeAgentPanelStatus(source = "files", state = "ready", reason = "delete_item")
    }

    fun openPreviewFilePicker() {
        writeAgentPanelEvent(source = "files", type = "user_file_picker_opened", state = "waiting_for_user", reason = "file_picker")
        writeAgentPanelStatus(source = "files", state = "waiting_for_user", reason = "file_picker")
        runCatching {
            pickPreviewFiles.launch(
                arrayOf(
                    "text/*",
                    "image/*",
                    "video/*",
                    "application/json",
                    "application/xml",
                    "application/x-yaml"
                )
            )
        }.onFailure { error ->
            writeAgentPanelEvent(source = "files", type = "user_file_picker_failed", state = "error", reason = error.message.orEmpty())
            writeAgentPanelStatus(source = "files", state = "error", reason = error.message.orEmpty())
            toast("无法打开文件管理器：${error.message}")
        }
    }

    fun sendPreviewToAi(preview: TerminalMediaPreview, userMessage: String) {
        val session = terminalViewModel.terminalView?.currentSession
        if (session == null) {
            toast("当前终端会话不可用")
            return
        }

        val refId = previewReferenceId(preview)
        val refWritten = runCatching {
            writePreviewReference(preview, refId)
        }.onFailure { error ->
            toast("无法创建文件引用：${error.message}")
        }.isSuccess
        if (!refWritten) return

        val cleanMessage = collapseTerminalText(userMessage)
        val prompt = buildString {
            append("文件[").append(refId).append("] ")
            if (cleanMessage.isNotBlank()) {
                append(cleanMessage).append("。")
            }
            append("路径：codex-preview path ").append(refId)
            append('\n')
        }
        session.write(prompt)
        writeAgentPanelEvent(
            source = "files",
            type = "user_sent_file",
            state = "done",
            reason = cleanMessage,
            itemId = refId,
            extra = mediaPreviewExtras(preview)
        )
        writeAgentPanelStatus(
            source = "files",
            state = "done",
            reason = "sent_to_terminal",
            itemId = refId
        )
        appendActiveSessionFoldItem(
            kind = TerminalSessionFoldItemKind.FILE,
            title = preview.name,
            summary = cleanMessage,
            path = preview.path,
            status = "done",
            itemId = refId
        )
        toast("已发送：${shortenForTerminal(preview.name, 24)}")
    }

    fun mediaPreviewOpened(preview: TerminalMediaPreview) {
        val refId = previewReferenceId(preview)
        writeAgentPanelEvent(
            source = "files",
            type = "user_opened_preview",
            state = "ready",
            reason = "preview_dialog",
            itemId = refId,
            extra = mediaPreviewExtras(preview)
        )
        writeAgentPanelStatus(source = "files", state = "ready", reason = "preview_dialog", itemId = refId)
    }

    fun mediaPreviewClosed(preview: TerminalMediaPreview?) {
        val refId = preview?.let { previewReferenceId(it) }.orEmpty()
        writeAgentPanelEvent(
            source = "files",
            type = "user_closed_preview",
            state = "ready",
            reason = "preview_dialog",
            itemId = refId,
            extra = mediaPreviewExtras(preview)
        )
        writeAgentPanelStatus(source = "files", state = "ready", reason = "preview_dialog", itemId = refId)
    }

    fun mediaPreviewShared(preview: TerminalMediaPreview) {
        val refId = previewReferenceId(preview)
        writeAgentPanelEvent(
            source = "files",
            type = "user_shared_preview",
            state = "done",
            reason = "share",
            itemId = refId,
            extra = mediaPreviewExtras(preview)
        )
        writeAgentPanelStatus(source = "files", state = "done", reason = "share", itemId = refId)
    }

    fun sendComposerTextToAi(rawText: String): Boolean {
        val text = rawText.trim()
        if (text.isBlank()) {
            toast("请输入文本")
            return false
        }

        val session = terminalViewModel.terminalView?.currentSession
        if (session == null) {
            toast("当前终端会话不可用")
            return false
        }

        val previewDir = localDir().child("media-preview")
        val mediaDir = previewDir.child("files")
        val stamp = "${System.currentTimeMillis()}.${(0..9999).random()}"
        val target = mediaDir.child("$stamp-user-text.txt")
        val written = runCatching {
            mediaDir.mkdirs()
            target.writeText(text.replace("\r\n", "\n"), Charsets.UTF_8)
        }.onFailure { error ->
            toast("无法保存文本：${error.message}")
        }.isSuccess
        if (!written) return false

        val preview = TerminalMediaPreview(
            path = target.absolutePath,
            name = "用户文本-$stamp.txt",
            kind = TerminalMediaPreviewKind.TEXT,
            stamp = stamp,
            sizeBytes = target.length(),
            mimeType = "text/plain",
            textPreview = text.take(64 * 1024),
            source = TerminalMediaPreviewSource.USER
        )
        terminalViewModel.addMediaPreview(preview)

        val refId = previewReferenceId(preview)
        val refWritten = runCatching {
            writePreviewReference(preview, refId)
        }.onFailure { error ->
            toast("无法创建文本引用：${error.message}")
        }.isSuccess
        if (!refWritten) return false

        session.write(
            buildString {
                append("文本[").append(refId).append("] 路径：codex-preview path ").append(refId).append('\n')
            }
        )
        writeAgentPanelEvent(
            source = "files",
            type = "user_sent_text",
            state = "done",
            reason = "composer",
            itemId = refId,
            extra = mediaPreviewExtras(preview)
        )
        syncMediaPreviewStatus(reason = "composer_sent", state = "done")
        writeAgentPanelStatus(
            source = "files",
            state = "done",
            reason = "composer_sent",
            itemId = refId,
            extra = mediaPreviewExtras(preview)
        )
        appendActiveSessionFoldItem(
            kind = TerminalSessionFoldItemKind.TEXT,
            title = preview.name,
            summary = text.replace(Regex("\\s+"), " ").take(240),
            path = preview.path,
            status = "done",
            itemId = refId
        )
        toast("文本已发送")
        return true
    }

    private fun writePreviewReference(preview: TerminalMediaPreview, refId: String) {
        val refsDir = localDir().child("media-preview").child("refs")
        refsDir.mkdirs()
        val target = refsDir.child(refId)
        val tmp = refsDir.child("$refId.tmp")
        tmp.writeText(
            buildString {
                append("path=").append(refValue(preview.path)).append('\n')
                append("name=").append(refValue(preview.name)).append('\n')
                append("kind=").append(preview.kind.name.lowercase(Locale.ROOT)).append('\n')
                append("stamp=").append(refValue(preview.stamp)).append('\n')
            }
        )
        if (!tmp.renameTo(target)) {
            tmp.copyTo(target, overwrite = true)
            tmp.delete()
        }
    }

    private fun removePreviewReference(preview: TerminalMediaPreview) {
        localDir().child("media-preview").child("refs").child(previewReferenceId(preview)).delete()
    }

    private fun previewReferenceId(preview: TerminalMediaPreview): String {
        val safe = preview.stamp
            .filter { it.isLetterOrDigit() || it == '.' || it == '_' || it == '-' }
            .take(80)
        if (safe.isNotBlank()) return safe

        val hash = preview.path.hashCode().toLong().let { if (it < 0) -it else it }
        return "file-$hash"
    }

    private fun refValue(value: String): String {
        return value.replace('\r', ' ').replace('\n', ' ')
    }

    private fun collapseTerminalText(value: String): String {
        return value.replace(Regex("\\s+"), " ").trim()
    }

    private fun shortenForTerminal(value: String, maxLength: Int): String {
        if (value.length <= maxLength) return value
        val head = (maxLength / 2).coerceAtLeast(8)
        val tail = (maxLength - head - 3).coerceAtLeast(8)
        return value.take(head) + "..." + value.takeLast(tail)
    }

    private fun launchBrowserFileChooser(
        intent: Intent,
        callback: (Array<Uri>?) -> Unit
    ) {
        browserFileChooserCallback?.invoke(null)
        browserFileChooserCallback = callback
        writeAgentPanelEvent(source = "browser", type = "user_upload_picker_opened", state = "waiting_for_user", reason = "browser_file_chooser")
        writeAgentPanelStatus(source = "browser", state = "waiting_for_user", reason = "browser_file_chooser")
        runCatching {
            pickBrowserUploadFiles.launch(intent)
        }.onFailure { error ->
            browserFileChooserCallback = null
            callback(null)
            writeAgentPanelEvent(source = "browser", type = "user_upload_picker_failed", state = "error", reason = error.message.orEmpty())
            writeAgentPanelStatus(source = "browser", state = "error", reason = error.message.orEmpty())
            toast("无法打开文件选择器：${error.message}")
        }
    }

    fun toggleMediaPreviewPanel() {
        if (terminalViewModel.mediaPreviewExpanded) {
            collapseMediaPreviewPanel()
        } else {
            terminalViewModel.browserPanelExpanded = false
            terminalViewModel.mediaPreviewExpanded = true
            syncMediaPreviewStatus(reason = "top_bar", state = "ready")
            writeAgentPanelEvent(source = "files", type = "user_presented", state = "ready", reason = "top_bar")
            writeAgentPanelStatus(source = "files", state = "ready", reason = "top_bar")
        }
    }

    fun collapseMediaPreviewPanel() {
        terminalViewModel.mediaPreviewExpanded = false
        syncMediaPreviewStatus(reason = "collapse", state = "done")
        writeAgentPanelEvent(source = "files", type = "user_collapsed", state = "done", reason = "collapse")
        writeAgentPanelStatus(source = "files", state = "done", reason = "collapse")
    }

    fun toggleBrowserPanel() {
        if (terminalViewModel.browserPanelExpanded) {
            collapseBrowserPanel()
        } else {
            terminalViewModel.mediaPreviewExpanded = false
            terminalViewModel.browserPanelExpanded = true
            writeAgentPanelEvent(
                source = "browser",
                type = "user_presented",
                state = terminalViewModel.browserSnapshot.status,
                reason = "top_bar",
                requestId = terminalViewModel.browserSnapshot.requestId
            )
            writeAgentPanelStatus(
                source = "browser",
                state = terminalViewModel.browserSnapshot.status,
                reason = "top_bar",
                requestId = terminalViewModel.browserSnapshot.requestId
            )
        }
    }

    fun collapseBrowserPanel() {
        if (terminalViewModel.browserSnapshot.needsUser) {
            markBrowserUserDone(reason = "user_collapsed")
            return
        }
        terminalViewModel.browserPanelExpanded = false
        writeAgentPanelEvent(
            source = "browser",
            type = "user_collapsed",
            state = "done",
            reason = "collapse",
            requestId = terminalViewModel.browserSnapshot.requestId
        )
        writeAgentPanelStatus(
            source = "browser",
            state = "done",
            reason = "collapse",
            requestId = terminalViewModel.browserSnapshot.requestId
        )
    }

    fun closeBrowserSession() {
        terminalViewModel.browserPanelExpanded = false
        writeAgentPanelEvent(
            source = "browser",
            type = "user_cancelled",
            state = "cancelled",
            reason = "close",
            requestId = terminalViewModel.browserSnapshot.requestId
        )
        lifecycleScope.launch {
            val browserDir = localDir().child("browser")
            val result = browserSessionManager.handleRequest(
                mapOf("action" to "close", "request_id" to "manual-close-${System.currentTimeMillis()}"),
                browserDir
            )
            writeBrowserResult(browserDir, result)
        }
    }

    fun markBrowserUserDone(reason: String = "user_done") {
        terminalViewModel.browserPanelExpanded = false
        val requestId = terminalViewModel.browserSnapshot.requestId
            .ifBlank { "manual-user-done-${System.currentTimeMillis()}" }
        writeAgentPanelEvent(
            source = "browser",
            type = reason,
            state = "done",
            reason = reason,
            requestId = requestId
        )
        lifecycleScope.launch {
            val browserDir = localDir().child("browser")
            val result = browserSessionManager.handleRequest(
                mapOf("action" to "user_done", "request_id" to requestId),
                browserDir
            )
            writeBrowserResult(browserDir, result)
        }
    }

    fun selectBrowserTabFromUi(tabId: Int) {
        browserSessionManager.selectTabFromUi(tabId)
        writeAgentPanelEvent(
            source = "browser",
            type = "user_selected_tab",
            state = terminalViewModel.browserSnapshot.status,
            reason = "tab_select",
            requestId = terminalViewModel.browserSnapshot.requestId,
            itemId = tabId.toString(),
            extra = browserSnapshotExtras(terminalViewModel.browserSnapshot)
        )
        writeAgentPanelStatus(
            source = "browser",
            state = terminalViewModel.browserSnapshot.status,
            reason = "tab_select",
            requestId = terminalViewModel.browserSnapshot.requestId,
            itemId = tabId.toString()
        )
    }

    fun closeBrowserTabFromUi(tabId: Int) {
        browserSessionManager.closeTabFromUi(tabId)
        writeAgentPanelEvent(
            source = "browser",
            type = "user_closed_tab",
            state = terminalViewModel.browserSnapshot.status,
            reason = "tab_close",
            requestId = terminalViewModel.browserSnapshot.requestId,
            itemId = tabId.toString(),
            extra = browserSnapshotExtras(terminalViewModel.browserSnapshot)
        )
        writeAgentPanelStatus(
            source = "browser",
            state = terminalViewModel.browserSnapshot.status,
            reason = "tab_close",
            requestId = terminalViewModel.browserSnapshot.requestId,
            itemId = tabId.toString()
        )
    }

    fun toggleSessionFoldRun(runId: String) {
        val run = terminalViewModel.sessionFoldRuns.firstOrNull { it.id == runId } ?: return
        val collapsed = !run.collapsed
        terminalViewModel.setSessionFoldCollapsed(runId, collapsed)
        writeSessionFoldEvent(
            type = if (collapsed) "user_collapsed" else "user_expanded",
            state = "ready",
            reason = "timeline_toggle",
            runId = runId
        )
        writeSessionFoldStatus(
            state = "ready",
            reason = "timeline_toggle",
            runId = runId
        )
    }

    fun removeSessionFoldRun(runId: String) {
        terminalViewModel.removeSessionFoldRun(runId)
        writeSessionFoldEvent(
            type = "user_removed",
            state = "ready",
            reason = "timeline_remove",
            runId = runId
        )
        writeSessionFoldStatus(
            state = "ready",
            reason = "timeline_remove",
            runId = runId
        )
    }

    fun clearSessionFoldTimeline() {
        terminalViewModel.clearSessionFoldRuns()
        lifecycleScope.launch(Dispatchers.IO) {
            runCatching { localDir().child("session-fold").child("entries").deleteRecursively() }
        }
        writeSessionFoldEvent(
            type = "user_cleared",
            state = "closed",
            reason = "timeline_clear"
        )
        writeSessionFoldStatus(state = "closed", reason = "timeline_clear")
    }

    private fun appendActiveSessionFoldItem(
        kind: TerminalSessionFoldItemKind,
        title: String,
        summary: String = "",
        path: String = "",
        status: String = "done",
        itemId: String = ""
    ) {
        val runId = terminalViewModel.activeSessionFoldRunId
        if (runId.isBlank()) return
        val resolvedItemId = itemId.ifBlank { "${kind.name.lowercase(Locale.ROOT)}-${System.currentTimeMillis()}" }
        terminalViewModel.addSessionFoldItem(
            TerminalSessionFoldItem(
                id = resolvedItemId,
                runId = runId,
                kind = kind,
                title = title,
                summary = summary,
                path = path,
                status = status
            )
        )
        writeSessionFoldStatus(
            state = status,
            reason = "attached_${kind.name.lowercase(Locale.ROOT)}",
            runId = runId,
            itemId = resolvedItemId
        )
    }

    private fun writeBrowserNeedsUserTransition(
        previous: TerminalBrowserSnapshot,
        current: TerminalBrowserSnapshot
    ) {
        val key = "${current.requestId}|${current.message}|${current.currentUrl}|${current.needsUser}"
        if (!current.needsUser) {
            lastBrowserNeedsUserEventKey = ""
            return
        }
        if (previous.needsUser && key == lastBrowserNeedsUserEventKey) return
        lastBrowserNeedsUserEventKey = key
        writeAgentPanelEvent(
            source = "browser",
            type = "browser_needs_user",
            state = "waiting_for_user",
            reason = current.message,
            requestId = current.requestId,
            extra = browserSnapshotExtras(current)
        )
        writeAgentPanelStatus(
            source = "browser",
            state = "waiting_for_user",
            reason = current.message,
            requestId = current.requestId,
            extra = browserSnapshotExtras(current)
        )
        appendActiveSessionFoldItem(
            kind = TerminalSessionFoldItemKind.BROWSER,
            title = "浏览器等待用户",
            summary = current.message.ifBlank { current.title.ifBlank { current.currentUrl } },
            path = current.currentUrl,
            status = "waiting_for_user",
            itemId = current.requestId.ifBlank { "browser-${System.currentTimeMillis()}" }
        )
    }

    private fun primeMediaPreviewRequestCache() {
        lastMediaPreviewRequest = try {
            val requestFile = localDir().child("media-preview").child("request")
            if (requestFile.isFile) requestFile.readText().trim() else ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun primeBrowserRequestCache() {
        lastBrowserRequest = try {
            val requestFile = localDir().child("browser").child("request")
            if (requestFile.isFile) requestFile.readText().trim() else ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun primeSessionFoldRequestCache() {
        lastSessionFoldRequest = try {
            val requestFile = localDir().child("session-fold").child("request")
            if (requestFile.isFile) requestFile.readText().trim() else ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun startMediaPreviewBridge() {
        if (mediaPreviewJob?.isActive == true) return
        mediaPreviewJob = lifecycleScope.launch {
            while (isActive) {
                pollMediaPreviewRequest()
                delay(500)
            }
        }
    }

    private fun startBrowserBridge() {
        if (browserBridgeJob?.isActive == true) return
        browserBridgeJob = lifecycleScope.launch {
            while (isActive) {
                pollBrowserRequest()
                delay(350)
            }
        }
    }

    private fun startSessionFoldBridge() {
        if (sessionFoldJob?.isActive == true) return
        sessionFoldJob = lifecycleScope.launch {
            while (isActive) {
                pollSessionFoldRequest()
                delay(450)
            }
        }
    }

    private suspend fun pollSessionFoldRequest() {
        val foldDir = localDir().child("session-fold")
        val requestFile = foldDir.child("request")
        val content = withContext(Dispatchers.IO) {
            foldDir.mkdirs()
            if (requestFile.isFile) requestFile.readText() else ""
        }.trim()

        if (content.isBlank() || content == lastSessionFoldRequest) return
        lastSessionFoldRequest = content

        val request = parseMediaPreviewRequest(content)
        val requestId = panelRequestId(request, content)
        val action = request["action"].orEmpty()
        val runId = request["run_id"].orEmpty().ifBlank { requestId }
        val reason = request["reason"] ?: request["summary"] ?: action
        try {
            when (action) {
                "start" -> {
                    val resolvedRunId = request["run_id"].orEmpty().ifBlank { requestId }
                    terminalViewModel.upsertSessionFoldRun(
                        runId = resolvedRunId,
                        title = request["title"].orEmpty().ifBlank { "会话处理" },
                        status = "running",
                        collapsed = false
                    )
                    writeSessionFoldEvent("agent_started", "running", reason, requestId, resolvedRunId)
                    writeSessionFoldResult(requestId, action, true, "running", reason, resolvedRunId)
                    writeSessionFoldStatus("running", reason, requestId, resolvedRunId)
                }
                "add" -> {
                    val resolvedRunId = request["run_id"].orEmpty().ifBlank {
                        terminalViewModel.activeSessionFoldRunId.ifBlank { runId }
                    }
                    val kind = sessionFoldItemKind(request["kind"].orEmpty())
                    val itemId = request["item_id"].orEmpty().ifBlank { requestId }
                    val path = request["path"].orEmpty()
                    val summary = request["summary"].orEmpty().ifBlank {
                        sessionFoldPathSummary(path)
                    }
                    val title = request["title"].orEmpty().ifBlank {
                        sessionFoldDefaultTitle(kind, path)
                    }
                    terminalViewModel.addSessionFoldItem(
                        TerminalSessionFoldItem(
                            id = itemId,
                            runId = resolvedRunId,
                            kind = kind,
                            title = title,
                            summary = summary,
                            path = path,
                            status = request["status"].orEmpty().ifBlank { "done" }
                        )
                    )
                    writeSessionFoldEvent(
                        type = "agent_added",
                        state = request["status"].orEmpty().ifBlank { "done" },
                        reason = reason,
                        requestId = requestId,
                        runId = resolvedRunId,
                        itemId = itemId,
                        extra = mapOf("kind" to kind.name.lowercase(Locale.ROOT), "title" to title, "path" to path)
                    )
                    writeSessionFoldResult(requestId, action, true, "done", reason, resolvedRunId, itemId)
                    writeSessionFoldStatus("done", reason, requestId, resolvedRunId, itemId)
                }
                "done", "fail" -> {
                    val state = if (action == "fail") "failed" else "done"
                    val summary = request["summary"].orEmpty()
                    terminalViewModel.upsertSessionFoldRun(
                        runId = runId,
                        title = request["title"].orEmpty(),
                        status = state,
                        collapsed = true,
                        summary = summary
                    )
                    if (summary.isNotBlank()) {
                        terminalViewModel.addSessionFoldItem(
                            TerminalSessionFoldItem(
                                id = "$requestId-final",
                                runId = runId,
                                kind = TerminalSessionFoldItemKind.FINAL,
                                title = if (state == "done") "最终结果" else "失败说明",
                                summary = summary,
                                status = state
                            )
                        )
                    }
                    writeSessionFoldEvent("agent_$state", state, reason, requestId, runId)
                    writeSessionFoldResult(requestId, action, true, state, reason, runId)
                    writeSessionFoldStatus(state, reason, requestId, runId)
                }
                "expand", "collapse" -> {
                    val collapsed = action == "collapse"
                    terminalViewModel.setSessionFoldCollapsed(runId, collapsed)
                    val state = if (collapsed) "collapsed" else "expanded"
                    writeSessionFoldEvent("agent_$state", state, reason, requestId, runId)
                    writeSessionFoldResult(requestId, action, true, state, reason, runId)
                    writeSessionFoldStatus(state, reason, requestId, runId)
                }
                "remove" -> {
                    terminalViewModel.removeSessionFoldRun(runId)
                    writeSessionFoldEvent("agent_removed", "ready", reason, requestId, runId)
                    writeSessionFoldResult(requestId, action, true, "ready", reason, runId)
                    writeSessionFoldStatus("ready", reason, requestId, runId)
                }
                "clear" -> {
                    terminalViewModel.clearSessionFoldRuns()
                    withContext(Dispatchers.IO) {
                        runCatching { foldDir.child("entries").deleteRecursively() }
                    }
                    writeSessionFoldEvent("agent_cleared", "closed", reason, requestId)
                    writeSessionFoldResult(requestId, action, true, "closed", reason)
                    writeSessionFoldStatus("closed", reason, requestId)
                }
                else -> {
                    writeSessionFoldEvent("agent_error", "error", "unsupported_action", requestId, runId)
                    writeSessionFoldResult(requestId, action, false, "error", "unsupported_action", runId, error = "unsupported_action")
                    writeSessionFoldStatus("error", "unsupported_action", requestId, runId)
                }
            }
        } catch (error: Exception) {
            val message = error.message ?: error::class.java.simpleName
            writeSessionFoldEvent("agent_error", "error", message, requestId, runId)
            writeSessionFoldResult(requestId, action, false, "error", message, runId, error = message)
            writeSessionFoldStatus("error", message, requestId, runId)
        }
    }

    private suspend fun pollBrowserRequest() {
        val browserDir = localDir().child("browser")
        val requestFile = browserDir.child("request")
        val content = withContext(Dispatchers.IO) {
            browserDir.mkdirs()
            if (requestFile.isFile) requestFile.readText() else ""
        }.trim()

        if (content.isBlank() || content == lastBrowserRequest) return
        lastBrowserRequest = content

        val request = parseMediaPreviewRequest(content)
        val requestedAction = request["action"].orEmpty()
        val effectiveAction = when (requestedAction) {
            "toggle" -> if (terminalViewModel.browserPanelExpanded) "collapse" else "present"
            else -> requestedAction
        }
        val effectiveRequest = if (effectiveAction != requestedAction) {
            request + ("action" to effectiveAction)
        } else {
            request
        }
        if (effectiveAction in setOf("present", "user_wait") || request["present"] == "1") {
            terminalViewModel.mediaPreviewExpanded = false
            terminalViewModel.browserPanelExpanded = true
        }
        if (effectiveAction in setOf("collapse", "user_done", "user_cancelled", "close")) {
            terminalViewModel.browserPanelExpanded = false
        }
        val result = runCatching {
            browserSessionManager.handleRequest(effectiveRequest, browserDir)
        }.getOrElse { error ->
            JSONObject()
                .put("ok", false)
                .put("requestId", effectiveRequest["request_id"] ?: effectiveRequest["stamp"] ?: content.hashCode().toString())
                .put("action", effectiveRequest["action"] ?: "")
                .put("error", error.message ?: error::class.java.simpleName)
                .put("snapshot", JSONObject())
        }
        val action = effectiveAction
        val snapshot = result.optJSONObject("snapshot")
        val suppressPresent = action in setOf("collapse", "user_done", "user_cancelled", "close")
        val shouldPresent = !suppressPresent && (
            request["present"] == "1" ||
                action == "present" ||
                action == "user_wait" ||
                snapshot?.optBoolean("needsUser") == true
            )
        val shouldCollapse = action == "collapse" || action == "user_done" || action == "user_cancelled"
        if (result.optBoolean("ok") && shouldCollapse) {
            terminalViewModel.browserPanelExpanded = false
        }
        if (result.optBoolean("ok") && shouldPresent) {
            terminalViewModel.mediaPreviewExpanded = false
            terminalViewModel.browserPanelExpanded = true
        }
        writeBrowserResult(browserDir, result)
        val state = if (result.optBoolean("ok")) {
            snapshot?.optString("status")?.takeIf { it.isNotBlank() } ?: "done"
        } else {
            "error"
        }
        writeAgentPanelEvent(
            source = "browser",
            type = browserAgentEventType(action),
            state = state,
            reason = request["reason"] ?: request["message"] ?: action,
            requestId = result.optString("requestId"),
            extra = browserJsonExtras(snapshot)
        )
        appendActiveSessionFoldItem(
            kind = TerminalSessionFoldItemKind.BROWSER,
            title = snapshot?.optString("title").orEmpty().ifBlank { "浏览器" },
            summary = snapshot?.optString("currentUrl").orEmpty().ifBlank { request["message"].orEmpty() },
            path = snapshot?.optString("currentUrl").orEmpty(),
            status = state,
            itemId = result.optString("requestId").ifBlank { "browser-${System.currentTimeMillis()}" }
        )
    }

    private suspend fun pollMediaPreviewRequest() {
        val previewDir = localDir().child("media-preview")
        val requestFile = previewDir.child("request")
        val content = withContext(Dispatchers.IO) {
            previewDir.mkdirs()
            if (requestFile.isFile) requestFile.readText() else ""
        }.trim()

        if (content.isBlank() || content == lastMediaPreviewRequest) return
        lastMediaPreviewRequest = content

        val request = parseMediaPreviewRequest(content)
        val action = request["action"].orEmpty().ifBlank { "show" }
        val requestId = panelRequestId(request, content)
        val reason = request["reason"] ?: action
        if (action == "clear") {
            terminalViewModel.clearMediaPreviews()
            withContext(Dispatchers.IO) {
                runCatching { previewDir.child("files").deleteRecursively() }
                runCatching { previewDir.child("refs").deleteRecursively() }
            }
            writeMediaPreviewStatus(previewDir, "cleared=1\n")
            writeMediaPreviewResult(previewDir, requestId, action, ok = true, state = "closed", reason = reason)
            writeAgentPanelEvent(source = "files", type = "agent_cleared", state = "closed", reason = reason, requestId = requestId)
            writeAgentPanelStatus(source = "files", state = "closed", reason = reason, requestId = requestId)
            return
        }

        if (action in setOf("present", "collapse", "toggle", "done", "cancel", "select", "remove")) {
            val selected = request["item_id"]?.let { mediaPreviewByRef(it) }
            when (action) {
                "present" -> {
                    terminalViewModel.browserPanelExpanded = false
                    terminalViewModel.mediaPreviewExpanded = true
                }
                "collapse" -> terminalViewModel.mediaPreviewExpanded = false
                "toggle" -> {
                    if (terminalViewModel.mediaPreviewExpanded) {
                        terminalViewModel.mediaPreviewExpanded = false
                    } else {
                        terminalViewModel.browserPanelExpanded = false
                        terminalViewModel.mediaPreviewExpanded = true
                    }
                }
                "done", "cancel" -> terminalViewModel.mediaPreviewExpanded = false
                "select" -> {
                    if (selected == null) {
                        writeMediaPreviewStatus(previewDir, "error=item-not-found\nrequest_id=$requestId\nitem_id=${request["item_id"].orEmpty()}\n")
                        writeMediaPreviewResult(previewDir, requestId, action, ok = false, state = "error", reason = "item_not_found", itemId = request["item_id"].orEmpty())
                        writeAgentPanelEvent(source = "files", type = "agent_error", state = "error", reason = "item_not_found", requestId = requestId, itemId = request["item_id"].orEmpty())
                        writeAgentPanelStatus(source = "files", state = "error", reason = "item_not_found", requestId = requestId, itemId = request["item_id"].orEmpty())
                        return
                    }
                    terminalViewModel.mediaPreviews.removeAll { it.stamp == selected.stamp }
                    terminalViewModel.mediaPreviews.add(selected)
                }
                "remove" -> {
                    if (selected == null) {
                        writeMediaPreviewStatus(previewDir, "error=item-not-found\nrequest_id=$requestId\nitem_id=${request["item_id"].orEmpty()}\n")
                        writeMediaPreviewResult(previewDir, requestId, action, ok = false, state = "error", reason = "item_not_found", itemId = request["item_id"].orEmpty())
                        writeAgentPanelEvent(source = "files", type = "agent_error", state = "error", reason = "item_not_found", requestId = requestId, itemId = request["item_id"].orEmpty())
                        writeAgentPanelStatus(source = "files", state = "error", reason = "item_not_found", requestId = requestId, itemId = request["item_id"].orEmpty())
                        return
                    }
                    val refId = previewReferenceId(selected)
                    terminalViewModel.removeMediaPreview(selected.stamp)
                    withContext(Dispatchers.IO) {
                        runCatching { File(selected.path).delete() }
                        runCatching { removePreviewReference(selected) }
                    }
                    syncMediaPreviewStatus(reason = reason, state = "ready")
                    writeMediaPreviewResult(previewDir, requestId, action, ok = true, state = "ready", reason = reason, itemId = refId, extra = mediaPreviewExtras(selected))
                    writeAgentPanelEvent(source = "files", type = "agent_removed", state = "ready", reason = reason, requestId = requestId, itemId = refId, extra = mediaPreviewExtras(selected))
                    writeAgentPanelStatus(source = "files", state = "ready", reason = reason, requestId = requestId, itemId = refId)
                    return
                }
            }
            val itemId = selected?.let { previewReferenceId(it) }.orEmpty()
            val state = when (action) {
                "present", "select" -> "ready"
                "toggle" -> if (terminalViewModel.mediaPreviewExpanded) "ready" else "done"
                "cancel" -> "cancelled"
                else -> "done"
            }
            syncMediaPreviewStatus(reason = reason, state = state)
            writeMediaPreviewResult(previewDir, requestId, action, ok = true, state = state, reason = reason, itemId = itemId)
            writeAgentPanelEvent(source = "files", type = mediaAgentEventType(action), state = state, reason = reason, requestId = requestId, itemId = itemId)
            writeAgentPanelStatus(source = "files", state = state, reason = reason, requestId = requestId, itemId = itemId)
            return
        }

        val mediaPath = request["path"]?.takeIf { it.isNotBlank() }
        if (mediaPath == null) {
            writeMediaPreviewStatus(previewDir, "error=missing-path\n")
            writeMediaPreviewResult(previewDir, requestId, action, ok = false, state = "error", reason = "missing_path", error = "missing_path")
            writeAgentPanelEvent(source = "files", type = "agent_error", state = "error", reason = "missing_path", requestId = requestId)
            writeAgentPanelStatus(source = "files", state = "error", reason = "missing_path", requestId = requestId)
            return
        }

        val mediaFile = File(mediaPath)
        val canRead = withContext(Dispatchers.IO) {
            mediaFile.isFile && mediaFile.canRead()
        }
        if (!canRead) {
            writeMediaPreviewStatus(previewDir, "error=unreadable\npath=$mediaPath\n")
            writeMediaPreviewResult(previewDir, requestId, action, ok = false, state = "error", reason = "unreadable", error = "unreadable", extra = mapOf("path" to mediaPath))
            writeAgentPanelEvent(source = "files", type = "agent_error", state = "error", reason = "unreadable", requestId = requestId, extra = mapOf("path" to mediaPath))
            writeAgentPanelStatus(source = "files", state = "error", reason = "unreadable", requestId = requestId, extra = mapOf("path" to mediaPath))
            return
        }

        val kind = when (request["kind"]) {
            "image" -> TerminalMediaPreviewKind.IMAGE
            "video" -> TerminalMediaPreviewKind.VIDEO
            "text" -> TerminalMediaPreviewKind.TEXT
            else -> {
                writeMediaPreviewStatus(previewDir, "error=unsupported-kind\npath=$mediaPath\n")
                writeMediaPreviewResult(previewDir, requestId, action, ok = false, state = "error", reason = "unsupported_kind", error = "unsupported_kind", extra = mapOf("path" to mediaPath))
                writeAgentPanelEvent(source = "files", type = "agent_error", state = "error", reason = "unsupported_kind", requestId = requestId, extra = mapOf("path" to mediaPath))
                writeAgentPanelStatus(source = "files", state = "error", reason = "unsupported_kind", requestId = requestId, extra = mapOf("path" to mediaPath))
                return
            }
        }

        val bounds = if (kind == TerminalMediaPreviewKind.IMAGE) {
            readImageBounds(mediaFile)
        } else {
            null
        }
        val textPreview = if (kind == TerminalMediaPreviewKind.TEXT) {
            readTextPreview(mediaFile)
        } else {
            null
        }

        val preview = TerminalMediaPreview(
            path = mediaFile.absolutePath,
            name = request["name"]?.takeIf { it.isNotBlank() } ?: mediaFile.name,
            kind = kind,
            stamp = request["stamp"] ?: content.hashCode().toString(),
            width = bounds?.first,
            height = bounds?.second,
            sizeBytes = mediaFile.length(),
            textPreview = textPreview
        )
        terminalViewModel.addMediaPreview(preview)
        val refId = previewReferenceId(preview)
        val shouldPresent = request["present"] != "0"
        if (shouldPresent) {
            terminalViewModel.browserPanelExpanded = false
            terminalViewModel.mediaPreviewExpanded = true
        }
        writeAgentPanelEvent(
            source = "files",
            type = if (shouldPresent) "agent_presented" else "agent_added",
            state = "ready",
            reason = if (shouldPresent) "present" else "background",
            requestId = refId,
            itemId = refId
        )
        writeMediaPreviewStatus(
            previewDir,
            buildString {
                append("state=ready\n")
                append("reason=").append(if (shouldPresent) "present" else "background").append('\n')
                append("shown=1\n")
                append("request_id=").append(refValue(requestId)).append('\n')
                append("kind=").append(preview.kind.name.lowercase(Locale.ROOT)).append('\n')
                append("path=").append(refValue(preview.path)).append('\n')
                append("name=").append(refValue(preview.name)).append('\n')
                append("stamp=").append(refValue(preview.stamp)).append('\n')
                append("item_id=").append(refId).append('\n')
            }
        )
        writeMediaPreviewResult(previewDir, requestId, action, ok = true, state = "ready", reason = if (shouldPresent) "present" else "background", itemId = refId)
        writeAgentPanelStatus(
            source = "files",
            state = "ready",
            reason = if (shouldPresent) "present" else "background",
            requestId = refId,
            itemId = refId
        )
        appendActiveSessionFoldItem(
            kind = if (kind == TerminalMediaPreviewKind.TEXT) TerminalSessionFoldItemKind.TEXT else TerminalSessionFoldItemKind.FILE,
            title = preview.name,
            summary = textPreview?.replace(Regex("\\s+"), " ")?.take(240).orEmpty(),
            path = preview.path,
            status = "ready",
            itemId = refId
        )
    }

    private suspend fun ingestPickedPreviewFile(uri: Uri) {
        val previewDir = localDir().child("media-preview")
        val mediaDir = previewDir.child("files")
        val info = queryPickedFileInfo(uri)
        val kind = detectPickedPreviewKind(info.name, info.mimeType)
        if (kind == null) {
            writeAgentPanelEvent(
                source = "files",
                type = "user_file_unsupported",
                state = "error",
                reason = "unsupported_kind",
                extra = mapOf("name" to info.name, "mime_type" to info.mimeType)
            )
            writeAgentPanelStatus(
                source = "files",
                state = "error",
                reason = "unsupported_kind",
                extra = mapOf("name" to info.name, "mime_type" to info.mimeType)
            )
            toast("暂不支持此文件类型：${info.name}")
            return
        }

        val stamp = "${System.currentTimeMillis()}.${(0..9999).random()}"
        val safeName = sanitizeFileName(info.name).ifBlank {
            "picked-${kind.name.lowercase(Locale.ROOT)}.${extensionFromMime(info.mimeType).ifBlank { "bin" }}"
        }
        val target = mediaDir.child("$stamp-$safeName")
        val copiedBytes = withContext(Dispatchers.IO) {
            mediaDir.mkdirs()
            runCatching {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }
            val tmp = File("${target.absolutePath}.tmp")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tmp).use { output ->
                    input.copyTo(output)
                }
            } ?: throw IllegalArgumentException("无法读取文件")
            tmp.renameTo(target)
            target.length()
        }

        val bounds = if (kind == TerminalMediaPreviewKind.IMAGE) {
            readImageBounds(target)
        } else {
            null
        }
        val textPreview = if (kind == TerminalMediaPreviewKind.TEXT) {
            readTextPreview(target)
        } else {
            null
        }

        terminalViewModel.addMediaPreview(
            TerminalMediaPreview(
                path = target.absolutePath,
                name = info.name.ifBlank { target.name },
                kind = kind,
                stamp = stamp,
                width = bounds?.first,
                height = bounds?.second,
                sizeBytes = info.sizeBytes?.takeIf { it >= 0 } ?: copiedBytes,
                mimeType = info.mimeType,
                textPreview = textPreview,
                source = TerminalMediaPreviewSource.USER
            )
        )
        writeAgentPanelEvent(
            source = "files",
            type = "user_selected_file",
            state = "ready",
            reason = "file_picker",
            itemId = stamp
        )
        writeMediaPreviewStatus(
            previewDir,
            "picked=1\nkind=${kind.name.lowercase(Locale.ROOT)}\npath=${target.absolutePath}\n"
        )
        writeAgentPanelStatus(
            source = "files",
            state = "ready",
            reason = "file_picker",
            itemId = stamp
        )
    }

    private suspend fun readImageBounds(file: File): Pair<Int, Int>? = withContext(Dispatchers.IO) {
        try {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, options)
            val width = options.outWidth
            val height = options.outHeight
            if (width > 0 && height > 0) width to height else null
        } catch (_: Exception) {
            null
        }
    }

    private suspend fun readTextPreview(file: File): String = withContext(Dispatchers.IO) {
        val maxBytes = 12 * 1024
        val buffer = ByteArray(maxBytes)
        val read = file.inputStream().use { input -> input.read(buffer) }
        if (read <= 0) {
            ""
        } else {
            String(buffer, 0, read, Charsets.UTF_8)
                .replace("\u0000", "")
                .trim()
        }
    }

    private fun queryPickedFileInfo(uri: Uri): PickedPreviewFileInfo {
        var name = uri.lastPathSegment.orEmpty().substringAfterLast('/')
        var size: Long? = null
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (cursor.moveToFirst()) {
                if (nameIndex >= 0) {
                    name = cursor.getString(nameIndex).orEmpty().ifBlank { name }
                }
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    size = cursor.getLong(sizeIndex)
                }
            }
        }
        val mimeType = contentResolver.getType(uri).orEmpty()
        return PickedPreviewFileInfo(
            name = name.ifBlank { "picked-file" },
            mimeType = mimeType,
            sizeBytes = size
        )
    }

    private fun detectPickedPreviewKind(
        name: String,
        mimeType: String
    ): TerminalMediaPreviewKind? {
        val lowerName = name.lowercase(Locale.ROOT)
        val lowerMime = mimeType.lowercase(Locale.ROOT)
        return when {
            lowerMime.startsWith("image/") -> TerminalMediaPreviewKind.IMAGE
            lowerMime.startsWith("video/") -> TerminalMediaPreviewKind.VIDEO
            lowerMime.startsWith("text/") -> TerminalMediaPreviewKind.TEXT
            lowerMime in setOf("application/json", "application/xml", "application/x-yaml") ->
                TerminalMediaPreviewKind.TEXT
            lowerName.endsWith(".txt") || lowerName.endsWith(".md") || lowerName.endsWith(".markdown") ||
                lowerName.endsWith(".json") || lowerName.endsWith(".yaml") || lowerName.endsWith(".yml") ||
                lowerName.endsWith(".xml") || lowerName.endsWith(".csv") || lowerName.endsWith(".log") ->
                TerminalMediaPreviewKind.TEXT
            else -> null
        }
    }

    private fun sanitizeFileName(name: String): String {
        return name
            .substringAfterLast('/')
            .replace(Regex("""[\\/:*?"<>|]"""), "_")
            .take(96)
            .ifBlank { "picked-file" }
    }

    private fun extensionFromMime(mimeType: String): String {
        return MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType).orEmpty()
    }

    private fun parseMediaPreviewRequest(content: String): Map<String, String> {
        val values = mutableMapOf<String, String>()
        for (line in content.lineSequence()) {
            val idx = line.indexOf('=')
            if (idx > 0) {
                values[line.substring(0, idx).trim()] = line.substring(idx + 1).trim()
            }
        }
        if (!values.containsKey("path")) {
            content.lineSequence().firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }?.let {
                values["path"] = it
            }
        }
        return values
    }

    private fun sessionFoldItemKind(value: String): TerminalSessionFoldItemKind {
        return when (value.lowercase(Locale.ROOT)) {
            "thinking", "reasoning" -> TerminalSessionFoldItemKind.THINKING
            "tool", "command", "terminal" -> TerminalSessionFoldItemKind.TOOL
            "text", "long_text" -> TerminalSessionFoldItemKind.TEXT
            "file", "preview" -> TerminalSessionFoldItemKind.FILE
            "browser", "web" -> TerminalSessionFoldItemKind.BROWSER
            "final", "answer" -> TerminalSessionFoldItemKind.FINAL
            else -> TerminalSessionFoldItemKind.TOOL
        }
    }

    private fun sessionFoldDefaultTitle(
        kind: TerminalSessionFoldItemKind,
        path: String
    ): String {
        val name = path.takeIf { it.isNotBlank() }?.let { File(it).name }.orEmpty()
        return when (kind) {
            TerminalSessionFoldItemKind.THINKING -> "思考过程"
            TerminalSessionFoldItemKind.TOOL -> "工具调用"
            TerminalSessionFoldItemKind.TEXT -> name.ifBlank { "长文本" }
            TerminalSessionFoldItemKind.FILE -> name.ifBlank { "文件" }
            TerminalSessionFoldItemKind.BROWSER -> "浏览器"
            TerminalSessionFoldItemKind.FINAL -> "最终结果"
        }
    }

    private suspend fun sessionFoldPathSummary(path: String): String = withContext(Dispatchers.IO) {
        if (path.isBlank()) return@withContext ""
        val file = File(path)
        if (!file.isFile || !file.canRead()) return@withContext ""
        val maxBytes = 4096
        val buffer = ByteArray(maxBytes)
        val read = runCatching {
            file.inputStream().use { input -> input.read(buffer) }
        }.getOrDefault(0)
        if (read <= 0) {
            ""
        } else {
            String(buffer, 0, read, Charsets.UTF_8)
                .replace("\u0000", "")
                .replace(Regex("\\s+"), " ")
                .trim()
                .take(240)
        }
    }

    private fun writeMediaPreviewStatus(previewDir: File, text: String) {
        try {
            previewDir.mkdirs()
            val visible = terminalViewModel.mediaPreviewExpanded
            previewDir.child("status").writeText(
                buildString {
                    append(text)
                    if (!text.endsWith('\n')) append('\n')
                    append("visible=").append(if (visible) "1" else "0").append('\n')
                    append("collapsed=").append(if (visible) "0" else "1").append('\n')
                }
            )
        } catch (_: Exception) {
            // Best-effort debug marker for terminal-side troubleshooting.
        }
    }

    private fun syncMediaPreviewStatus(reason: String, state: String) {
        val latest = terminalViewModel.mediaPreviews.lastOrNull()
        val status = buildString {
            append("state=").append(refValue(state)).append('\n')
            append("reason=").append(refValue(reason)).append('\n')
            if (latest == null) {
                append("empty=1\n")
            } else {
                val refId = previewReferenceId(latest)
                append("shown=1\n")
                append("kind=").append(latest.kind.name.lowercase(Locale.ROOT)).append('\n')
                append("path=").append(refValue(latest.path)).append('\n')
                append("name=").append(refValue(latest.name)).append('\n')
                append("stamp=").append(refValue(latest.stamp)).append('\n')
                append("item_id=").append(refId).append('\n')
            }
        }
        writeMediaPreviewStatus(localDir().child("media-preview"), status)
    }

    private fun panelRequestId(request: Map<String, String>, content: String): String {
        return request["request_id"] ?: request["stamp"] ?: content.hashCode().toString()
    }

    private fun mediaAgentEventType(action: String): String {
        return when (action) {
            "present" -> "agent_presented"
            "collapse" -> "agent_collapsed"
            "toggle" -> if (terminalViewModel.mediaPreviewExpanded) "agent_presented" else "agent_collapsed"
            "done" -> "agent_done"
            "cancel" -> "agent_cancelled"
            "select" -> "agent_selected"
            "remove" -> "agent_removed"
            "clear" -> "agent_cleared"
            else -> "agent_${action.ifBlank { "request" }}"
        }
    }

    private fun browserAgentEventType(action: String): String {
        return when (action) {
            "present" -> "agent_presented"
            "collapse" -> "agent_collapsed"
            "user_wait" -> "agent_user_wait"
            "user_done" -> "agent_done"
            "user_cancelled" -> "agent_cancelled"
            "close" -> "agent_closed"
            else -> "agent_${action.ifBlank { "request" }}"
        }
    }

    private fun writeMediaPreviewResult(
        previewDir: File,
        requestId: String,
        action: String,
        ok: Boolean,
        state: String,
        reason: String,
        itemId: String = "",
        error: String = "",
        extra: Map<String, String> = emptyMap()
    ) {
        try {
            previewDir.mkdirs()
            val visible = terminalViewModel.mediaPreviewExpanded
            val activeItem = terminalViewModel.mediaPreviews.lastOrNull()?.let { previewReferenceId(it) }.orEmpty()
            val extras = panelExtrasFor("files", itemId) + extra
            previewDir.child("result").writeText(
                buildString {
                    append("request_id=").append(refValue(requestId)).append('\n')
                    append("action=").append(refValue(action)).append('\n')
                    append("ok=").append(if (ok) "1" else "0").append('\n')
                    append("state=").append(refValue(state)).append('\n')
                    append("reason=").append(refValue(reason)).append('\n')
                    append("item_id=").append(refValue(itemId)).append('\n')
                    append("active_item=").append(refValue(activeItem)).append('\n')
                    append("visible=").append(if (visible) "1" else "0").append('\n')
                    append("collapsed=").append(if (visible) "0" else "1").append('\n')
                    if (error.isNotBlank()) append("error=").append(refValue(error)).append('\n')
                    appendPanelExtras(extras)
                }
            )
        } catch (_: Exception) {
            // Best-effort bridge result for terminal-side automation.
        }
    }

    private fun writeBrowserResult(browserDir: File, result: JSONObject) {
        try {
            browserDir.mkdirs()
            val snapshot = result.optJSONObject("snapshot")
            val state = if (result.optBoolean("ok")) {
                snapshot?.optString("status")?.takeIf { it.isNotBlank() } ?: "done"
            } else {
                "error"
            }
            val visible = terminalViewModel.browserPanelExpanded
            val activeItem = snapshot?.opt("activeTabId")?.toString().orEmpty()
            val tabsCount = (snapshot?.optJSONArray("tabs")?.length() ?: 0).toString()
            result
                .put("visible", visible)
                .put("collapsed", !visible)
                .put("itemId", "")
                .put("activeItem", activeItem)
                .put("reason", result.optString("action"))
                .put("needsUser", snapshot?.optBoolean("needsUser") == true)
                .put("tabsCount", tabsCount)
            browserDir.child("result.json").writeText(result.toString(2))
            val text = buildString {
                append("request_id=").append(result.optString("requestId")).append('\n')
                append("state=").append(state).append('\n')
                append("action=").append(result.optString("action")).append('\n')
                append("ok=").append(if (result.optBoolean("ok")) "1" else "0").append('\n')
                append("needs_user=").append(if (snapshot?.optBoolean("needsUser") == true) "1" else "0").append('\n')
                append("visible=").append(if (visible) "1" else "0").append('\n')
                append("collapsed=").append(if (visible) "0" else "1").append('\n')
                append("item_id=\n")
                append("active_item=").append(refValue(activeItem)).append('\n')
                append("tab_id=").append(refValue(activeItem)).append('\n')
                append("tabs_count=").append(tabsCount).append('\n')
                append("url=").append(snapshot?.optString("currentUrl").orEmpty()).append('\n')
                append("title=").append(snapshot?.optString("title").orEmpty()).append('\n')
                result.optString("error").takeIf { it.isNotBlank() && it != "null" }?.let {
                    append("error=").append(it).append('\n')
                }
            }
            browserDir.child("status").writeText(text)
            browserDir.child("logs").mkdirs()
            browserDir.child("logs").child("session.log").appendText(text.lines().take(4).joinToString(" ") + "\n")
            writeAgentPanelStatus(
                source = "browser",
                state = state,
                reason = result.optString("action"),
                requestId = result.optString("requestId"),
                extra = browserJsonExtras(snapshot)
            )
        } catch (_: Exception) {
            // Best-effort bridge result for terminal-side troubleshooting.
        }
    }

    private data class PickedPreviewFileInfo(
        val name: String,
        val mimeType: String,
        val sizeBytes: Long?
    )
}
