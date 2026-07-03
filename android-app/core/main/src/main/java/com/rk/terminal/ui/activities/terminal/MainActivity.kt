package com.rk.terminal.ui.activities.terminal

import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
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
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.rk.libcommons.child
import com.rk.libcommons.localDir
import com.rk.terminal.ui.navHosts.MainActivityNavHost
import com.rk.terminal.ui.routes.MainActivityRoutes
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
    private var imagePreviewJob: Job? = null
    private var lastImagePreviewRequest = ""

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
        
        setupKeyboardListener()
    }

    override fun onStart() {
        super.onStart()
        viewModel.startAndBindService(this)
        startImagePreviewBridge()
    }

    override fun onStop() {
        super.onStop()
        imagePreviewJob?.cancel()
        imagePreviewJob = null
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
            pollImagePreviewRequest()
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

    private fun startImagePreviewBridge() {
        if (imagePreviewJob?.isActive == true) return
        imagePreviewJob = lifecycleScope.launch {
            while (isActive) {
                pollImagePreviewRequest()
                delay(500)
            }
        }
    }

    private suspend fun pollImagePreviewRequest() {
        val previewDir = localDir().child("image-preview")
        val requestFile = previewDir.child("request")
        val content = withContext(Dispatchers.IO) {
            previewDir.mkdirs()
            if (requestFile.isFile) requestFile.readText() else ""
        }.trim()

        if (content.isBlank() || content == lastImagePreviewRequest) return
        lastImagePreviewRequest = content

        val imagePath = parseImagePreviewPath(content)
        if (imagePath == null) {
            writeImagePreviewStatus(previewDir, "error=missing-path\n")
            return
        }

        val imageFile = File(imagePath)
        val canRead = withContext(Dispatchers.IO) {
            imageFile.isFile && imageFile.canRead()
        }
        if (!canRead) {
            writeImagePreviewStatus(previewDir, "error=unreadable\npath=$imagePath\n")
            return
        }

        writeImagePreviewStatus(previewDir, "seen=1\npath=$imagePath\n")
        showImagePreview(imageFile, previewDir)
    }

    private fun parseImagePreviewPath(content: String): String? {
        for (line in content.lineSequence()) {
            if (line.startsWith("path=")) {
                return line.removePrefix("path=").trim().takeIf { it.isNotEmpty() }
            }
        }
        return content.lineSequence().firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
    }

    private suspend fun showImagePreview(file: File, previewDir: File) {
        val bitmap = withContext(Dispatchers.IO) { loadPreviewBitmap(file) }
        if (isFinishing || isDestroyed) return

        val contentView: View = if (bitmap == null) {
            TextView(this).apply {
                text = "无法打开图片"
                setPadding(dp(24), dp(16), dp(24), dp(8))
            }
        } else {
            ImageView(this).apply {
                setImageBitmap(bitmap)
                adjustViewBounds = true
                scaleType = ImageView.ScaleType.FIT_CENTER
                setPadding(dp(12), dp(8), dp(12), dp(8))
            }
        }

        val contentHeight = if (bitmap == null) {
            ViewGroup.LayoutParams.WRAP_CONTENT
        } else {
            (resources.displayMetrics.heightPixels * 0.68f).toInt()
        }

        val container = FrameLayout(this).apply {
            addView(
                contentView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    contentHeight
                )
            )
        }

        MaterialAlertDialogBuilder(this)
            .setTitle(file.name)
            .setView(container)
            .setPositiveButton("关闭", null)
            .show()

        writeImagePreviewStatus(previewDir, "shown=1\npath=${file.absolutePath}\n")
    }

    private fun loadPreviewBitmap(file: File): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sampleSize = 1
        while (bounds.outWidth / sampleSize > 2048 || bounds.outHeight / sampleSize > 2048) {
            sampleSize *= 2
        }

        return BitmapFactory.decodeFile(
            file.absolutePath,
            BitmapFactory.Options().apply { inSampleSize = sampleSize }
        )
    }

    private fun writeImagePreviewStatus(previewDir: File, text: String) {
        try {
            previewDir.mkdirs()
            previewDir.child("status").writeText(text)
        } catch (_: Exception) {
            // Best-effort debug marker for terminal-side troubleshooting.
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
