package com.rk.terminal.ui.activities.terminal

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.view.View
import android.view.inputmethod.InputMethodManager
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
import com.rk.terminal.ui.navHosts.MainActivityNavHost
import com.rk.terminal.ui.routes.MainActivityRoutes
import com.rk.terminal.ui.screens.terminal.TerminalMediaPreview
import com.rk.terminal.ui.screens.terminal.TerminalMediaPreviewKind
import com.rk.terminal.ui.screens.terminal.TerminalViewModel
import com.rk.terminal.ui.theme.KarbonTheme
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    val viewModel: MainViewModel by viewModels()
    private val terminalViewModel: TerminalViewModel by viewModels()
    private var isKeyboardVisible = false
    private var wasKeyboardOpen = false
    private var mediaPreviewJob: Job? = null
    private var lastMediaPreviewRequest = ""

    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { isGranted ->
            if (!isGranted) {
                // Optional: Handle permission denied
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        requestPermission()

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
        setupKeyboardListener()
    }

    override fun onStart() {
        super.onStart()
        viewModel.startAndBindService(this)
        startMediaPreviewBridge()
    }

    override fun onStop() {
        super.onStop()
        mediaPreviewJob?.cancel()
        mediaPreviewJob = null
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

    private fun primeMediaPreviewRequestCache() {
        lastMediaPreviewRequest = try {
            val requestFile = localDir().child("media-preview").child("request")
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

        terminalViewModel.addMediaPreview(
            TerminalMediaPreview(
                path = mediaFile.absolutePath,
                name = request["name"]?.takeIf { it.isNotBlank() } ?: mediaFile.name,
                kind = kind,
                stamp = request["stamp"] ?: content.hashCode().toString(),
                width = bounds?.first,
                height = bounds?.second
            )
        )
        writeMediaPreviewStatus(
            previewDir,
            "shown=1\nkind=${request["kind"]}\npath=${mediaFile.absolutePath}\n"
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
}
