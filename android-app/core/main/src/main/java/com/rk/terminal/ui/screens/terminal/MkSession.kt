package com.rk.terminal.ui.screens.terminal

import android.content.Context
import com.rk.libcommons.alpineHomeDir
import com.rk.libcommons.child
import com.rk.libcommons.createFileIfNot
import com.rk.libcommons.localBinDir
import com.rk.libcommons.localDir
import com.rk.libcommons.localLibDir
import com.rk.settings.Settings
import com.rk.terminal.App.Companion.getTempDir
import com.rk.terminal.BuildConfig
import com.rk.terminal.ui.screens.settings.WorkingMode
import com.termux.terminal.TerminalEmulator
import com.termux.terminal.TerminalSession
import com.termux.terminal.TerminalSessionClient
import java.io.File
import java.security.MessageDigest

object MkSession {
    private val managedScripts = mapOf(
        "init-host.sh" to "init-host",
        "init.sh" to "init",
        "codex-apk-upgrade.sh" to "codex-apk-upgrade",
        "codex-for-tui-bootstrap.sh" to "codex-for-tui-bootstrap.sh",
        "codex-preview" to "codex-preview",
        "codex-push-image" to "codex-push-image",
        "codex-push-media" to "codex-push-media",
        "codex-browser" to "codex-browser",
        "codex-panel" to "codex-panel",
        "codex-session" to "codex-session",
        "codex-rtk" to "codex-rtk",
        "codex-context" to "codex-context",
        "codex-doctor" to "codex-doctor",
        "codex-clean" to "codex-clean",
        "codex-ops" to "codex-ops",
        "codex-ops-lib" to "codex-ops-lib",
        "codex-dev-transfer" to "codex-dev-transfer",
        "rtk" to "rtk",
    )
    private val obsoleteScripts = listOf(
        "install-reterminal-alpine.sh",
        "codex-local-resume.sh",
    )
    private val unsafeSessionIdChars = Regex("[^A-Za-z0-9._-]")
    // Avoid rewriting multi-MB assets (especially rtk) on every new session.
    private const val MANAGED_SCRIPTS_STAMP = ".managed-scripts-stamp"

    fun sanitizeSessionId(sessionId: String): String {
        val base = sessionId
            .trim()
            .replace(unsafeSessionIdChars, "_")
            .trim('.', '-', '_')
            .take(64)
            .ifBlank { "session" }
        return "$base-${sha256Prefix(sessionId)}"
    }

    fun sessionTempDir(context: Context, sessionId: String): File =
        getTempDir(context).child(sanitizeSessionId(sessionId))

    private fun Context.appVersionFields(): Pair<Long, String> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code =
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
        val name = info.versionName ?: "unknown"
        return code to name
    }

    private fun Context.managedScriptsStampValue(): String {
        val (code, name) = appVersionFields()
        return "versionCode=$code\nversionName=$name\ncount=${managedScripts.size}\n"
    }

    private fun Context.syncManagedScripts() {
        val binDir = localBinDir()
        obsoleteScripts.forEach { outputName ->
            binDir.child(outputName).delete()
        }

        val stampFile = binDir.child(MANAGED_SCRIPTS_STAMP)
        val expectedStamp = managedScriptsStampValue()
        val stampMatches = stampFile.exists() &&
            runCatching { stampFile.readText() }.getOrNull() == expectedStamp
        val missingOrUnusable = managedScripts.values.any { outputName ->
            val file = binDir.child(outputName)
            !file.exists() || !file.canExecute() || file.length() <= 0L
        }

        // Fast path: same app version and all managed binaries still present.
        if (stampMatches && !missingOrUnusable) {
            return
        }

        managedScripts.forEach { (assetName, outputName) ->
            val dest = binDir.child(outputName)
            // Skip rewrite when the on-disk file already matches the packaged asset size.
            // rtk alone is ~6.7MB; rewriting it every session makes the first frame blank.
            val assetLength = runCatching {
                assets.openFd(assetName).use { it.length }
            }.getOrElse {
                // Compressed assets may not support openFd; fall back to a full rewrite.
                -1L
            }
            if (
                dest.exists() &&
                dest.canExecute() &&
                assetLength > 0L &&
                dest.length() == assetLength
            ) {
                return@forEach
            }
            dest.createFileIfNot()
            assets.open(assetName).use { input ->
                dest.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            dest.setExecutable(true, false)
        }

        stampFile.writeText(expectedStamp)
    }

    fun createSession(
        context: Context,
        sessionClient: TerminalSessionClient,
        sessionId: String,
        workingMode: Int,
        pendingCommand: PendingCommand? = null
    ): TerminalSession {
        with(context) {
            val envVariables = mapOf(
                "ANDROID_ART_ROOT" to System.getenv("ANDROID_ART_ROOT"),
                "ANDROID_DATA" to System.getenv("ANDROID_DATA"),
                "ANDROID_I18N_ROOT" to System.getenv("ANDROID_I18N_ROOT"),
                "ANDROID_ROOT" to System.getenv("ANDROID_ROOT"),
                "ANDROID_RUNTIME_ROOT" to System.getenv("ANDROID_RUNTIME_ROOT"),
                "ANDROID_TZDATA_ROOT" to System.getenv("ANDROID_TZDATA_ROOT"),
                "BOOTCLASSPATH" to System.getenv("BOOTCLASSPATH"),
                "DEX2OATBOOTCLASSPATH" to System.getenv("DEX2OATBOOTCLASSPATH"),
                "EXTERNAL_STORAGE" to System.getenv("EXTERNAL_STORAGE")
            )

            val workingDir = pendingCommand?.workingDir ?: alpineHomeDir().path

            syncManagedScripts()
            val initFile: File = localBinDir().child("init-host")

            val env = mutableListOf(
                "PATH=${System.getenv("PATH")}:/sbin:${localBinDir().absolutePath}",
                "HOME=/root",
                "CODEX_HOME=/root/.codex",
                // Shell-first by default; Settings can re-enable auto Codex start.
                "CODEX_FOR_TUI_AUTO_START=${if (Settings.auto_start_codex) "1" else "0"}",
                // Dedicated workspace avoids treating $HOME/.codex as project-local config.
                "CODEX_FOR_TUI_WORKSPACE=/root/workspace",
                "PUBLIC_HOME=${getExternalFilesDir(null)?.absolutePath}",
                "COLORTERM=truecolor",
                "TERM=xterm-256color",
                "LANG=C.UTF-8",
                "BIN=${localBinDir()}",
                "DEBUG=${BuildConfig.DEBUG}",
                "PREFIX=${filesDir.parentFile!!.path}",
                "LD_LIBRARY_PATH=${localLibDir().absolutePath}",
                "LINKER=${if (File("/system/bin/linker64").exists()) "/system/bin/linker64" else "/system/bin/linker"}",
                "NATIVE_LIB_DIR=${applicationInfo.nativeLibraryDir}",
                "PKG=${packageName}",
                "RISH_APPLICATION_ID=${packageName}",
                "PKG_PATH=${applicationInfo.sourceDir}",
                // Keep proot private tmp under localDir so App temp cleanup cannot wipe it mid-session.
                "PROOT_TMP_DIR=${localDir().child("proot-tmp").child(sanitizeSessionId(sessionId)).also { if (it.exists().not()) it.mkdirs() }.absolutePath}",
                "TMPDIR=${getTempDir(this).absolutePath}",
                "PROOT_LOADER=${applicationInfo.nativeLibraryDir}/libloader.so",
                "PROOT=${applicationInfo.nativeLibraryDir}/libproot.so",
            )

            val loader32 = "${applicationInfo.nativeLibraryDir}/libloader32.so"
            if (File(loader32).exists()) {
                env.add("PROOT_LOADER_32=$loader32")
            }

            env.addAll(envVariables.map { "${it.key}=${it.value}" })

            localDir().child("stat").apply {
                if (exists().not()) {
                    writeText(TerminalUtils.stat)
                }
            }

            localDir().child("vmstat").apply {
                if (exists().not()) {
                    writeText(TerminalUtils.vmstat)
                }
            }

            pendingCommand?.env?.let {
                env.addAll(it)
            }

            val args: Array<String>
            val shell = if (pendingCommand == null) {
                args = if (workingMode == WorkingMode.ALPINE) {
                    arrayOf("-c", initFile.absolutePath)
                } else {
                    arrayOf()
                }
                "/system/bin/sh"
            } else {
                args = pendingCommand.args
                pendingCommand.shell
            }

            return TerminalSession(
                shell,
                workingDir,
                args,
                env.toTypedArray(),
                TerminalEmulator.DEFAULT_TERMINAL_TRANSCRIPT_ROWS,
                sessionClient,
            )
        }
    }

    private fun sha256Prefix(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        return digest.take(6).joinToString(separator = "") { "%02x".format(it.toInt() and 0xff) }
    }
}

data class PendingCommand(
    val shell: String,
    val args: Array<String>,
    val workingDir: String?,
    val env: List<String>?
)
