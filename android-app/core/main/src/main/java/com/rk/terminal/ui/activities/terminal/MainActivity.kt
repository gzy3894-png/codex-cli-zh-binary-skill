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
        }
        writeMediaPreviewStatus(localDir().child("media-preview"), "closed=1\n")
    }

    fun removeMediaPreview(preview: TerminalMediaPreview) {
        terminalViewModel.removeMediaPreview(preview.stamp)
        lifecycleScope.launch(Dispatchers.IO) {
            runCatching { File(preview.path).delete() }
        }
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

    fun sendPreviewToAi(preview: TerminalMediaPreview) {
        val session = terminalViewModel.terminalView?.currentSession
        if (session == null) {
            toast("当前终端会话不可用")
            return
        }

        val kindText = when (preview.kind) {
            TerminalMediaPreviewKind.IMAGE -> "图片"
            TerminalMediaPreviewKind.VIDEO -> "视频"
            TerminalMediaPreviewKind.TEXT -> "文本文件"
        }
        val prompt = buildString {
            append("请查看我放入预览托盘的").append(kindText).append("：")
            append(preview.path)
            if (preview.kind == TerminalMediaPreviewKind.TEXT) {
                append("\n不要让我粘贴全文，直接读取这个本地文件。")
            }
            append('\n')
        }
        session.write(prompt)
        toast("已发送给 AI：${preview.name}")
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

    fun closeBrowserSession() {
        terminalViewModel.browserPanelExpanded = false
        lifecycleScope.launch {
            val browserDir = localDir().child("browser")
            val result = browserSessionManager.handleRequest(
                mapOf("action" to "close", "request_id" to "manual-close-${System.currentTimeMillis()}"),
                browserDir
            )
            writeBrowserResult(browserDir, result)
        }
    }

    fun markBrowserUserDone() {
        lifecycleScope.launch {
            val browserDir = localDir().child("browser")
            val result = browserSessionManager.handleRequest(
                mapOf("action" to "user_done", "request_id" to "manual-user-done-${System.currentTimeMillis()}"),
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
            }
            writeMediaPreviewStatus(previewDir, "cleared=1\n")
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
        writeMediaPreviewStatus(
            previewDir,
            "shown=1\nkind=${request["kind"]}\npath=${mediaFile.absolutePath}\n"
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
        writeMediaPreviewStatus(
            previewDir,
            "picked=1\nkind=${kind.name.lowercase(Locale.ROOT)}\npath=${target.absolutePath}\n"
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
            previewDir.child("status").writeText(text)
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
                append("url=").append(snapshot?.optString("currentUrl").orEmpty()).append('\n')
                append("title=").append(snapshot?.optString("title").orEmpty()).append('\n')
                result.optString("error").takeIf { it.isNotBlank() && it != "null" }?.let {
                    append("error=").append(it).append('\n')
                }
            }
            browserDir.child("status").writeText(text)
            browserDir.child("logs").mkdirs()
            browserDir.child("logs").child("session.log").appendText(text.lines().take(4).joinToString(" ") + "\n")
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
