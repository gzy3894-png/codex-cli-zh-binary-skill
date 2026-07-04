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
import com.rk.terminal.ui.screens.terminal.TerminalBrowserSessionManager
import com.rk.terminal.ui.screens.terminal.TerminalMediaPreview
import com.rk.terminal.ui.screens.terminal.TerminalMediaPreviewKind
import com.rk.terminal.ui.screens.terminal.TerminalMediaPreviewSource
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
    private var lastMediaPreviewRequest = ""
    private var lastBrowserRequest = ""
    private var browserFileChooserCallback: ((Array<Uri>?) -> Unit)? = null

    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { isGranted ->
            if (!isGranted) {
                // Optional: Handle permission denied
            }
        }

    private val pickPreviewFiles =
        registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
            if (uris.isEmpty()) return@registerForActivityResult
            lifecycleScope.launch {
                uris.forEach { uri ->
                    ingestPickedPreviewFile(uri)
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
            callback?.invoke(uris)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        requestPermission()
        browserSessionManager = TerminalBrowserSessionManager(
            context = this,
            onSnapshot = { snapshot ->
                terminalViewModel.updateBrowserSnapshot(snapshot)
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
        setupKeyboardListener()
    }

    override fun onStart() {
        super.onStart()
        viewModel.startAndBindService(this)
        startMediaPreviewBridge()
        startBrowserBridge()
    }

    override fun onStop() {
        super.onStop()
        mediaPreviewJob?.cancel()
        mediaPreviewJob = null
        browserBridgeJob?.cancel()
        browserBridgeJob = null
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
        itemId: String = ""
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
            val status = buildString {
                append("source=").append(source).append('\n')
                append("mode=").append(mode).append('\n')
                append("state=").append(state).append('\n')
                append("visible=").append(if (visible) "1" else "0").append('\n')
                append("collapsed=").append(if (visible) "0" else "1").append('\n')
                append("reason=").append(refValue(reason)).append('\n')
                append("request_id=").append(refValue(requestId)).append('\n')
                append("active_item=").append(refValue(activeItem)).append('\n')
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
        itemId: String = ""
    ) {
        try {
            val visible = when (source) {
                "browser" -> terminalViewModel.browserPanelExpanded
                else -> terminalViewModel.mediaPreviewExpanded
            }
            val event = buildString {
                append("event_id=").append(panelEventId()).append('\n')
                append("source=").append(source).append('\n')
                append("type=").append(type).append('\n')
                append("state=").append(state).append('\n')
                append("reason=").append(refValue(reason)).append('\n')
                append("request_id=").append(refValue(requestId)).append('\n')
                append("item_id=").append(refValue(itemId)).append('\n')
                append("visible=").append(if (visible) "1" else "0").append('\n')
                append("collapsed=").append(if (visible) "0" else "1").append('\n')
                append("---\n")
            }
            localDir().child("agent-panel").apply { mkdirs() }.child("events").appendText(event)
        } catch (_: Exception) {
            // Best-effort event bridge for terminal-side automation.
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
        terminalViewModel.removeMediaPreview(preview.stamp)
        lifecycleScope.launch(Dispatchers.IO) {
            runCatching { File(preview.path).delete() }
            runCatching { removePreviewReference(preview) }
        }
        writeAgentPanelEvent(
            source = "files",
            type = "user_deleted",
            state = "ready",
            reason = "delete_item",
            itemId = previewReferenceId(preview)
        )
        writeAgentPanelStatus(source = "files", state = "ready", reason = "delete_item")
    }

    fun openPreviewFilePicker() {
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
            source = if (preview.kind == TerminalMediaPreviewKind.TEXT) "text" else "files",
            type = "user_sent_file",
            state = "done",
            reason = cleanMessage,
            itemId = refId
        )
        writeAgentPanelStatus(
            source = "files",
            state = "done",
            reason = "sent_to_terminal",
            itemId = refId
        )
        toast("已发送：${shortenForTerminal(preview.name, 24)}")
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
            source = "text",
            type = "user_sent_text",
            state = "done",
            reason = "composer",
            itemId = refId
        )
        writeAgentPanelStatus(
            source = "text",
            state = "done",
            reason = "composer_sent",
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
        runCatching {
            pickBrowserUploadFiles.launch(intent)
        }.onFailure { error ->
            browserFileChooserCallback = null
            callback(null)
            toast("无法打开文件选择器：${error.message}")
        }
    }

    fun toggleMediaPreviewPanel() {
        if (terminalViewModel.mediaPreviewExpanded) {
            collapseMediaPreviewPanel()
        } else {
            terminalViewModel.browserPanelExpanded = false
            terminalViewModel.mediaPreviewExpanded = true
            writeAgentPanelEvent(source = "files", type = "user_presented", state = "ready", reason = "top_bar")
            writeAgentPanelStatus(source = "files", state = "ready", reason = "top_bar")
        }
    }

    fun collapseMediaPreviewPanel() {
        terminalViewModel.mediaPreviewExpanded = false
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
        val result = runCatching {
            browserSessionManager.handleRequest(request, browserDir)
        }.getOrElse { error ->
            JSONObject()
                .put("ok", false)
                .put("requestId", request["request_id"] ?: request["stamp"] ?: content.hashCode().toString())
                .put("action", request["action"] ?: "")
                .put("error", error.message ?: error::class.java.simpleName)
                .put("snapshot", JSONObject())
        }
        val action = request["action"].orEmpty()
        val snapshot = result.optJSONObject("snapshot")
        val shouldPresent = request["present"] == "1" ||
            action == "present" ||
            action == "user_wait" ||
            snapshot?.optBoolean("needsUser") == true
        val shouldCollapse = action == "user_done" || action == "user_cancelled"
        if (result.optBoolean("ok") && shouldCollapse) {
            terminalViewModel.browserPanelExpanded = false
            writeAgentPanelEvent(
                source = "browser",
                type = action,
                state = snapshot?.optString("status").orEmpty().ifBlank { "done" },
                reason = action,
                requestId = result.optString("requestId")
            )
        }
        if (result.optBoolean("ok") && shouldPresent) {
            terminalViewModel.mediaPreviewExpanded = false
            terminalViewModel.browserPanelExpanded = true
            writeAgentPanelEvent(
                source = "browser",
                type = if (action == "user_wait") "user_wait_started" else "agent_presented",
                state = snapshot?.optString("status").orEmpty().ifBlank { "ready" },
                reason = request["reason"] ?: request["message"] ?: action,
                requestId = result.optString("requestId")
            )
        }
        writeBrowserResult(browserDir, result)
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
        if (request["action"] == "clear") {
            terminalViewModel.clearMediaPreviews()
            withContext(Dispatchers.IO) {
                runCatching { previewDir.child("files").deleteRecursively() }
                runCatching { previewDir.child("refs").deleteRecursively() }
            }
            writeMediaPreviewStatus(previewDir, "cleared=1\n")
            writeAgentPanelEvent(source = "files", type = "panel_cleared", state = "closed", reason = "request")
            writeAgentPanelStatus(source = "files", state = "closed", reason = "request")
            return
        }

        val mediaPath = request["path"]?.takeIf { it.isNotBlank() }
        if (mediaPath == null) {
            writeMediaPreviewStatus(previewDir, "error=missing-path\n")
            return
        }

        val mediaFile = File(mediaPath)
        val canRead = withContext(Dispatchers.IO) {
            mediaFile.isFile && mediaFile.canRead()
        }
        if (!canRead) {
            writeMediaPreviewStatus(previewDir, "error=unreadable\npath=$mediaPath\n")
            return
        }

        val kind = when (request["kind"]) {
            "image" -> TerminalMediaPreviewKind.IMAGE
            "video" -> TerminalMediaPreviewKind.VIDEO
            "text" -> TerminalMediaPreviewKind.TEXT
            else -> {
                writeMediaPreviewStatus(previewDir, "error=unsupported-kind\npath=$mediaPath\n")
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

        terminalViewModel.addMediaPreview(
            TerminalMediaPreview(
                path = mediaFile.absolutePath,
                name = request["name"]?.takeIf { it.isNotBlank() } ?: mediaFile.name,
                kind = kind,
                stamp = request["stamp"] ?: content.hashCode().toString(),
                width = bounds?.first,
                height = bounds?.second,
                sizeBytes = mediaFile.length(),
                textPreview = textPreview
            )
        )
        val refId = request["stamp"] ?: content.hashCode().toString()
        val shouldPresent = request["present"] != "0"
        if (shouldPresent) {
            terminalViewModel.browserPanelExpanded = false
            terminalViewModel.mediaPreviewExpanded = true
        }
        writeAgentPanelEvent(
            source = if (kind == TerminalMediaPreviewKind.TEXT) "text" else "files",
            type = if (shouldPresent) "agent_presented" else "agent_added",
            state = "ready",
            reason = if (shouldPresent) "present" else "background",
            requestId = refId,
            itemId = refId
        )
        writeMediaPreviewStatus(
            previewDir,
            "shown=1\nkind=${request["kind"]}\npath=${mediaFile.absolutePath}\n"
        )
        writeAgentPanelStatus(
            source = if (kind == TerminalMediaPreviewKind.TEXT) "text" else "files",
            state = "ready",
            reason = if (shouldPresent) "present" else "background",
            requestId = refId,
            itemId = refId
        )
    }

    private suspend fun ingestPickedPreviewFile(uri: Uri) {
        val previewDir = localDir().child("media-preview")
        val mediaDir = previewDir.child("files")
        val info = queryPickedFileInfo(uri)
        val kind = detectPickedPreviewKind(info.name, info.mimeType)
        if (kind == null) {
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
            source = if (kind == TerminalMediaPreviewKind.TEXT) "text" else "files",
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
            source = if (kind == TerminalMediaPreviewKind.TEXT) "text" else "files",
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

    private fun writeBrowserResult(browserDir: File, result: JSONObject) {
        try {
            browserDir.mkdirs()
            browserDir.child("result.json").writeText(result.toString(2))
            val snapshot = result.optJSONObject("snapshot")
            val state = if (result.optBoolean("ok")) {
                snapshot?.optString("status")?.takeIf { it.isNotBlank() } ?: "done"
            } else {
                "error"
            }
            val text = buildString {
                append("request_id=").append(result.optString("requestId")).append('\n')
                append("state=").append(state).append('\n')
                append("action=").append(result.optString("action")).append('\n')
                append("ok=").append(if (result.optBoolean("ok")) "1" else "0").append('\n')
                append("needs_user=").append(if (snapshot?.optBoolean("needsUser") == true) "1" else "0").append('\n')
                append("visible=").append(if (terminalViewModel.browserPanelExpanded) "1" else "0").append('\n')
                append("collapsed=").append(if (terminalViewModel.browserPanelExpanded) "0" else "1").append('\n')
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
                requestId = result.optString("requestId")
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
