package com.rk.terminal.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.annotation.RequiresApi
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.core.app.NotificationCompat
import com.rk.resources.drawables
import com.rk.resources.strings
import com.rk.terminal.session.SessionIsolation
import com.rk.terminal.session.SessionIsolationHooks
import com.rk.terminal.ui.activities.terminal.MainActivity
import com.rk.terminal.ui.screens.terminal.MkSession
import com.termux.terminal.TerminalSession
import com.termux.terminal.TerminalSessionClient

class SessionService : Service() {
    private val sessions = hashMapOf<String, TerminalSession>()
    val sessionList = mutableStateMapOf<String, Int>()
    var currentSession = mutableStateOf(Pair("main", com.rk.settings.Settings.working_Mode))

    inner class SessionBinder : Binder() {
        fun getService(): SessionService = this@SessionService

        fun terminateAllSessions() {
            // Binder API: wipe live PTYs and registry (same as notification EXIT).
            this@SessionService.terminateAllSessions(clearRegistry = true)
        }

        fun createSession(
            id: String,
            client: TerminalSessionClient,
            workingMode: Int
        ): TerminalSession {
            sessions[id]?.finishIfRunning()
            cleanupSessionTempDir(id)
            return MkSession.createSession(
                context = this@SessionService,
                sessionClient = client,
                sessionId = id,
                workingMode = workingMode
            ).also {
                sessions[id] = it
                sessionList[id] = workingMode
                // Metadata only — does not alter PTY / env setup.
                SessionIsolationHooks.notifyCreated(id, workingMode)
                updateNotification()
            }
        }

        fun getSession(id: String): TerminalSession? = sessions[id]

        /**
         * Close one terminal window (kill its PTY). Window lifecycle only —
         * not an agent-session delete. Safe to call from UI clicks.
         * @return next current window id, or null if none remain.
         */
        fun terminateSession(id: String): String? {
            return this@SessionService.terminateSession(id)
        }
    }

    private val binder = SessionBinder()
    private val notificationManager by lazy {
        getSystemService(NotificationManager::class.java)
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        // Process/service teardown: kill PTYs but keep isolation registry for cold restore.
        terminateAllSessions(updateNotification = false, clearRegistry = false)
        super.onDestroy()
    }

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannel()
        }
        val notification = createNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(1, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "ACTION_EXIT") {
            // User tapped EXIT: wipe tabs so next open does not resurrect them.
            terminateAllSessions(updateNotification = false, clearRegistry = true)
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    private fun terminateAllSessions(
        updateNotification: Boolean = true,
        clearRegistry: Boolean = false,
    ) {
        sessions.keys.toList().forEach { id ->
            sessions[id]?.finishIfRunning()
            cleanupSessionTempDir(id)
        }
        sessions.clear()
        sessionList.clear()
        SessionIsolationHooks.ensureInit(this)
        if (clearRegistry) {
            SessionIsolationHooks.clearAll()
        } else {
            // Keep registry so cold start can restore tabs after process death.
            SessionIsolation.saveNow()
        }
        if (updateNotification) {
            updateNotification()
        }
    }

    /**
     * Close a terminal window: stop its PTY and drop live + label metadata.
     * Agent CLI history/UUID lives outside this map; closing a window must not
     * be treated as deleting a codex/claude conversation.
     *
     * Always leaves [currentSession] pointing at a still-live id when any remain.
     * Avoids [stopSelf] on last-window close while UI may still be bound
     * (binder death mid-recompose was a crash path).
     * @return next current id, or null when no windows left.
     */
    private fun terminateSession(id: String): String? {
        return runCatching {
            sessions[id]?.let { session ->
                runCatching { session.finishIfRunning() }
            }
            sessions.remove(id)
            sessionList.remove(id)
            cleanupSessionTempDir(id)
            // Window chrome only — not agent-session lifecycle.
            runCatching { SessionIsolationHooks.notifyTerminated(id) }

            val remaining = sessionList.keys.toList()
            val nextCurrent = when {
                remaining.isEmpty() -> null
                currentSession.value.first == id -> remaining.last()
                sessionList.containsKey(currentSession.value.first) -> currentSession.value.first
                else -> remaining.last()
            }
            if (nextCurrent != null) {
                val mode = sessionList[nextCurrent] ?: com.rk.settings.Settings.working_Mode
                currentSession.value = nextCurrent to mode
                runCatching { SessionIsolationHooks.notifyCurrent(nextCurrent) }
                updateNotification()
            } else {
                currentSession.value = "main" to com.rk.settings.Settings.working_Mode
                updateNotification()
            }
            nextCurrent
        }.getOrElse {
            android.util.Log.e("SessionService", "terminateSession failed for $id", it)
            sessionList.keys.lastOrNull()
        }
    }

    private fun cleanupSessionTempDir(id: String) {
        runCatching {
            MkSession.sessionTempDir(this, id).takeIf { it.exists() }?.deleteRecursively()
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val exitIntent = Intent(this, SessionService::class.java).apply {
            action = "ACTION_EXIT"
        }
        val exitPendingIntent = PendingIntent.getService(
            this, 1, exitIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Codex for TUI")
            .setContentText(getNotificationContentText())
            .setSmallIcon(drawables.terminal)
            .setContentIntent(pendingIntent)
            .addAction(
                NotificationCompat.Action.Builder(
                    null,
                    "EXIT",
                    exitPendingIntent
                ).build()
            )
            .setOngoing(true)
            .build()
    }

    private val CHANNEL_ID = "session_service_channel"

    @RequiresApi(Build.VERSION_CODES.O)
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Session Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Notification for Terminal Service"
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun updateNotification() {
        val notification = createNotification()
        notificationManager.notify(1, notification)
    }

    private fun getNotificationContentText(): String {
        val count = sessions.size
        return if (count == 1) "1 session running" else "$count sessions running"
    }
}
