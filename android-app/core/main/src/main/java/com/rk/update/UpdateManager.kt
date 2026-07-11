package com.rk.update

import android.content.Context
import com.rk.libcommons.child
import com.rk.libcommons.createFileIfNot
import com.rk.libcommons.localBinDir
import com.rk.terminal.BuildConfig
import java.io.File

class UpdateManager(private val context: Context) {
    private val criticalScripts = mapOf(
        "init-host.sh" to "init-host",
        "init.sh" to "init",
        "codex-apk-upgrade.sh" to "codex-apk-upgrade",
        "codex-for-tui-bootstrap.sh" to "codex-for-tui-bootstrap.sh",
    )
    private val obsoleteScripts = listOf(
        "install-reterminal-alpine.sh",
        "codex-local-resume.sh",
    )
    private val stampName = ".update-manager-stamp"

    fun onUpdate() {
        with(context) {
            val binDir = localBinDir()
            obsoleteScripts.forEach { outputName ->
                binDir.child(outputName).delete()
            }

            val stampFile = binDir.child(stampName)
            val expected =
                "versionCode=${BuildConfig.VERSION_CODE}\nversionName=${BuildConfig.VERSION_NAME}\n"
            val stampMatches = stampFile.exists() &&
                runCatching { stampFile.readText() }.getOrNull() == expected
            val missing = criticalScripts.values.any { name ->
                val file = binDir.child(name)
                !file.exists() || !file.canExecute() || file.length() <= 0L
            }
            if (stampMatches && !missing) {
                return
            }

            criticalScripts.forEach { (assetName, outputName) ->
                val file: File = binDir.child(outputName)
                file.createFileIfNot()
                assets.open(assetName).use { input ->
                    file.outputStream().use { output -> input.copyTo(output) }
                }
                file.setExecutable(true, false)
            }
            stampFile.writeText(expected)
        }
    }
}
