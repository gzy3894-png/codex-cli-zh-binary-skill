package com.rk.crashhandler

import com.rk.libcommons.application
import com.rk.libcommons.child
import com.rk.libcommons.createFileIfNot
import java.io.PrintWriter
import java.io.StringWriter
import kotlin.system.exitProcess

object CrashHandler : Thread.UncaughtExceptionHandler {
    @Volatile
    private var previousHandler: Thread.UncaughtExceptionHandler? = null

    fun install() {
        val current = Thread.getDefaultUncaughtExceptionHandler()
        if (current === this) return
        previousHandler = current
        Thread.setDefaultUncaughtExceptionHandler(this)
    }

    override fun uncaughtException(thread: Thread, ex: Throwable) {
        logErrorOrExit(ex)
        previousHandler?.takeIf { it !== this }?.uncaughtException(thread, ex) ?: exitProcess(1)
    }
}

fun logErrorOrExit(throwable: Throwable){
    runCatching {
        val app = application ?: return@runCatching
        val stackTrace = StringWriter().also { writer ->
            throwable.printStackTrace(PrintWriter(writer))
        }.toString()
        app.filesDir.child("crash.log").createFileIfNot()
            .appendText("\n${System.currentTimeMillis()}\n$stackTrace")
    }.onFailure { it.printStackTrace() }
}
