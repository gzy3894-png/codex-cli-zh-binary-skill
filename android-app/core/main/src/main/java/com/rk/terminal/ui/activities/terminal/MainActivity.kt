package com.rk.terminal.ui.activities.terminal

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.FileObserver
import android.provider.OpenableColumns
import android.view.KeyEvent
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
import com.rk.terminal.ui.screens.terminal.TerminalRenderPerformanceMetrics
import com.rk.terminal.ui.screens.terminal.TerminalSessionFoldItem
import com.rk.terminal.ui.screens.terminal.TerminalSessionFoldItemKind
import com.rk.terminal.ui.screens.terminal.TerminalViewModel
import com.rk.terminal.ui.screens.terminal.buildPreviewDisplayNames
import com.rk.terminal.ui.screens.terminal.shortPreviewDisplayName
import com.rk.terminal.ui.theme.KarbonTheme
import com.termux.terminal.TerminalSession
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

private const val BRIDGE_FALLBACK_POLL_MS = 1500L
private const val BRIDGE_STATUS_SCHEMA_VERSION = "2.3.1"
private const val TERMINAL_PERF_STATUS_MIN_INTERVAL_MS = 5000L
private const val TRAY_SEND_ENTER_DELAY_MS = 320L
private const val MEDIA_PREVIEW_RESTORE_LIMIT = 60
private const val MEDIA_PREVIEW_MAX_CACHE_FILES = 200
private const val MEDIA_PREVIEW_MAX_CACHE_BYTES = 200L * 1024L * 1024L
private const val MEDIA_PREVIEW_MAX_CACHE_AGE_MS = 7L * 24L * 60L * 60L * 1000L
private val REQUEST_FILE_OBSERVER_EVENTS =
    FileObserver.CLOSE_WRITE or FileObserver.MOVED_TO
private val QUEUE_FILE_OBSERVER_EVENTS =
    FileObserver.CLOSE_WRITE or FileObserver.MOVED_TO

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
    private var mediaPreviewObserver: FileObserver? = null
    private var mediaPreviewQueueObserver: FileObserver? = null
    private var browserRequestObserver: FileObserver? = null
    private var browserQueueObserver: FileObserver? = null
    private var sessionFoldObserver: FileObserver? = null
    private var sessionFoldQueueObserver: FileObserver? = null
    private val mediaPreviewPollMutex = Mutex()
    private val browserPollMutex = Mutex()
    private val sessionFoldPollMutex = Mutex()
    private val terminalPerfStatusLock = Any()
    private var lastMediaPreviewRequest = ""
    private var lastBrowserRequest = ""
    private var lastSessionFoldRequest = ""
    private var lastBrowserNeedsUserEventKey = ""
    private var lastTerminalPerfStatusWriteAt = 0L
    private var mediaPreviewCacheRestoreStarted = false
    private val mediaPreviewProcessedRequestIds = linkedSetOf<String>()
    private val browserProcessedRequestIds = linkedSetOf<String>()
    private val sessionFoldProcessedRequestIds = linkedSetOf<String>()
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
                persistBrowserSnapshot(snapshot)
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
        restoreMediaPreviewCacheAfterColdStart()
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
        viewModel.unbindService(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        mediaPreviewJob?.cancel()
        mediaPreviewJob = null
        browserBridgeJob?.cancel()
        browserBridgeJob = null
        sessionFoldJob?.cancel()
        sessionFoldJob = null
        stopBridgeObservers()
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
            pollMediaPreviewRequestLocked()
            pollBrowserRequestLocked()
            pollSessionFoldRequestLocked()
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

    private fun panelEventId(timestampMs: Long = System.currentTimeMillis()): String {
        return "$timestampMs.${(0..9999).random()}"
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
            val timestampMs = System.currentTimeMillis()
            val visible = when (source) {
                "browser" -> terminalViewModel.browserPanelExpanded
                else -> terminalViewModel.mediaPreviewExpanded
            }
            val mode = panelMode(source)
            val activeItem = itemId.ifBlank {
                if (source == "browser") {
                    terminalViewModel.browserSnapshot.activeTabId?.toString().orEmpty()
                } else {
                    terminalViewModel.mediaPreviews.lastOrNull()?.stamp.orEmpty()
                }
            }
            val extras = panelExtrasFor(source, itemId) + extra
            val needsUser = panelNeedsUser(source, state, extras)
            val userAction = panelStatusUserAction(state, extras)
            val status = buildString {
                append("source=").append(source).append('\n')
                append("mode=").append(mode).append('\n')
                append("schema_version=").append(BRIDGE_STATUS_SCHEMA_VERSION).append('\n')
                append("timestamp_ms=").append(timestampMs).append('\n')
                append("state=").append(refValue(state)).append('\n')
                append("visible=").append(if (visible) "1" else "0").append('\n')
                append("collapsed=").append(if (visible) "0" else "1").append('\n')
                append("needs_user=").append(if (needsUser) "1" else "0").append('\n')
                append("user_action=").append(refValue(userAction)).append('\n')
                append("reason=").append(refValue(reason)).append('\n')
                append("request_id=").append(refValue(requestId)).append('\n')
                append("item_id=").append(refValue(itemId)).append('\n')
                append("active_item=").append(refValue(activeItem)).append('\n')
                appendPanelExtras(extras)
                append("stamp=").append(panelEventId(timestampMs)).append('\n')
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
            val timestampMs = System.currentTimeMillis()
            val visible = when (source) {
                "browser" -> terminalViewModel.browserPanelExpanded
                else -> terminalViewModel.mediaPreviewExpanded
            }
            val mode = panelMode(source)
            val activeItem = if (source == "browser") {
                terminalViewModel.browserSnapshot.activeTabId?.toString().orEmpty()
            } else {
                terminalViewModel.mediaPreviews.lastOrNull()?.stamp.orEmpty()
            }
            val extras = panelExtrasFor(source, itemId) + extra
            val needsUser = panelNeedsUser(source, state, extras)
            val userAction = panelEventUserAction(type, extras)
            val event = buildString {
                append("event_id=").append(panelEventId(timestampMs)).append('\n')
                append("source=").append(source).append('\n')
                append("mode=").append(mode).append('\n')
                append("schema_version=").append(BRIDGE_STATUS_SCHEMA_VERSION).append('\n')
                append("timestamp_ms=").append(timestampMs).append('\n')
                append("type=").append(type).append('\n')
                append("state=").append(refValue(state)).append('\n')
                append("reason=").append(refValue(reason)).append('\n')
                append("request_id=").append(refValue(requestId)).append('\n')
                append("item_id=").append(refValue(itemId)).append('\n')
                append("active_item=").append(refValue(activeItem)).append('\n')
                append("visible=").append(if (visible) "1" else "0").append('\n')
                append("collapsed=").append(if (visible) "0" else "1").append('\n')
                append("needs_user=").append(if (needsUser) "1" else "0").append('\n')
                append("user_action=").append(refValue(userAction)).append('\n')
                appendPanelExtras(extras)
                append("---\n")
            }
            localDir().child("agent-panel").apply { mkdirs() }.child("events").appendText(event)
        } catch (_: Exception) {
            // Best-effort event bridge for terminal-side automation.
        }
    }

    private fun panelMode(source: String): String {
        return when (source) {
            "browser" -> "browser"
            "session" -> "session"
            else -> "files"
        }
    }

    private fun truthyBridgeValue(value: String): Boolean {
        return value == "1" || value.equals("true", ignoreCase = true) || value.equals("yes", ignoreCase = true)
    }

    private fun panelNeedsUser(
        source: String,
        state: String,
        extras: Map<String, String>
    ): Boolean {
        extras["needs_user"]?.takeIf { it.isNotBlank() }?.let { return truthyBridgeValue(it) }
        extras["needsUser"]?.takeIf { it.isNotBlank() }?.let { return truthyBridgeValue(it) }
        return when (source) {
            "browser" -> terminalViewModel.browserSnapshot.needsUser || state == "waiting_for_user"
            else -> state == "waiting_for_user"
        }
    }

    private fun panelStatusUserAction(
        state: String,
        extras: Map<String, String>
    ): String {
        extras["user_action"]?.takeIf { it.isNotBlank() }?.let { return it }
        extras["userAction"]?.takeIf { it.isNotBlank() }?.let { return it }
        return if (state == "waiting_for_user") "wait" else ""
    }

    private fun panelEventUserAction(
        type: String,
        extras: Map<String, String>
    ): String {
        extras["user_action"]?.takeIf { it.isNotBlank() }?.let { return it }
        extras["userAction"]?.takeIf { it.isNotBlank() }?.let { return it }
        return normalizedUserAction(type)
    }

    private fun normalizedUserAction(type: String): String {
        return when (type) {
            "user_presented" -> "present"
            "user_collapsed" -> "collapse"
            "user_cancelled" -> "cancel"
            "user_cleared" -> "clear"
            "user_deleted" -> "delete"
            "user_sent_file" -> "send_file"
            "user_sent_text" -> "send_text"
            "user_opened_preview" -> "open_preview"
            "user_closed_preview" -> "close_preview"
            "user_shared_preview" -> "share"
            "user_selected_file" -> "select_file"
            "user_file_picker_opened" -> "file_picker_open"
            "user_file_picker_cancelled" -> "file_picker_cancel"
            "user_file_picker_failed" -> "file_picker_failed"
            "user_file_ingest_failed" -> "file_ingest_failed"
            "user_file_unsupported" -> "file_unsupported"
            "user_upload_picker_opened" -> "upload_picker_open"
            "user_upload_picker_failed" -> "upload_picker_failed"
            "user_upload_cancelled" -> "upload_cancel"
            "user_upload_selected" -> "upload_select"
            "user_selected_tab" -> "select_tab"
            "user_closed_tab" -> "close_tab"
            "user_done", "auth_done" -> "done"
            "auth_cancelled", "external_open_cancelled" -> "cancel"
            "auth_collapsed" -> "collapse"
            "auth_reopened" -> "reopen"
            "external_open_confirmed" -> "confirm"
            else -> if (type.startsWith("user_")) type.removePrefix("user_") else ""
        }
    }

    private fun StringBuilder.appendPanelExtras(extras: Map<String, String>) {
        val reserved = setOf(
            "event_id", "source", "mode", "schema_version", "timestamp_ms", "type", "state", "reason", "request_id",
            "item_id", "active_item", "visible", "collapsed", "needs_user", "needsUser",
            "user_action", "userAction", "stamp"
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
            "url" to redactSensitiveUrl(snapshot.currentUrl),
            "title" to snapshot.title,
            "needs_user" to if (snapshot.needsUser) "1" else "0",
            "tabs_count" to snapshot.tabs.size.toString(),
            "auth_request_id" to snapshot.authTask?.requestId.orEmpty(),
            "auth_state" to snapshot.authTask?.state.orEmpty(),
            "user_action" to snapshot.authTask?.userAction.orEmpty(),
            "external_request_id" to snapshot.externalPrompt?.requestId.orEmpty(),
            "risk_challenge_detected" to if (snapshot.riskChallengeDetected) "1" else "0",
            "risk_challenge_kind" to snapshot.riskChallengeKind,
            "recommended_next_action" to snapshot.recommendedNextAction
        )
    }

    private fun browserJsonExtras(snapshot: JSONObject?): Map<String, String> {
        val authTask = snapshot?.optJSONObject("authTask")
        val externalPrompt = snapshot?.optJSONObject("externalPrompt")
        return mapOf(
            "tab_id" to snapshot?.opt("activeTabId")?.toString().orEmpty(),
            "url" to redactSensitiveUrl(snapshot?.optString("currentUrl").orEmpty()),
            "title" to snapshot?.optString("title").orEmpty(),
            "needs_user" to if (snapshot?.optBoolean("needsUser") == true) "1" else "0",
            "tabs_count" to (snapshot?.optJSONArray("tabs")?.length() ?: 0).toString(),
            "auth_request_id" to authTask?.optString("requestId").orEmpty(),
            "auth_state" to authTask?.optString("state").orEmpty(),
            "user_action" to authTask?.optString("userAction").orEmpty(),
            "external_request_id" to externalPrompt?.optString("requestId").orEmpty(),
            "risk_challenge_detected" to if (snapshot?.optBoolean("riskChallengeDetected") == true) "1" else "0",
            "risk_challenge_kind" to snapshot?.optString("riskChallengeKind").orEmpty(),
            "recommended_next_action" to snapshot?.optString("recommendedNextAction").orEmpty()
        )
    }

    private fun redactAuthCode(code: String): String {
        val trimmed = code.trim()
        if (trimmed.isBlank()) return ""
        if (trimmed.length <= 4) return "••••"
        return trimmed.take(2) + "••••" + trimmed.takeLast(2)
    }

    private fun redactSensitiveUrl(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isBlank()) return ""
        return runCatching {
            val uri = Uri.parse(trimmed)
            val scheme = uri.scheme.orEmpty().lowercase(Locale.ROOT)
            if (scheme.isNotBlank() && scheme !in setOf("http", "https", "about")) {
                return@runCatching "$scheme:REDACTED"
            }
            val sensitiveKeys = setOf(
                "access_token",
                "auth",
                "authorization",
                "authuser",
                "client_secret",
                "code",
                "id_token",
                "jwt",
                "key",
                "login_hint",
                "login_token",
                "oauth_token",
                "pass_ticket",
                "password",
                "refresh_token",
                "secret",
                "session",
                "sid",
                "sig",
                "signature",
                "skey",
                "state",
                "ticket",
                "token"
            )
            val queryNames = runCatching { uri.queryParameterNames }.getOrDefault(emptySet())
            val hasSensitiveQuery = queryNames.any { it.lowercase(Locale.ROOT) in sensitiveKeys }
            val fragment = uri.encodedFragment.orEmpty()
            val lowerFragment = fragment.lowercase(Locale.ROOT)
            val hasSensitiveFragment = fragment.isNotBlank() &&
                sensitiveKeys.any { lowerFragment.contains(it) || lowerFragment.contains("${it}%3d") }
            if (!hasSensitiveQuery && !hasSensitiveFragment) {
                trimmed
            } else {
                val builder = uri.buildUpon()
                if (hasSensitiveQuery) {
                    builder.clearQuery()
                    queryNames.forEach { key ->
                        val values = uri.getQueryParameters(key)
                        val shouldRedact = key.lowercase(Locale.ROOT) in sensitiveKeys
                        if (values.isEmpty()) {
                            builder.appendQueryParameter(key, if (shouldRedact) "REDACTED" else "")
                        } else {
                            values.forEach { value ->
                                builder.appendQueryParameter(key, if (shouldRedact) "REDACTED" else value)
                            }
                        }
                    }
                }
                if (hasSensitiveFragment) {
                    builder.encodedFragment("REDACTED")
                }
                builder.build().toString()
            }
        }.getOrElse {
            trimmed.substringBefore('?').take(180) + if (trimmed.contains('?')) "?REDACTED" else ""
        }
    }

    private fun sanitizeBrowserResultJson(value: Any?, keyHint: String = ""): Any? {
        return when (value) {
            null, JSONObject.NULL -> value
            is JSONObject -> JSONObject().also { sanitized ->
                val keys = value.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    sanitized.put(key, sanitizeBrowserResultJson(value.opt(key), key))
                }
            }
            is JSONArray -> JSONArray().also { sanitized ->
                for (index in 0 until value.length()) {
                    sanitized.put(sanitizeBrowserResultJson(value.opt(index), keyHint))
                }
            }
            is String -> sanitizeBrowserResultString(keyHint, value)
            else -> value
        }
    }

    private fun sanitizeBrowserResult(result: JSONObject): JSONObject {
        return (sanitizeBrowserResultJson(result) as? JSONObject ?: JSONObject())
            .put("valuesRedacted", true)
    }

    private fun sanitizeBrowserResultString(keyHint: String, value: String): String {
        val key = keyHint.lowercase(Locale.ROOT)
        if (value.isBlank()) return value
        return when {
            key in setOf("url", "currenturl", "authurl", "target", "fallbackurl") ||
                key.endsWith("url") -> redactSensitiveUrl(value)
            key in setOf("authcode", "devicecode", "usercode") -> redactAuthCode(value)
            key.contains("token") ||
                key.contains("cookie") ||
                key.contains("password") ||
                key.contains("secret") ||
                key == "raw" -> "REDACTED"
            else -> value
        }
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
            val timestampMs = System.currentTimeMillis()
            val activeRun = runId.ifBlank { terminalViewModel.activeSessionFoldRunId }
            val run = terminalViewModel.sessionFoldRuns.firstOrNull { it.id == activeRun }
                ?: terminalViewModel.sessionFoldRuns.lastOrNull()
            val totalItems = terminalViewModel.sessionFoldRuns.sumOf { it.items.size }
            val userAction = sessionFoldUserAction("", extra)
            localDir().child("session-fold").apply { mkdirs() }.child("status").writeText(
                buildString {
                    append("source=session\n")
                    append("mode=session\n")
                    append("schema_version=").append(BRIDGE_STATUS_SCHEMA_VERSION).append('\n')
                    append("timestamp_ms=").append(timestampMs).append('\n')
                    append("state=").append(refValue(state)).append('\n')
                    append("needs_user=0\n")
                    append("user_action=").append(refValue(userAction)).append('\n')
                    append("reason=").append(refValue(reason)).append('\n')
                    append("request_id=").append(refValue(requestId)).append('\n')
                    append("run_id=").append(refValue(run?.id ?: activeRun)).append('\n')
                    append("item_id=").append(refValue(itemId)).append('\n')
                    append("active_run=").append(refValue(terminalViewModel.activeSessionFoldRunId)).append('\n')
                    append("collapsed=").append(if (run?.collapsed == true) "1" else "0").append('\n')
                    append("timeline_collapsed=").append(if (terminalViewModel.sessionFoldTimelineCollapsed) "1" else "0").append('\n')
                    append("runs=").append(terminalViewModel.sessionFoldRuns.size).append('\n')
                    append("items=").append(totalItems).append('\n')
                    appendSessionFoldExtras(extra)
                    append("stamp=").append(panelEventId(timestampMs)).append('\n')
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
            val timestampMs = System.currentTimeMillis()
            val run = terminalViewModel.sessionFoldRuns.firstOrNull { it.id == runId }
            val userAction = sessionFoldUserAction(type, extra)
            val event = buildString {
                append("event_id=").append(panelEventId(timestampMs)).append('\n')
                append("source=session\n")
                append("mode=session\n")
                append("schema_version=").append(BRIDGE_STATUS_SCHEMA_VERSION).append('\n')
                append("timestamp_ms=").append(timestampMs).append('\n')
                append("type=").append(type).append('\n')
                append("state=").append(refValue(state)).append('\n')
                append("needs_user=0\n")
                append("user_action=").append(refValue(userAction)).append('\n')
                append("reason=").append(refValue(reason)).append('\n')
                append("request_id=").append(refValue(requestId)).append('\n')
                append("run_id=").append(refValue(runId)).append('\n')
                append("item_id=").append(refValue(itemId)).append('\n')
                append("active_run=").append(refValue(terminalViewModel.activeSessionFoldRunId)).append('\n')
                append("collapsed=").append(if (run?.collapsed == true) "1" else "0").append('\n')
                append("timeline_collapsed=").append(if (terminalViewModel.sessionFoldTimelineCollapsed) "1" else "0").append('\n')
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
            val timestampMs = System.currentTimeMillis()
            val run = terminalViewModel.sessionFoldRuns.firstOrNull { it.id == runId }
            val userAction = sessionFoldUserAction(action, extra)
            localDir().child("session-fold").apply { mkdirs() }.child("result").writeText(
                buildString {
                    append("source=session\n")
                    append("mode=session\n")
                    append("schema_version=").append(BRIDGE_STATUS_SCHEMA_VERSION).append('\n')
                    append("timestamp_ms=").append(timestampMs).append('\n')
                    append("request_id=").append(refValue(requestId)).append('\n')
                    append("action=").append(refValue(action)).append('\n')
                    append("ok=").append(if (ok) "1" else "0").append('\n')
                    append("state=").append(refValue(state)).append('\n')
                    append("needs_user=0\n")
                    append("user_action=").append(refValue(userAction)).append('\n')
                    append("reason=").append(refValue(reason)).append('\n')
                    append("run_id=").append(refValue(runId)).append('\n')
                    append("item_id=").append(refValue(itemId)).append('\n')
                    append("active_run=").append(refValue(terminalViewModel.activeSessionFoldRunId)).append('\n')
                    append("collapsed=").append(if (run?.collapsed == true) "1" else "0").append('\n')
                    append("timeline_collapsed=").append(if (terminalViewModel.sessionFoldTimelineCollapsed) "1" else "0").append('\n')
                    if (error.isNotBlank()) append("error=").append(refValue(error)).append('\n')
                    appendSessionFoldExtras(extra)
                }
            )
        } catch (_: Exception) {
            // Best-effort session-fold result bridge.
        }
    }

    private fun sessionFoldUserAction(type: String, extras: Map<String, String>): String {
        extras["user_action"]?.takeIf { it.isNotBlank() }?.let { return it }
        extras["userAction"]?.takeIf { it.isNotBlank() }?.let { return it }
        return normalizedUserAction(type)
    }

    private fun StringBuilder.appendSessionFoldExtras(extras: Map<String, String>) {
        val reserved = setOf(
            "event_id", "source", "mode", "schema_version", "timestamp_ms", "type", "state",
            "needs_user", "needsUser", "user_action", "userAction", "reason", "request_id", "run_id",
            "item_id", "active_run", "collapsed", "timeline_collapsed", "runs", "items",
            "stamp", "ok", "action"
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

    private fun restoreMediaPreviewCacheAfterColdStart() {
        if (mediaPreviewCacheRestoreStarted) return
        mediaPreviewCacheRestoreStarted = true
        lifecycleScope.launch {
            val restored = recoverMediaPreviewCache()
            restored.forEach { preview -> addMediaPreviewWithCacheCleanup(preview) }
            if (restored.isNotEmpty()) {
                syncMediaPreviewStatus(reason = "startup_restore", state = "ready")
                writeAgentPanelEvent(
                    source = "files",
                    type = "agent_restored_cache",
                    state = "ready",
                    reason = "startup_restore",
                    extra = mapOf("restored_count" to restored.size.toString())
                )
                writeAgentPanelStatus(
                    source = "files",
                    state = "ready",
                    reason = "startup_restore",
                    extra = mapOf("restored_count" to restored.size.toString())
                )
            }
        }
    }

    private suspend fun recoverMediaPreviewCache(): List<TerminalMediaPreview> {
        val previewDir = localDir().child("media-preview")
        val refsDir = previewDir.child("refs")
        val refs = withContext(Dispatchers.IO) {
            refsDir.listFiles()
                ?.filter { it.isFile && !it.name.endsWith(".tmp") }
                ?.sortedBy { it.lastModified() }
                ?: emptyList()
        }
        val candidates = mutableListOf<TerminalMediaPreview>()
        for (ref in refs) {
            val values = withContext(Dispatchers.IO) {
                runCatching { parseMediaPreviewRequest(ref.readText()) }.getOrDefault(emptyMap())
            }
            val path = values["path"]?.let { unrefValue(it) }.orEmpty()
            val file = File(path)
            val kind = mediaPreviewKindFromString(values["kind"].orEmpty())
            val readable = withContext(Dispatchers.IO) { file.isFile && file.canRead() }
            if (path.isBlank() || kind == null || !readable || !isLocalPreviewCacheFile(file)) {
                withContext(Dispatchers.IO) { runCatching { ref.delete() } }
                continue
            }

            val bounds = if (kind == TerminalMediaPreviewKind.IMAGE) readImageBounds(file) else null
            val textPreview = if (kind == TerminalMediaPreviewKind.TEXT) readTextPreview(file) else null
            candidates.add(
                TerminalMediaPreview(
                    path = file.absolutePath,
                    name = values["name"]?.let { unrefValue(it) }?.ifBlank { file.name } ?: file.name,
                    kind = kind,
                    stamp = values["stamp"]?.let { unrefValue(it) }?.ifBlank { ref.name } ?: ref.name,
                    width = bounds?.first,
                    height = bounds?.second,
                    sizeBytes = file.length(),
                    mimeType = mimeTypeForPreview(kind, file),
                    textPreview = textPreview
                )
            )
        }

        val survivors = enforceMediaPreviewCacheBudget(candidates)
        val survivorPaths = survivors.map { canonicalPathOrAbsolute(File(it.path)) }.toSet()
        withContext(Dispatchers.IO) {
            cleanupOrphanMediaPreviewCacheFiles(survivorPaths)
        }
        return survivors.sortedBy { File(it.path).lastModified() }
    }

    private suspend fun enforceMediaPreviewCacheBudget(
        candidates: List<TerminalMediaPreview>
    ): List<TerminalMediaPreview> = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        val newestFirst = candidates.sortedByDescending { File(it.path).lastModified() }
        val kept = mutableListOf<TerminalMediaPreview>()
        var keptBytes = 0L
        for (preview in newestFirst) {
            val file = File(preview.path)
            val size = file.length().coerceAtLeast(0L)
            val tooOld = now - file.lastModified() > MEDIA_PREVIEW_MAX_CACHE_AGE_MS
            val overCount = kept.size >= MEDIA_PREVIEW_RESTORE_LIMIT ||
                kept.size >= MEDIA_PREVIEW_MAX_CACHE_FILES
            val overBytes = keptBytes + size > MEDIA_PREVIEW_MAX_CACHE_BYTES
            if (tooOld || overCount || overBytes) {
                deleteMediaPreviewCacheNow(preview)
            } else {
                kept.add(preview)
                keptBytes += size
            }
        }
        kept
    }

    private fun addMediaPreviewWithCacheCleanup(preview: TerminalMediaPreview) {
        val evicted = terminalViewModel.addMediaPreview(preview)
        if (evicted.isNotEmpty()) {
            lifecycleScope.launch(Dispatchers.IO) {
                evicted.forEach { deleteMediaPreviewCacheNow(it) }
            }
        }
    }

    private fun deleteMediaPreviewCache(preview: TerminalMediaPreview) {
        lifecycleScope.launch(Dispatchers.IO) {
            deleteMediaPreviewCacheNow(preview)
        }
    }

    private fun deleteMediaPreviewCacheNow(preview: TerminalMediaPreview) {
        val file = File(preview.path)
        if (isLocalPreviewCacheFile(file)) {
            runCatching { file.delete() }
        }
        runCatching { removePreviewReference(preview) }
    }

    private fun clearAllMediaPreviewCache(previewDir: File = localDir().child("media-preview")) {
        runCatching { previewDir.child("files").deleteRecursively() }
        runCatching { previewDir.child("refs").deleteRecursively() }
        runCatching { previewDir.child("queue").deleteRecursively() }
        runCatching { localDir().child("browser").child("screenshots").deleteRecursively() }
    }

    private fun cleanupOrphanMediaPreviewCacheFiles(survivorPaths: Set<String>) {
        mediaPreviewCacheRoots().forEach { root ->
            if (!root.isDirectory) return@forEach
            root.walkTopDown()
                .filter { it.isFile }
                .forEach { file ->
                    val canonical = canonicalPathOrAbsolute(file)
                    if (canonical !in survivorPaths) {
                        runCatching { file.delete() }
                    }
                }
        }
    }

    private fun mediaPreviewCacheRoots(): List<File> {
        return listOf(
            localDir().child("media-preview").child("files"),
            localDir().child("browser").child("screenshots")
        )
    }

    private fun isLocalPreviewCacheFile(file: File): Boolean {
        val filePath = canonicalPathOrAbsolute(file)
        return mediaPreviewCacheRoots().any { root ->
            val rootPath = canonicalPathOrAbsolute(root)
            filePath == rootPath || filePath.startsWith("$rootPath${File.separator}")
        }
    }

    private fun canonicalPathOrAbsolute(file: File): String {
        return runCatching { file.canonicalPath }.getOrElse { file.absolutePath }
    }

    private fun mediaPreviewKindFromString(value: String): TerminalMediaPreviewKind? {
        return when (value.lowercase(Locale.ROOT)) {
            "image" -> TerminalMediaPreviewKind.IMAGE
            "video" -> TerminalMediaPreviewKind.VIDEO
            "text" -> TerminalMediaPreviewKind.TEXT
            else -> null
        }
    }

    private fun mimeTypeForPreview(kind: TerminalMediaPreviewKind, file: File): String {
        return when (kind) {
            TerminalMediaPreviewKind.IMAGE -> "image/${file.extension.ifBlank { "png" }}"
            TerminalMediaPreviewKind.VIDEO -> "video/${file.extension.ifBlank { "mp4" }}"
            TerminalMediaPreviewKind.TEXT -> "text/plain"
        }
    }

    fun dismissMediaPreview() {
        terminalViewModel.clearMediaPreviews()
        lifecycleScope.launch(Dispatchers.IO) {
            clearAllMediaPreviewCache()
        }
        writeMediaPreviewStatus(localDir().child("media-preview"), "closed=1\n")
        writeAgentPanelEvent(source = "files", type = "user_cleared", state = "closed", reason = "clear")
        writeAgentPanelStatus(source = "files", state = "closed", reason = "clear")
    }

    fun removeMediaPreview(preview: TerminalMediaPreview) {
        val refId = previewReferenceId(preview)
        val previewExtras = mediaPreviewExtras(preview)
        terminalViewModel.removeMediaPreview(preview.stamp)
        deleteMediaPreviewCache(preview)
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
        sendPreviewsToAi(listOf(preview), userMessage)
    }

    fun sendPreviewsToAi(previews: List<TerminalMediaPreview>, userMessage: String) {
        if (previews.isEmpty()) {
            toast("请先勾选要发送的文件")
            return
        }
        val session = terminalViewModel.terminalView?.currentSession
        if (session == null) {
            toast("当前终端会话不可用")
            return
        }

        val displayNames = buildPreviewDisplayNames(terminalViewModel.mediaPreviews.toList())
        val cleanMessage = collapseTerminalText(userMessage)
        val sentLabels = mutableListOf<String>()
        val prompt = buildString {
            previews.forEachIndexed { index, preview ->
                val refId = previewReferenceId(preview)
                val refWritten = runCatching {
                    writePreviewReference(preview, refId)
                }.onFailure { error ->
                    toast("无法创建文件引用：${error.message}")
                }.isSuccess
                if (!refWritten) return@forEachIndexed

                val label = displayNames[preview.stamp] ?: shortPreviewDisplayName(preview, index + 1)
                if (isNotEmpty()) append('\n')
                append(label).append("[").append(refId).append("] ")
                if (index == 0 && cleanMessage.isNotBlank()) {
                    append(cleanMessage).append("。")
                }
                append("路径：codex-preview path ").append(refId)

                writeAgentPanelEvent(
                    source = "files",
                    type = "user_sent_file",
                    state = "done",
                    reason = cleanMessage,
                    itemId = refId,
                    extra = mediaPreviewExtras(preview) + mapOf("display_name" to label)
                )
                writeAgentPanelStatus(
                    source = "files",
                    state = "done",
                    reason = "sent_to_terminal",
                    itemId = refId
                )
                appendActiveSessionFoldItem(
                    kind = TerminalSessionFoldItemKind.FILE,
                    title = label,
                    summary = cleanMessage,
                    path = preview.path,
                    status = "done",
                    itemId = refId
                )
                sentLabels.add(label)
            }
        }
        if (prompt.isBlank() || sentLabels.isEmpty()) return
        submitPromptToSession(session, prompt)
        val toastLabel = if (sentLabels.size == 1) {
            sentLabels.first()
        } else {
            sentLabels.take(3).joinToString("、") + if (sentLabels.size > 3) " 等${sentLabels.size}项" else ""
        }
        toast("已发送：$toastLabel")
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
        // Keep on-disk names short; UI renumbers as 文本N for display.
        val target = mediaDir.child("$stamp-text.txt")
        val written = runCatching {
            mediaDir.mkdirs()
            target.writeText(text.replace("\r\n", "\n"), Charsets.UTF_8)
        }.onFailure { error ->
            toast("无法保存文本：${error.message}")
        }.isSuccess
        if (!written) return false

        val textIndex = terminalViewModel.mediaPreviews.count {
            it.kind == TerminalMediaPreviewKind.TEXT
        } + 1
        val preview = TerminalMediaPreview(
            path = target.absolutePath,
            name = "文本$textIndex",
            kind = TerminalMediaPreviewKind.TEXT,
            stamp = stamp,
            sizeBytes = target.length(),
            mimeType = "text/plain",
            textPreview = text.take(64 * 1024),
            source = TerminalMediaPreviewSource.USER
        )
        addMediaPreviewWithCacheCleanup(preview)

        val refId = previewReferenceId(preview)
        val refWritten = runCatching {
            writePreviewReference(preview, refId)
        }.onFailure { error ->
            toast("无法创建文本引用：${error.message}")
        }.isSuccess
        if (!refWritten) return false

        submitPromptToSession(
            session,
            buildString {
                append("文本[").append(refId).append("] 路径：codex-preview path ").append(refId)
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
        return value
            .replace("\\", "\\\\")
            .replace("\r", "\\r")
            .replace("\n", "\\n")
    }

    private fun unrefValue(value: String): String {
        val out = StringBuilder()
        var escaping = false
        value.forEach { ch ->
            if (escaping) {
                out.append(
                    when (ch) {
                        'r' -> '\r'
                        'n' -> '\n'
                        '\\' -> '\\'
                        else -> ch
                    }
                )
                escaping = false
            } else if (ch == '\\') {
                escaping = true
            } else {
                out.append(ch)
            }
        }
        if (escaping) out.append('\\')
        return out.toString()
    }

    private fun bridgeTextKeys(text: String): Set<String> {
        return text.lineSequence().mapNotNull { line ->
            val idx = line.indexOf('=')
            if (idx > 0) line.substring(0, idx).trim() else null
        }.toSet()
    }

    private fun bridgeTextValue(text: String, key: String): String {
        val prefix = "$key="
        return text.lineSequence()
            .firstOrNull { it.startsWith(prefix) }
            ?.substring(prefix.length)
            .orEmpty()
    }

    private fun StringBuilder.appendBridgeFieldIfMissing(
        existingKeys: Set<String>,
        key: String,
        value: String
    ) {
        if (key !in existingKeys) {
            append(key).append('=').append(refValue(value)).append('\n')
        }
    }

    private fun collapseTerminalText(value: String): String {
        return value.replace(Regex("\\s+"), " ").trim()
    }

    private fun submitPromptToSession(session: TerminalSession, prompt: String) {
        val cleanPrompt = prompt.trimEnd('\r', '\n')
        session.write(cleanPrompt)

        val terminalView = terminalViewModel.terminalView
        if (terminalView?.currentSession !== session) {
            lifecycleScope.launch {
                delay(TRAY_SEND_ENTER_DELAY_MS)
                session.write("\r")
            }
            return
        }

        terminalView.requestFocus()
        // Keep the submit key separate from the programmatic text write. Codex
        // may classify a same-tick text+enter burst as pasted text and leave it
        // in the composer; a short delay makes this follow the real user key
        // path while still feeling immediate in the tray UI.
        terminalView.postDelayed({
            if (terminalView.currentSession === session) {
                terminalView.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                terminalView.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
            } else {
                session.write("\r")
            }
        }, TRAY_SEND_ENTER_DELAY_MS)
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
        terminalViewModel.browserPanelExpanded = false
        if (terminalViewModel.browserSnapshot.authTask?.active == true) {
            markBrowserAuthCollapsed()
            return
        }
        val collapseState = if (terminalViewModel.browserSnapshot.needsUser) "collapsed" else "done"
        if (terminalViewModel.browserSnapshot.needsUser) {
            lifecycleScope.launch {
                val browserDir = localDir().child("browser")
                val requestId = terminalViewModel.browserSnapshot.requestId
                    .ifBlank { "manual-user-collapse-${System.currentTimeMillis()}" }
                val result = browserSessionManager.handleRequest(
                    mapOf("action" to "user_collapse", "request_id" to requestId),
                    browserDir
                )
                writeBrowserResult(browserDir, result)
            }
        }
        writeAgentPanelEvent(
            source = "browser",
            type = "user_collapsed",
            state = collapseState,
            reason = "collapse",
            requestId = terminalViewModel.browserSnapshot.requestId
        )
        writeAgentPanelStatus(
            source = "browser",
            state = collapseState,
            reason = "collapse",
            requestId = terminalViewModel.browserSnapshot.requestId
        )
    }

    fun closeBrowserSession() {
        val snapshot = terminalViewModel.browserSnapshot
        if (snapshot.authTask?.active == true || snapshot.externalPrompt != null) {
            cancelBrowserUserAction()
            return
        }
        terminalViewModel.browserPanelExpanded = false
        writeAgentPanelEvent(
            source = "browser",
            type = "user_cancelled",
            state = "cancelled",
            reason = "close",
            requestId = snapshot.requestId
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
        val isAuth = terminalViewModel.browserSnapshot.authTask?.active == true
        writeAgentPanelEvent(
            source = "browser",
            type = if (isAuth) "auth_done" else reason,
            state = "done",
            reason = if (isAuth) "auth_done" else reason,
            requestId = requestId
        )
        lifecycleScope.launch {
            val browserDir = localDir().child("browser")
            val result = browserSessionManager.handleRequest(
                mapOf("action" to if (isAuth) "auth_done" else "user_done", "request_id" to requestId),
                browserDir
            )
            writeBrowserResult(browserDir, result)
        }
    }

    fun markBrowserAuthCollapsed() {
        val requestId = terminalViewModel.browserSnapshot.authTask?.requestId
            ?: terminalViewModel.browserSnapshot.requestId.ifBlank { "manual-auth-collapse-${System.currentTimeMillis()}" }
        writeAgentPanelEvent(
            source = "browser",
            type = "auth_collapsed",
            state = "collapsed",
            reason = "auth_collapse",
            requestId = requestId,
            extra = browserSnapshotExtras(terminalViewModel.browserSnapshot) + ("user_action" to "collapse")
        )
        lifecycleScope.launch {
            val browserDir = localDir().child("browser")
            val result = browserSessionManager.handleRequest(
                mapOf("action" to "auth_collapse", "request_id" to requestId, "auth_request_id" to requestId),
                browserDir
            )
            writeBrowserResult(browserDir, result)
        }
    }

    fun reopenBrowserAuth() {
        val requestId = terminalViewModel.browserSnapshot.authTask?.requestId
            ?: terminalViewModel.browserSnapshot.requestId.ifBlank { "manual-auth-reopen-${System.currentTimeMillis()}" }
        terminalViewModel.mediaPreviewExpanded = false
        terminalViewModel.browserPanelExpanded = true
        writeAgentPanelEvent(
            source = "browser",
            type = "auth_reopened",
            state = "reopened",
            reason = "auth_reopen",
            requestId = requestId,
            extra = browserSnapshotExtras(terminalViewModel.browserSnapshot) + ("user_action" to "reopen")
        )
        lifecycleScope.launch {
            val browserDir = localDir().child("browser")
            val result = browserSessionManager.handleRequest(
                mapOf("action" to "auth_reopen", "request_id" to requestId, "auth_request_id" to requestId),
                browserDir
            )
            writeBrowserResult(browserDir, result)
        }
    }

    fun cancelBrowserUserAction() {
        terminalViewModel.browserPanelExpanded = false
        val snapshot = terminalViewModel.browserSnapshot
        val authRequestId = snapshot.authTask?.requestId
        val externalRequestId = snapshot.externalPrompt?.requestId
        val requestId = authRequestId ?: externalRequestId ?: snapshot.requestId.ifBlank {
            "manual-user-cancel-${System.currentTimeMillis()}"
        }
        val action = when {
            authRequestId != null -> "auth_cancel"
            externalRequestId != null -> "external_cancel"
            else -> "user_cancelled"
        }
        writeAgentPanelEvent(
            source = "browser",
            type = when (action) {
                "auth_cancel" -> "auth_cancelled"
                "external_cancel" -> "external_open_cancelled"
                else -> "user_cancelled"
            },
            state = "cancelled",
            reason = action,
            requestId = requestId,
            extra = browserSnapshotExtras(snapshot) + ("user_action" to "cancel")
        )
        lifecycleScope.launch {
            val browserDir = localDir().child("browser")
            val result = browserSessionManager.handleRequest(
                mapOf(
                    "action" to action,
                    "request_id" to requestId,
                    "auth_request_id" to authRequestId.orEmpty(),
                    "external_request_id" to externalRequestId.orEmpty()
                ),
                browserDir
            )
            writeBrowserResult(browserDir, result)
        }
    }

    fun confirmBrowserExternalOpen() {
        val snapshot = terminalViewModel.browserSnapshot
        val requestId = snapshot.externalPrompt?.requestId
            ?: snapshot.requestId.ifBlank { "manual-external-confirm-${System.currentTimeMillis()}" }
        writeAgentPanelEvent(
            source = "browser",
            type = "external_open_confirmed",
            state = "done",
            reason = "external_confirm",
            requestId = requestId,
            extra = browserSnapshotExtras(snapshot) + ("user_action" to "confirm")
        )
        lifecycleScope.launch {
            val browserDir = localDir().child("browser")
            val result = browserSessionManager.handleRequest(
                mapOf("action" to "external_confirm", "request_id" to requestId, "external_request_id" to requestId),
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

    fun toggleSessionFoldTimeline() {
        setSessionFoldTimelineCollapsed(
            collapsed = !terminalViewModel.sessionFoldTimelineCollapsed,
            reason = "timeline_toggle"
        )
    }

    private fun setSessionFoldTimelineCollapsed(
        collapsed: Boolean,
        reason: String,
        requestId: String = "",
        action: String = "timeline",
        actor: String = "user"
    ) {
        terminalViewModel.updateSessionFoldTimelineCollapsed(collapsed)
        val state = if (collapsed) "collapsed" else "expanded"
        writeSessionFoldEvent(
            type = "${actor}_timeline_$state",
            state = state,
            reason = reason,
            requestId = requestId,
            extra = mapOf("timeline_action" to action)
        )
        writeSessionFoldStatus(
            state = state,
            reason = reason,
            requestId = requestId,
            extra = mapOf("timeline_action" to action)
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

    private fun persistBrowserSnapshot(snapshot: TerminalBrowserSnapshot) {
        runCatching {
            val browserDir = localDir().child("browser")
            val requestId = snapshot.requestId.ifBlank { "snapshot-${System.currentTimeMillis()}" }
            if (shouldSkipTerminalBrowserSnapshotPersist(browserDir, snapshot, requestId)) {
                return@runCatching
            }
            val result = JSONObject()
                .put("ok", true)
                .put("requestId", requestId)
                .put("action", "snapshot")
                .put("snapshot", browserSnapshotJson(snapshot))
            writeBrowserResult(browserDir, result)
        }
    }

    private fun shouldSkipTerminalBrowserSnapshotPersist(
        browserDir: File,
        snapshot: TerminalBrowserSnapshot,
        requestId: String
    ): Boolean {
        if (requestId.isBlank() || requestId.startsWith("snapshot-")) return false
        if (snapshot.status !in setOf("done", "ready", "closed", "cancelled", "collapsed", "user_done")) return false
        return browserResultHasExplicitAction(browserDir, requestId)
    }

    private fun browserResultHasExplicitAction(browserDir: File, requestId: String): Boolean {
        val safeId = safeBridgeRequestId(requestId)
        val candidates = buildList {
            if (safeId.isNotBlank()) add(browserDir.child("results").child("$safeId.status"))
            add(browserDir.child("status"))
        }
        return candidates.any { file ->
            runCatching {
                if (!file.isFile) return@runCatching false
                file.useLines { lines ->
                    lines.take(80).mapNotNull { line ->
                        line.removePrefix("action=").takeIf { it != line }
                    }.any { action ->
                        action.isNotBlank() && action != "snapshot"
                    }
                }
            }.getOrDefault(false)
        }
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
            summary = current.message.ifBlank { current.title.ifBlank { redactSensitiveUrl(current.currentUrl) } },
            path = redactSensitiveUrl(current.currentUrl),
            status = "waiting_for_user",
            itemId = current.requestId.ifBlank { "browser-${System.currentTimeMillis()}" }
        )
    }

    private fun primeMediaPreviewRequestCache() {
        val previewDir = localDir().child("media-preview")
        lastMediaPreviewRequest = primeRecoverableRequestCache(
            bridgeDir = previewDir,
            resultFileName = "result",
            processedCache = mediaPreviewProcessedRequestIds
        )
    }

    private fun primeBrowserRequestCache() {
        val browserDir = localDir().child("browser")
        lastBrowserRequest = try {
            val requestFile = browserDir.child("request")
            val content = if (requestFile.isFile) requestFile.readText().trim() else ""
            if (content.isBlank()) {
                ""
            } else {
                val requestId = panelRequestId(parseMediaPreviewRequest(content), content)
                if (browserRequestResultMatches(browserDir, requestId)) {
                    rememberBrowserRequestId(requestId)
                    content
                } else {
                    ""
                }
            }
        } catch (_: Exception) {
            ""
        }
    }

    private fun primeSessionFoldRequestCache() {
        val foldDir = localDir().child("session-fold")
        lastSessionFoldRequest = primeRecoverableRequestCache(
            bridgeDir = foldDir,
            resultFileName = "result",
            processedCache = sessionFoldProcessedRequestIds
        )
    }

    private fun primeRecoverableRequestCache(
        bridgeDir: File,
        resultFileName: String,
        processedCache: LinkedHashSet<String>
    ): String {
        return try {
            val requestFile = bridgeDir.child("request")
            val content = if (requestFile.isFile) requestFile.readText().trim() else ""
            if (content.isBlank()) {
                ""
            } else {
                val requestId = panelRequestId(parseMediaPreviewRequest(content), content)
                if (bridgeResultMatchesRequest(bridgeDir, resultFileName, requestId)) {
                    rememberRequestId(processedCache, requestId)
                    content
                } else {
                    ""
                }
            }
        } catch (_: Exception) {
            ""
        }
    }

    private fun startMediaPreviewBridge() {
        if (mediaPreviewJob?.isActive == true) return
        val previewDir = localDir().child("media-preview").apply { mkdirs() }
        val queueDir = previewDir.child("queue").apply { mkdirs() }
        mediaPreviewObserver = startBridgeRequestObserver(
            dir = previewDir,
            requestFileName = "request"
        ) {
            scheduleMediaPreviewPoll()
        }
        mediaPreviewQueueObserver = startBridgeQueueObserver(queueDir) {
            scheduleMediaPreviewPoll()
        }
        writeTerminalPerformanceStatus()
        mediaPreviewJob = lifecycleScope.launch {
            while (isActive) {
                pollMediaPreviewRequestLocked()
                delay(BRIDGE_FALLBACK_POLL_MS)
            }
        }
    }

    private fun startBrowserBridge() {
        if (browserBridgeJob?.isActive == true) return
        val browserDir = localDir().child("browser").apply { mkdirs() }
        val queueDir = browserDir.child("queue").apply { mkdirs() }
        browserRequestObserver = startBridgeRequestObserver(
            dir = browserDir,
            requestFileName = "request"
        ) {
            scheduleBrowserPoll()
        }
        browserQueueObserver = startBridgeQueueObserver(queueDir) {
            scheduleBrowserPoll()
        }
        writeTerminalPerformanceStatus()
        browserBridgeJob = lifecycleScope.launch {
            while (isActive) {
                pollBrowserRequestLocked()
                delay(BRIDGE_FALLBACK_POLL_MS)
            }
        }
    }

    private fun startSessionFoldBridge() {
        if (sessionFoldJob?.isActive == true) return
        val foldDir = localDir().child("session-fold").apply { mkdirs() }
        val queueDir = foldDir.child("queue").apply { mkdirs() }
        sessionFoldObserver = startBridgeRequestObserver(
            dir = foldDir,
            requestFileName = "request"
        ) {
            scheduleSessionFoldPoll()
        }
        sessionFoldQueueObserver = startBridgeQueueObserver(queueDir) {
            scheduleSessionFoldPoll()
        }
        writeTerminalPerformanceStatus()
        sessionFoldJob = lifecycleScope.launch {
            while (isActive) {
                pollSessionFoldRequestLocked()
                delay(BRIDGE_FALLBACK_POLL_MS)
            }
        }
    }

    private fun scheduleMediaPreviewPoll() {
        writeTerminalPerformanceStatus()
        lifecycleScope.launch {
            pollMediaPreviewRequestLocked()
        }
    }

    private fun scheduleBrowserPoll() {
        writeTerminalPerformanceStatus()
        lifecycleScope.launch {
            pollBrowserRequestLocked()
        }
    }

    private fun scheduleSessionFoldPoll() {
        writeTerminalPerformanceStatus()
        lifecycleScope.launch {
            pollSessionFoldRequestLocked()
        }
    }

    private suspend fun pollMediaPreviewRequestLocked() {
        mediaPreviewPollMutex.withLock {
            runCatching {
                pollMediaPreviewRequest()
            }.onFailure { error ->
                if (error is CancellationException) throw error
            }
        }
        writeTerminalPerformanceStatus()
    }

    private suspend fun pollBrowserRequestLocked() {
        browserPollMutex.withLock {
            runCatching {
                pollBrowserRequest()
            }.onFailure { error ->
                if (error is CancellationException) throw error
                writeBrowserBridgeError(
                    browserDir = localDir().child("browser"),
                    requestId = "poll-${System.currentTimeMillis()}",
                    action = "poll",
                    error = error
                )
            }
        }
        writeTerminalPerformanceStatus()
    }

    private suspend fun pollSessionFoldRequestLocked() {
        sessionFoldPollMutex.withLock {
            runCatching {
                pollSessionFoldRequest()
            }.onFailure { error ->
                if (error is CancellationException) throw error
            }
        }
        writeTerminalPerformanceStatus()
    }

    private fun startBridgeRequestObserver(
        dir: File,
        requestFileName: String,
        onChanged: () -> Unit
    ): FileObserver? {
        return startBridgeObserver(dir, REQUEST_FILE_OBSERVER_EVENTS) { event, path ->
            if ((event and REQUEST_FILE_OBSERVER_EVENTS) != 0 && (path.isNullOrBlank() || path == requestFileName)) {
                onChanged()
            }
        }
    }

    private fun startBridgeQueueObserver(
        dir: File,
        onChanged: () -> Unit
    ): FileObserver? {
        return startBridgeObserver(dir, QUEUE_FILE_OBSERVER_EVENTS) { event, path ->
            if ((event and QUEUE_FILE_OBSERVER_EVENTS) != 0 && path?.endsWith(".req") == true) {
                onChanged()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun startBridgeObserver(
        dir: File,
        events: Int,
        onEvent: (event: Int, path: String?) -> Unit
    ): FileObserver? {
        return runCatching {
            dir.mkdirs()
            object : FileObserver(dir.absolutePath, events) {
                override fun onEvent(event: Int, path: String?) {
                    onEvent(event, path)
                }
            }.also { it.startWatching() }
        }.getOrNull()
    }

    private fun stopBridgeObservers() {
        mediaPreviewObserver?.stopWatching()
        mediaPreviewObserver = null
        mediaPreviewQueueObserver?.stopWatching()
        mediaPreviewQueueObserver = null
        browserRequestObserver?.stopWatching()
        browserRequestObserver = null
        browserQueueObserver?.stopWatching()
        browserQueueObserver = null
        sessionFoldObserver?.stopWatching()
        sessionFoldObserver = null
        sessionFoldQueueObserver?.stopWatching()
        sessionFoldQueueObserver = null
        writeTerminalPerformanceStatus()
    }

    private fun bridgeMode(): String {
        return if (
            mediaPreviewObserver != null ||
            mediaPreviewQueueObserver != null ||
            browserRequestObserver != null ||
            browserQueueObserver != null ||
            sessionFoldObserver != null ||
            sessionFoldQueueObserver != null
        ) {
            "file_observer"
        } else {
            "fallback_poll"
        }
    }

    private fun writeTerminalPerformanceStatus() {
        val now = System.currentTimeMillis()
        val shouldWrite = synchronized(terminalPerfStatusLock) {
            if (now - lastTerminalPerfStatusWriteAt < TERMINAL_PERF_STATUS_MIN_INTERVAL_MS) {
                false
            } else {
                lastTerminalPerfStatusWriteAt = now
                true
            }
        }
        if (!shouldWrite) return
        val render = TerminalRenderPerformanceMetrics.snapshot()
        runCatching {
            localDir().child("perf").apply { mkdirs() }.child("terminal.status").writeText(
                buildString {
                    append("source=ops\n")
                    append("mode=ops\n")
                    append("schema_version=").append(BRIDGE_STATUS_SCHEMA_VERSION).append('\n')
                    append("timestamp_ms=").append(now).append('\n')
                    append("state=ready\n")
                    append("needs_user=0\n")
                    append("user_action=\n")
                    append("render_requests=").append(render.renderRequests).append('\n')
                    append("render_frames=").append(render.renderFrames).append('\n')
                    append("coalesced_requests=").append(render.coalescedRequests).append('\n')
                    append("burst_mode=").append(if (render.burstMode) "1" else "0").append('\n')
                    append("last_frame_ms=").append(render.lastFrameMs).append('\n')
                    append("avg_frame_ms=").append(render.avgFrameMs).append('\n')
                    append("max_frame_ms=").append(render.maxFrameMs).append('\n')
                    append("last_request_ms=").append(render.lastRequestMs).append('\n')
                    append("last_request_age_ms=").append(render.lastRequestAgeMs).append('\n')
                    append("last_request_to_frame_ms=").append(render.lastRequestToFrameMs).append('\n')
                    append("input_events=").append(render.inputEvents).append('\n')
                    append("last_input_ms=").append(render.lastInputMs).append('\n')
                    append("last_input_age_ms=").append(render.lastInputAgeMs).append('\n')
                    append("recent_window_ms=").append(render.recentWindowMs).append('\n')
                    append("recent_window_age_ms=").append(render.recentWindowAgeMs).append('\n')
                    append("recent_input_events=").append(render.recentInputEvents).append('\n')
                    append("recent_render_requests=").append(render.recentRenderRequests).append('\n')
                    append("recent_coalesced_requests=").append(render.recentCoalescedRequests).append('\n')
                    append("slow_frames_16ms=").append(render.slowFrames16Ms).append('\n')
                    append("slow_frames_32ms=").append(render.slowFrames32Ms).append('\n')
                    append("bridge_mode=").append(bridgeMode()).append('\n')
                    append("fallback_interval_ms=").append(BRIDGE_FALLBACK_POLL_MS).append('\n')
                    append("media_preview_observer=").append(if (mediaPreviewObserver != null) "1" else "0").append('\n')
                    append("media_preview_queue_observer=").append(if (mediaPreviewQueueObserver != null) "1" else "0").append('\n')
                    append("browser_request_observer=").append(if (browserRequestObserver != null) "1" else "0").append('\n')
                    append("browser_queue_observer=").append(if (browserQueueObserver != null) "1" else "0").append('\n')
                    append("session_fold_observer=").append(if (sessionFoldObserver != null) "1" else "0").append('\n')
                    append("session_fold_queue_observer=").append(if (sessionFoldQueueObserver != null) "1" else "0").append('\n')
                    append("stamp=").append(now).append('\n')
                }
            )
        }
    }


    private suspend fun queuedRequestFiles(bridgeDir: File): List<File> = withContext(Dispatchers.IO) {
        val queueDir = bridgeDir.child("queue")
        bridgeDir.mkdirs()
        queueDir.mkdirs()
        queueDir.listFiles()
            ?.filter { it.isFile && it.name.endsWith(".req") }
            ?.sortedBy { it.name }
            ?: emptyList()
    }

    private fun safeBridgeRequestId(requestId: String): String {
        return requestId.filter { it.isLetterOrDigit() || it == '.' || it == '_' || it == '-' }.take(120)
    }

    private fun bridgeResultMatchesRequest(
        bridgeDir: File,
        resultFileName: String,
        requestId: String
    ): Boolean {
        if (requestId.isBlank()) return false
        return bridgeStatusFileMatchesRequest(bridgeDir.child(resultFileName), requestId)
    }

    private fun browserRequestResultMatches(browserDir: File, requestId: String): Boolean {
        if (requestId.isBlank()) return false
        val safeId = safeBridgeRequestId(requestId)
        val resultsDir = browserDir.child("results")
        return (safeId.isNotBlank() && (
            bridgeStatusFileMatchesRequest(resultsDir.child("$safeId.status"), requestId) ||
                resultsDir.child("$safeId.json").isFile
            )) ||
            bridgeStatusFileMatchesRequest(browserDir.child("status"), requestId)
    }

    private fun bridgeStatusFileMatchesRequest(file: File, requestId: String): Boolean {
        if (requestId.isBlank() || !file.isFile) return false
        val expected = "request_id=${refValue(requestId)}"
        val rawExpected = "request_id=$requestId"
        return runCatching {
            file.useLines { lines ->
                lines.take(80).any { line -> line == expected || line == rawExpected }
            }
        }.getOrDefault(false)
    }

    private fun isRequestProcessed(cache: LinkedHashSet<String>, requestId: String): Boolean {
        return requestId.isNotBlank() && cache.contains(requestId)
    }

    private fun rememberRequestId(cache: LinkedHashSet<String>, requestId: String) {
        if (requestId.isBlank()) return
        cache.add(requestId)
        while (cache.size > 200) {
            cache.remove(cache.first())
        }
    }

    private suspend fun pollSessionFoldRequest() {
        val foldDir = localDir().child("session-fold")
        val requestFile = foldDir.child("request")
        for (file in queuedRequestFiles(foldDir)) {
            val queuedContent = withContext(Dispatchers.IO) {
                if (file.isFile) file.readText().trim() else ""
            }
            if (queuedContent.isNotBlank()) {
                val queuedRequest = parseMediaPreviewRequest(queuedContent)
                val queuedRequestId = panelRequestId(queuedRequest, queuedContent)
                if (!isSessionFoldRequestProcessed(foldDir, queuedRequestId)) {
                    handleSessionFoldRequestContent(foldDir, queuedContent)
                    rememberRequestId(sessionFoldProcessedRequestIds, queuedRequestId)
                }
            }
            withContext(Dispatchers.IO) { runCatching { file.delete() } }
        }

        val content = withContext(Dispatchers.IO) {
            foldDir.mkdirs()
            if (requestFile.isFile) requestFile.readText() else ""
        }.trim()

        if (content.isBlank() || content == lastSessionFoldRequest) return
        val requestId = panelRequestId(parseMediaPreviewRequest(content), content)
        if (isSessionFoldRequestProcessed(foldDir, requestId)) {
            lastSessionFoldRequest = content
            return
        }
        lastSessionFoldRequest = content
        handleSessionFoldRequestContent(foldDir, content)
        rememberRequestId(sessionFoldProcessedRequestIds, requestId)
    }

    private fun isSessionFoldRequestProcessed(foldDir: File, requestId: String): Boolean {
        if (isRequestProcessed(sessionFoldProcessedRequestIds, requestId)) return true
        if (bridgeResultMatchesRequest(foldDir, "result", requestId)) {
            rememberRequestId(sessionFoldProcessedRequestIds, requestId)
            return true
        }
        return false
    }

    private suspend fun handleSessionFoldRequestContent(foldDir: File, content: String) {
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
                "timeline_collapse", "timeline_expand", "timeline_toggle" -> {
                    val collapsed = when (action) {
                        "timeline_collapse" -> true
                        "timeline_expand" -> false
                        else -> !terminalViewModel.sessionFoldTimelineCollapsed
                    }
                    terminalViewModel.updateSessionFoldTimelineCollapsed(collapsed)
                    val state = if (collapsed) "collapsed" else "expanded"
                    writeSessionFoldEvent(
                        type = "agent_timeline_$state",
                        state = state,
                        reason = reason,
                        requestId = requestId,
                        extra = mapOf("timeline_action" to action)
                    )
                    writeSessionFoldResult(
                        requestId = requestId,
                        action = action,
                        ok = true,
                        state = state,
                        reason = reason,
                        extra = mapOf("timeline_action" to action)
                    )
                    writeSessionFoldStatus(
                        state = state,
                        reason = reason,
                        requestId = requestId,
                        extra = mapOf("timeline_action" to action)
                    )
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
        val queueDir = browserDir.child("queue")
        val queuedRequests = withContext(Dispatchers.IO) {
            browserDir.mkdirs()
            queueDir.mkdirs()
            queueDir.listFiles()
                ?.filter { it.isFile && it.name.endsWith(".req") }
                ?.sortedBy { it.name }
                ?: emptyList()
        }
        for (file in queuedRequests) {
            var content = ""
            try {
                content = withContext(Dispatchers.IO) {
                    if (file.isFile) file.readText().trim() else ""
                }
                if (content.isNotBlank()) {
                    val requestId = panelRequestId(parseMediaPreviewRequest(content), content)
                    if (!isBrowserRequestProcessed(browserDir, requestId)) {
                        handleBrowserRequestContent(browserDir, content)
                    }
                }
            } catch (error: Exception) {
                val request = runCatching { parseMediaPreviewRequest(content) }.getOrDefault(emptyMap())
                writeBrowserBridgeError(
                    browserDir = browserDir,
                    requestId = if (content.isNotBlank()) {
                        panelRequestId(request, content)
                    } else {
                        file.name.removeSuffix(".req").ifBlank { "queue-${System.currentTimeMillis()}" }
                    },
                    action = request["action"].orEmpty().ifBlank { "queue" },
                    error = error
                )
            } finally {
                withContext(Dispatchers.IO) {
                    runCatching { file.delete() }
                }
            }
        }

        val content = withContext(Dispatchers.IO) {
            browserDir.mkdirs()
            if (requestFile.isFile) requestFile.readText() else ""
        }.trim()

        if (content.isBlank() || content == lastBrowserRequest) return
        val requestId = panelRequestId(parseMediaPreviewRequest(content), content)
        if (isBrowserRequestProcessed(browserDir, requestId)) {
            lastBrowserRequest = content
            return
        }
        lastBrowserRequest = content
        handleBrowserRequestContent(browserDir, content)
    }

    private fun writeBrowserBridgeError(
        browserDir: File,
        requestId: String,
        action: String,
        error: Throwable
    ) {
        val message = error.message ?: error::class.java.simpleName
        val result = JSONObject()
            .put("ok", false)
            .put("requestId", requestId)
            .put("action", action)
            .put("error", message)
            .put("snapshot", browserSnapshotJson(terminalViewModel.browserSnapshot))
        writeBrowserResult(browserDir, result)
        rememberBrowserRequestId(requestId)
        writeAgentPanelEvent(
            source = "browser",
            type = "agent_error",
            state = "error",
            reason = message,
            requestId = requestId,
            extra = browserSnapshotExtras(terminalViewModel.browserSnapshot)
        )
    }

    private fun browserSnapshotJson(snapshot: TerminalBrowserSnapshot): JSONObject {
        return JSONObject()
            .put("available", snapshot.available)
            .put("requestId", snapshot.requestId)
            .put("activeTabId", snapshot.activeTabId)
            .put("title", snapshot.title)
            .put("currentUrl", redactSensitiveUrl(snapshot.currentUrl))
            .put("isLoading", snapshot.isLoading)
            .put("status", snapshot.status)
            .put("message", snapshot.message)
            .put("needsUser", snapshot.needsUser)
            .put("lastError", snapshot.lastError)
            .put("riskChallengeDetected", snapshot.riskChallengeDetected)
            .put("riskChallengeKind", snapshot.riskChallengeKind)
            .put("recommendedNextAction", snapshot.recommendedNextAction)
            .put("valuesRedacted", true)
            .put("authTask", snapshot.authTask?.let {
                JSONObject()
                    .put("requestId", it.requestId)
                    .put("url", redactSensitiveUrl(it.url))
                    .put("reason", it.reason)
                    .put("code", redactAuthCode(it.code))
                    .put("state", it.state)
                    .put("userAction", it.userAction)
                    .put("active", it.active)
                    .put("valuesRedacted", true)
            })
            .put("externalPrompt", snapshot.externalPrompt?.let {
                JSONObject()
                    .put("requestId", it.requestId)
                    .put("target", redactSensitiveUrl(it.target))
                    .put("scheme", it.scheme)
                    .put("fallbackUrl", redactSensitiveUrl(it.fallbackUrl))
                    .put("kind", it.kind)
                    .put("valuesRedacted", true)
            })
            .put("tabs", JSONArray().apply {
                snapshot.tabs.forEach { tab ->
                    put(
                        JSONObject()
                            .put("id", tab.id)
                            .put("title", tab.title)
                            .put("url", redactSensitiveUrl(tab.url))
                            .put("isLoading", tab.isLoading)
                    )
                }
            })
    }

    private suspend fun handleBrowserRequestContent(browserDir: File, content: String) {
        val request = parseMediaPreviewRequest(content)
        val requestId = panelRequestId(request, content)
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
        if (effectiveAction in setOf("present", "user_wait", "auth_open", "auth_reopen") || request["present"] == "1") {
            terminalViewModel.mediaPreviewExpanded = false
            terminalViewModel.browserPanelExpanded = true
        }
        if (effectiveAction in setOf("collapse", "user_done", "user_cancelled", "auth_collapse", "auth_done", "auth_cancel", "auth_cancelled", "external_cancel", "close")) {
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
        val suppressPresent = action in setOf("collapse", "user_done", "user_cancelled", "auth_collapse", "auth_done", "auth_cancel", "auth_cancelled", "external_cancel", "close")
        val shouldPresent = !suppressPresent && (
            request["present"] == "1" ||
                action == "present" ||
                action == "user_wait" ||
                action == "auth_open" ||
                action == "auth_reopen" ||
                snapshot?.optBoolean("needsUser") == true
            )
        val shouldCollapse = action in setOf("collapse", "user_done", "user_cancelled", "auth_collapse", "auth_done", "auth_cancel", "auth_cancelled", "external_cancel")
        if (result.optBoolean("ok") && shouldCollapse) {
            terminalViewModel.browserPanelExpanded = false
        }
        if (result.optBoolean("ok") && shouldPresent) {
            terminalViewModel.mediaPreviewExpanded = false
            terminalViewModel.browserPanelExpanded = true
        }
        maybePushBrowserScreenshotToFiles(result, request)
        writeBrowserResult(browserDir, result)
        rememberBrowserRequestId(requestId)
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
            summary = redactSensitiveUrl(snapshot?.optString("currentUrl").orEmpty()).ifBlank { request["message"].orEmpty() },
            path = redactSensitiveUrl(snapshot?.optString("currentUrl").orEmpty()),
            status = state,
            itemId = result.optString("requestId").ifBlank { "browser-${System.currentTimeMillis()}" }
        )
    }

    private fun isBrowserRequestProcessed(browserDir: File, requestId: String): Boolean {
        if (isRequestProcessed(browserProcessedRequestIds, requestId)) return true
        if (browserRequestResultMatches(browserDir, requestId)) {
            rememberBrowserRequestId(requestId)
            return true
        }
        return false
    }

    private fun rememberBrowserRequestId(requestId: String) {
        rememberRequestId(browserProcessedRequestIds, requestId)
    }

    private suspend fun maybePushBrowserScreenshotToFiles(
        result: JSONObject,
        request: Map<String, String>
    ) {
        if (!result.optBoolean("ok")) return
        val data = result.optJSONObject("data") ?: return
        if (!data.optBoolean("pushToFiles")) return
        val path = data.optString("path")
        val file = File(path)
        val readable = withContext(Dispatchers.IO) { file.isFile && file.canRead() }
        if (!readable) return

        val previewDir = localDir().child("media-preview")
        val stamp = data.optString("fileId").ifBlank { result.optString("requestId") }
        val preview = TerminalMediaPreview(
            path = file.absolutePath,
            name = data.optString("name").ifBlank { file.name },
            kind = TerminalMediaPreviewKind.IMAGE,
            stamp = stamp,
            width = data.optInt("width").takeIf { it > 0 },
            height = data.optInt("height").takeIf { it > 0 },
            sizeBytes = data.optLong("bytes").takeIf { it > 0 } ?: file.length(),
            mimeType = "image/png"
        )
        addMediaPreviewWithCacheCleanup(preview)
        val refId = previewReferenceId(preview)
        withContext(Dispatchers.IO) {
            writePreviewReference(preview, refId)
        }
        val shouldPresent = data.optBoolean("presentFiles", true) && request["present_files"] != "0"
        if (shouldPresent) {
            terminalViewModel.browserPanelExpanded = false
            terminalViewModel.mediaPreviewExpanded = true
        }
        writeMediaPreviewStatus(
            previewDir,
            buildString {
                append("state=ready\n")
                append("reason=browser_screenshot\n")
                append("shown=1\n")
                append("request_id=").append(refValue(result.optString("requestId"))).append('\n')
                append("kind=image\n")
                append("path=").append(refValue(preview.path)).append('\n')
                append("name=").append(refValue(preview.name)).append('\n')
                append("stamp=").append(refValue(preview.stamp)).append('\n')
                append("item_id=").append(refId).append('\n')
            }
        )
        writeMediaPreviewResult(
            previewDir = previewDir,
            requestId = result.optString("requestId"),
            action = "browser_screenshot",
            ok = true,
            state = "ready",
            reason = "browser_screenshot",
            itemId = refId,
            extra = mediaPreviewExtras(preview)
        )
        writeAgentPanelEvent(
            source = "files",
            type = if (shouldPresent) "agent_presented" else "agent_added",
            state = "ready",
            reason = "browser_screenshot",
            requestId = result.optString("requestId"),
            itemId = refId,
            extra = mediaPreviewExtras(preview)
        )
        writeAgentPanelStatus(
            source = "files",
            state = "ready",
            reason = "browser_screenshot",
            requestId = result.optString("requestId"),
            itemId = refId,
            extra = mediaPreviewExtras(preview)
        )
        appendActiveSessionFoldItem(
            kind = TerminalSessionFoldItemKind.FILE,
            title = preview.name,
            summary = snapshotSummaryForBrowserScreenshot(result),
            path = preview.path,
            status = "ready",
            itemId = refId
        )
        data.put("fileId", refId)
    }

    private fun snapshotSummaryForBrowserScreenshot(result: JSONObject): String {
        val snapshot = result.optJSONObject("snapshot")
        return redactSensitiveUrl(snapshot?.optString("currentUrl").orEmpty())
            .ifBlank { snapshot?.optString("title").orEmpty() }
            .ifBlank { "浏览器截图" }
    }

    private suspend fun pollMediaPreviewRequest() {
        val previewDir = localDir().child("media-preview")
        val requestFile = previewDir.child("request")
        for (file in queuedRequestFiles(previewDir)) {
            val queuedContent = withContext(Dispatchers.IO) {
                if (file.isFile) file.readText().trim() else ""
            }
            if (queuedContent.isNotBlank()) {
                val queuedRequest = parseMediaPreviewRequest(queuedContent)
                val queuedRequestId = panelRequestId(queuedRequest, queuedContent)
                if (!isMediaPreviewRequestProcessed(previewDir, queuedRequestId)) {
                    handleMediaPreviewRequestContent(previewDir, queuedContent)
                    rememberRequestId(mediaPreviewProcessedRequestIds, queuedRequestId)
                }
            }
            withContext(Dispatchers.IO) { runCatching { file.delete() } }
        }

        val content = withContext(Dispatchers.IO) {
            previewDir.mkdirs()
            if (requestFile.isFile) requestFile.readText() else ""
        }.trim()

        if (content.isBlank() || content == lastMediaPreviewRequest) return
        val requestId = panelRequestId(parseMediaPreviewRequest(content), content)
        if (isMediaPreviewRequestProcessed(previewDir, requestId)) {
            lastMediaPreviewRequest = content
            return
        }
        lastMediaPreviewRequest = content
        handleMediaPreviewRequestContent(previewDir, content)
        rememberRequestId(mediaPreviewProcessedRequestIds, requestId)
    }

    private fun isMediaPreviewRequestProcessed(previewDir: File, requestId: String): Boolean {
        if (isRequestProcessed(mediaPreviewProcessedRequestIds, requestId)) return true
        if (bridgeResultMatchesRequest(previewDir, "result", requestId)) {
            rememberRequestId(mediaPreviewProcessedRequestIds, requestId)
            return true
        }
        return false
    }

    private suspend fun handleMediaPreviewRequestContent(previewDir: File, content: String) {
        val request = parseMediaPreviewRequest(content)
        val action = request["action"].orEmpty().ifBlank { "show" }
        val requestId = panelRequestId(request, content)
        val reason = request["reason"] ?: action
        if (action == "clear") {
            terminalViewModel.clearMediaPreviews()
            withContext(Dispatchers.IO) {
                clearAllMediaPreviewCache(previewDir)
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
                    if (terminalViewModel.mediaPreviews.lastOrNull() != selected) {
                        terminalViewModel.mediaPreviews.removeAll { it.stamp == selected.stamp }
                        terminalViewModel.mediaPreviews.add(selected)
                    }
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
                        deleteMediaPreviewCacheNow(selected)
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
            writeMediaPreviewStatus(previewDir, "error=unreadable\npath=${refValue(mediaPath)}\n")
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
                writeMediaPreviewStatus(previewDir, "error=unsupported-kind\npath=${refValue(mediaPath)}\n")
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
        addMediaPreviewWithCacheCleanup(preview)
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
        val ext = extensionFromMime(info.mimeType).ifBlank {
            sanitizeFileName(info.name).substringAfterLast('.', missingDelimiterValue = "").take(12)
        }.ifBlank { "bin" }
        val kindToken = when (kind) {
            TerminalMediaPreviewKind.IMAGE -> "img"
            TerminalMediaPreviewKind.VIDEO -> "vid"
            TerminalMediaPreviewKind.TEXT -> "txt"
        }
        // Disk cache: stamp + short type token only (no long original names).
        val target = mediaDir.child("$stamp-$kindToken.$ext")
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

        val displayIndex = terminalViewModel.mediaPreviews.count { it.kind == kind } + 1
        val displayName = shortPreviewDisplayName(
            TerminalMediaPreview(
                path = target.absolutePath,
                name = "",
                kind = kind,
                stamp = stamp
            ),
            displayIndex
        )
        val preview = TerminalMediaPreview(
            path = target.absolutePath,
            name = displayName,
            kind = kind,
            stamp = stamp,
            width = bounds?.first,
            height = bounds?.second,
            sizeBytes = info.sizeBytes?.takeIf { it >= 0 } ?: copiedBytes,
            mimeType = info.mimeType,
            textPreview = textPreview,
            source = TerminalMediaPreviewSource.USER
        )
        withContext(Dispatchers.IO) {
            writePreviewReference(preview, previewReferenceId(preview))
        }
        addMediaPreviewWithCacheCleanup(preview)
        writeAgentPanelEvent(
            source = "files",
            type = "user_selected_file",
            state = "ready",
            reason = "file_picker",
            itemId = stamp
        )
        writeMediaPreviewStatus(
            previewDir,
            "picked=1\nkind=${kind.name.lowercase(Locale.ROOT)}\npath=${refValue(target.absolutePath)}\n"
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
            val timestampMs = System.currentTimeMillis()
            val visible = terminalViewModel.mediaPreviewExpanded
            val existingKeys = bridgeTextKeys(text)
            val state = bridgeTextValue(text, "state").ifBlank { inferMediaPreviewState(text) }
            val needsUser = state == "waiting_for_user"
            val userAction = bridgeTextValue(text, "user_action")
            previewDir.child("status").writeText(
                buildString {
                    append(text)
                    if (!text.endsWith('\n')) append('\n')
                    appendBridgeFieldIfMissing(existingKeys, "source", "files")
                    appendBridgeFieldIfMissing(existingKeys, "mode", "files")
                    appendBridgeFieldIfMissing(existingKeys, "schema_version", BRIDGE_STATUS_SCHEMA_VERSION)
                    appendBridgeFieldIfMissing(existingKeys, "timestamp_ms", timestampMs.toString())
                    appendBridgeFieldIfMissing(existingKeys, "state", state)
                    appendBridgeFieldIfMissing(existingKeys, "needs_user", if (needsUser) "1" else "0")
                    appendBridgeFieldIfMissing(existingKeys, "user_action", userAction)
                    appendBridgeFieldIfMissing(existingKeys, "visible", if (visible) "1" else "0")
                    appendBridgeFieldIfMissing(existingKeys, "collapsed", if (visible) "0" else "1")
                }
            )
        } catch (_: Exception) {
            // Best-effort debug marker for terminal-side troubleshooting.
        }
    }

    private fun inferMediaPreviewState(text: String): String {
        return when {
            text.lineSequence().any { it.startsWith("error=") } -> "error"
            text.lineSequence().any { it == "closed=1" || it == "cleared=1" } -> "closed"
            text.lineSequence().any { it == "picked=1" || it == "shown=1" } -> "ready"
            else -> ""
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
            "auth_open" -> "auth_opened"
            "auth_reopen" -> "auth_reopened"
            "auth_done" -> "auth_done"
            "auth_collapse" -> "auth_collapsed"
            "auth_cancel", "auth_cancelled" -> "auth_cancelled"
            "external_confirm" -> "external_open_confirmed"
            "external_cancel" -> "external_open_cancelled"
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
            val timestampMs = System.currentTimeMillis()
            val visible = terminalViewModel.mediaPreviewExpanded
            val activeItem = terminalViewModel.mediaPreviews.lastOrNull()?.let { previewReferenceId(it) }.orEmpty()
            val extras = panelExtrasFor("files", itemId) + extra
            val needsUser = state == "waiting_for_user"
            val userAction = panelEventUserAction(action, extras)
            previewDir.child("result").writeText(
                buildString {
                    append("source=files\n")
                    append("mode=files\n")
                    append("schema_version=").append(BRIDGE_STATUS_SCHEMA_VERSION).append('\n')
                    append("timestamp_ms=").append(timestampMs).append('\n')
                    append("request_id=").append(refValue(requestId)).append('\n')
                    append("action=").append(refValue(action)).append('\n')
                    append("ok=").append(if (ok) "1" else "0").append('\n')
                    append("state=").append(refValue(state)).append('\n')
                    append("needs_user=").append(if (needsUser) "1" else "0").append('\n')
                    append("user_action=").append(refValue(userAction)).append('\n')
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
            val timestampMs = System.currentTimeMillis()
            val snapshot = result.optJSONObject("snapshot")
            val state = if (result.optBoolean("ok")) {
                snapshot?.optString("status")?.takeIf { it.isNotBlank() } ?: "done"
            } else {
                "error"
            }
            val visible = terminalViewModel.browserPanelExpanded
            val needsUser = snapshot?.optBoolean("needsUser") == true
            val activeItem = snapshot?.opt("activeTabId")?.toString().orEmpty()
            val tabsCount = (snapshot?.optJSONArray("tabs")?.length() ?: 0).toString()
            val requestId = result.optString("requestId")
            val authTask = snapshot?.optJSONObject("authTask")
            val externalPrompt = snapshot?.optJSONObject("externalPrompt")
            val userAction = result.optJSONObject("data")?.optString("userAction")
                ?.takeIf { it.isNotBlank() }
                ?: authTask?.optString("userAction").orEmpty()
            val persistedResult = sanitizeBrowserResult(result)
            persistedResult
                .put("source", "browser")
                .put("mode", "browser")
                .put("schemaVersion", BRIDGE_STATUS_SCHEMA_VERSION)
                .put("schema_version", BRIDGE_STATUS_SCHEMA_VERSION)
                .put("timestampMs", timestampMs)
                .put("timestamp_ms", timestampMs)
                .put("state", state)
                .put("visible", visible)
                .put("collapsed", !visible)
                .put("itemId", "")
                .put("activeItem", activeItem)
                .put("reason", result.optString("action"))
                .put("needsUser", needsUser)
                .put("needs_user", needsUser)
                .put("tabsCount", tabsCount)
                .put("userAction", userAction)
                .put("user_action", userAction)
            browserDir.child("result.json").writeText(persistedResult.toString(2))
            val requestResultsDir = browserDir.child("results").apply { mkdirs() }
            val text = buildString {
                append("source=browser\n")
                append("mode=browser\n")
                append("schema_version=").append(BRIDGE_STATUS_SCHEMA_VERSION).append('\n')
                append("timestamp_ms=").append(timestampMs).append('\n')
                append("request_id=").append(refValue(requestId)).append('\n')
                append("state=").append(refValue(state)).append('\n')
                append("action=").append(refValue(result.optString("action"))).append('\n')
                append("ok=").append(if (result.optBoolean("ok")) "1" else "0").append('\n')
                append("needs_user=").append(if (needsUser) "1" else "0").append('\n')
                append("visible=").append(if (visible) "1" else "0").append('\n')
                append("collapsed=").append(if (visible) "0" else "1").append('\n')
                append("item_id=\n")
                append("active_item=").append(refValue(activeItem)).append('\n')
                append("tab_id=").append(refValue(activeItem)).append('\n')
                append("tabs_count=").append(tabsCount).append('\n')
                append("url=").append(refValue(redactSensitiveUrl(snapshot?.optString("currentUrl").orEmpty()))).append('\n')
                append("title=").append(refValue(snapshot?.optString("title").orEmpty())).append('\n')
                append("user_action=").append(refValue(userAction)).append('\n')
                append("auth_request_id=").append(refValue(authTask?.optString("requestId").orEmpty())).append('\n')
                append("auth_state=").append(refValue(authTask?.optString("state").orEmpty())).append('\n')
                append("external_request_id=").append(refValue(externalPrompt?.optString("requestId").orEmpty())).append('\n')
                append("risk_challenge_detected=").append(if (snapshot?.optBoolean("riskChallengeDetected") == true) "1" else "0").append('\n')
                append("risk_challenge_kind=").append(refValue(snapshot?.optString("riskChallengeKind").orEmpty())).append('\n')
                append("recommended_next_action=").append(refValue(snapshot?.optString("recommendedNextAction").orEmpty())).append('\n')
                result.optString("error").takeIf { it.isNotBlank() && it != "null" }?.let {
                    append("error=").append(refValue(it)).append('\n')
                }
                result.optJSONObject("data")?.let { data ->
                    data.optString("authCode").takeIf { it.isNotBlank() }?.let {
                        append("auth_code=").append(refValue(redactAuthCode(it))).append('\n')
                    }
                    data.optString("path").takeIf { it.isNotBlank() }?.let {
                        append("path=").append(refValue(it)).append('\n')
                    }
                    data.optString("fileId").takeIf { it.isNotBlank() }?.let {
                        append("file_id=").append(refValue(it)).append('\n')
                    }
                    data.optInt("cookieCount", -1).takeIf { it >= 0 }?.let {
                        append("cookie_count=").append(it).append('\n')
                    }
                    data.optBoolean("verified", false).takeIf { it }?.let {
                        append("verified=1\n")
                    }
                }
            }
            browserDir.child("status").writeText(text)
            if (requestId.isNotBlank()) {
                val safeId = safeBridgeRequestId(requestId)
                if (safeId.isNotBlank()) {
                    requestResultsDir.child("$safeId.json").writeText(persistedResult.toString(2))
                    requestResultsDir.child("$safeId.status").writeText(text)
                }
            }
            browserDir.child("logs").mkdirs()
            browserDir.child("logs").child("session.log").appendText(
                "timestamp_ms=$timestampMs request_id=${refValue(requestId)} state=${refValue(state)} action=${refValue(result.optString("action"))} ok=${if (result.optBoolean("ok")) "1" else "0"}\n"
            )
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
