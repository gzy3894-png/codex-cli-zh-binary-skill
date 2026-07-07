package com.rk.terminal.ui.screens.terminal

import android.content.Context
import androidx.compose.runtime.mutableStateOf
import com.rk.libcommons.child
import com.rk.libcommons.localDir
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

object Rootfs {
    private const val ARCHIVE_NAME = "alpine.tar.gz"
    private const val ARCHIVE_READY_MARKER = "alpine.tar.gz.ready"
    private const val ROOTFS_READY_MARKER = ".codex-rootfs-ready"
    private const val INSTALL_LOCK_DIR = "rootfs-install.lock"
    private const val INSTALL_LOCK_WAIT_MS = 120_000L
    private const val INSTALL_LOCK_RETRY_MS = 200L

    var isInstalled = mutableStateOf(false)

    fun checkInstallation(context: Context) {
        isInstalled.value = isRootfsInstalled(context)
    }

    fun isRootfsInstalled(context: Context): Boolean {
        val isExtracted = isExtractedRootfsPresent(context)
        val isArchivePresent = isArchiveReady(context)
        return isExtracted || isArchivePresent
    }

    fun prepareArchiveFromAsset(context: Context, assetName: String): File {
        val archive = archiveFile(context)
        if (isArchiveReady(context)) return archive

        return withInstallLock(context) {
            if (isArchiveReady(context)) return@withInstallLock archive

            val tmpFile = context.filesDir.child(
                "$ARCHIVE_NAME.tmp.${android.os.Process.myPid()}.${Thread.currentThread().id}"
            )
            tmpFile.delete()

            context.assets.open(assetName).use { input ->
                FileOutputStream(tmpFile).use { output ->
                    input.copyTo(output)
                    output.fd.sync()
                }
            }

            if (tmpFile.length() <= 0L) {
                tmpFile.delete()
                throw IOException("Rootfs archive asset is empty: $assetName")
            }

            archiveReadyMarker(context).delete()
            if (archive.exists() && !archive.delete()) {
                tmpFile.delete()
                throw IOException("Unable to replace rootfs archive: ${archive.absolutePath}")
            }
            if (!tmpFile.renameTo(archive)) {
                tmpFile.delete()
                throw IOException("Unable to install rootfs archive atomically: ${archive.absolutePath}")
            }
            archiveReadyMarker(context).writeText("${System.currentTimeMillis()}\n")
            archive
        }
    }

    private fun archiveFile(context: Context): File = context.filesDir.child(ARCHIVE_NAME)

    private fun archiveReadyMarker(context: Context): File = context.filesDir.child(ARCHIVE_READY_MARKER)

    private fun isArchiveReady(context: Context): Boolean {
        val archive = archiveFile(context)
        return archive.exists() && archive.length() > 0L && archiveReadyMarker(context).exists()
    }

    private fun isExtractedRootfsPresent(context: Context): Boolean {
        val alpineDir = context.localDir().child("alpine")
        val hasPayload = alpineDir.exists() &&
            (alpineDir.list()?.any { it != "root" && it != "tmp" && it != ROOTFS_READY_MARKER } == true)
        // Legacy installs may predate the marker; init-host backfills it before proot starts.
        return hasPayload
    }

    private fun <T> withInstallLock(context: Context, block: () -> T): T {
        val lockDir = context.filesDir.child(INSTALL_LOCK_DIR)
        val deadline = System.currentTimeMillis() + INSTALL_LOCK_WAIT_MS
        while (!lockDir.mkdir()) {
            if (isArchiveReady(context)) return block()
            if (System.currentTimeMillis() >= deadline) {
                throw IOException("Timed out waiting for rootfs install lock: ${lockDir.absolutePath}")
            }
            Thread.sleep(INSTALL_LOCK_RETRY_MS)
        }
        return try {
            block()
        } finally {
            lockDir.deleteRecursively()
        }
    }
}
