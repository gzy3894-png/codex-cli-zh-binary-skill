package com.rk.update

import android.content.Context
import com.rk.libcommons.child
import com.rk.libcommons.createFileIfNot
import com.rk.libcommons.localBinDir
import java.io.File

class UpdateManager(private val context: Context) {
    fun onUpdate() {
        with(context) {
            mapOf(
                "init-host.sh" to "init-host",
                "init.sh" to "init",
                "codex-for-tui-bootstrap.sh" to "codex-for-tui-bootstrap.sh",
                "install-reterminal-alpine.sh" to "install-reterminal-alpine.sh",
                "codex-local-resume.sh" to "codex-local-resume.sh",
            ).forEach { (assetName, outputName) ->
                val file: File = localBinDir().child(outputName)
                file.createFileIfNot()
                assets.open(assetName).bufferedReader().use { it.readText() }.let {
                    file.writeText(it)
                }
                file.setExecutable(true, false)
            }
        }
    }
}
