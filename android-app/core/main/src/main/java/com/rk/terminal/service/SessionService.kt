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
import android.system.Os
import android.system.OsConstants
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
import com.rk.terminal.ui.screens.terminal.PendingCommand
import com.termux.terminal.TerminalSession
import com.termux.terminal.TerminalSessionClient

class SessionService : Service() {
    private val sessions = hashMapOf<String, TerminalSession>()
    /** Hidden sessions waiting for a graceful process exit after UI removal. */
    private val retiringSessions = hashMapOf<String, TerminalSession>()
    private val lifecycleLock = Any()
    private val closingSessionIds = mutableSetOf<String>()
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
            workingMode: Int,
            pendingCommand: PendingCommand? = null,
        ): TerminalSession {
            // Restore/click races can request the same window twice. Reuse a
            // live PTY instead of tearing it down and recreating the native
            // object under an attached TerminalView.
            synchronized(lifecycleLock) {
                sessions[id]?.takeIf { it.isRunning }?.let { return it }
                sessions.remove(id)
                sessionList.remove(id)
            }
            cleanupSessionTempDir(id)
            val created = MkSession.createSession(
                context = this@SessionService,
                sessionClient = client,
                sessionId = id,
                workingMode = workingMode,
                pendingCommand = pendingCommand,
            )
            synchronized(lifecycleLock) {
                sessions[id] = created
                sessionList[id] = workingMode
            }
            return created.also {
                // Metadata only — does not alter PTY / env setup.
                SessionIsolationHooks.notifyCreated(id, workingMode)
                updateNotification()
            }
        }

        fun getSession(id: String): TerminalSession? = synchronized(lifecycleLock) {
            sessions[id]?.takeIf { it.isRunning }
        }

        /**
         * Close one terminal window (kill its PTY). Window lifecycle only —
         * not an agent-session delete. Safe to call from UI clicks.
         * @return next current window id, or null if none remain.
         */
        fun terminateSession(id: String): String? {
            return this@SessionService.terminateSession(id)
        }

        fun notifySessionFinished(id: String, session: TerminalSession) {
            this@SessionService.onSessionFinished(id, session)
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
        val dying = synchronized(lifecycleLock) {
            val snapshot = (sessions.toList() + retiringSessions.toList())
                .distinctBy { it.first }
            closingSessionIds.addAll(snapshot.map { it.first })
            sessions.clear()
            retiringSessions.clear()
            sessionList.clear()
            snapshot
        }
        currentSession.value = "" to com.rk.settings.Settings.working_Mode
        SessionIsolationHooks.ensureInit(this)
        if (clearRegistry) {
            SessionIsolationHooks.clearAll()
        } else SessionIsolation.saveNow()
        if (updateNotification) {
            updateNotification()
        }
        // Registry truth is already committed before native teardown. A
        // process-level SIGSEGV cannot be caught by runCatching, so keeping
        // this phase isolated is what prevents stale windows from returning.
        dying.forEach { (id, session) ->
            runCatching { session.finishIfRunning() }
            cleanupSessionTempDir(id)
        }
        synchronized(lifecycleLock) {
            closingSessionIds.clear()
        }
    }

    /**
     * Close a terminal window: drop live + label metadata, then stop its PTY.
     * Agent CLI history/UUID lives outside this map; closing a window must not
     * be treated as deleting a codex/claude conversation.
     *
     * Order is crash-critical for 2.5.0–2.5.4 legacy windows:
     * 1) Snapshot remaining + switch [currentSession]
     * 2) Remove from live maps so the drawer updates immediately
     * 3) Persist registry drop ([notifyTerminated]) BEFORE native PTY teardown
     * 4) Request graceful process exit; retain stubborn PTYs off-screen
     *
     * Older builds killed the PTY from the close click. Native teardown could
     * terminate the app process, so user-close no longer calls finishIfRunning.
     *
     * Always leaves [currentSession] pointing at a still-live id when any remain.
     * Avoids [stopSelf] on last-window close while UI may still be bound
     * (binder death mid-recompose was a crash path).
     * @return next current id, or null when no windows left.
     */
    private fun terminateSession(id: String): String? {
        if (SessionIsolation.record(id)?.role == com.rk.terminal.session.WindowRole.LAUNCHER) {
            return currentSession.value.first
        }
        val removal = synchronized(lifecycleLock) {
            if (id in closingSessionIds) return currentSession.value.first
            if (!sessionList.containsKey(id) && !sessions.containsKey(id)) return null
            closingSessionIds += id

            // Snapshot remaining before mutation so Compose readers never see
            // a half-removed map mid-click.
            val remainingBefore = sessionList.keys.filter { it != id }
            val nextCurrent = when {
                remainingBefore.isEmpty() -> null
                currentSession.value.first == id -> remainingBefore.last()
                sessionList.containsKey(currentSession.value.first) -> currentSession.value.first
                else -> remainingBefore.lastOrNull()
            }
            if (nextCurrent != null) {
                val mode = sessionList[nextCurrent] ?: com.rk.settings.Settings.working_Mode
                currentSession.value = nextCurrent to mode
            } else {
                currentSession.value = "" to com.rk.settings.Settings.working_Mode
            }
            val dying = sessions.remove(id)
            if (dying != null) retiringSessions[id] = dying
            sessionList.remove(id)
            nextCurrent to dying
        }

        val nextCurrent = removal.first
        val dying = removal.second

        // Persist chrome drop BEFORE native teardown: window drop before
        // touching native PTY teardown. This
        // survives a process-level SIGSEGV, which Kotlin cannot catch.
        runCatching { SessionIsolationHooks.notifyTerminated(id) }
        if (nextCurrent != null) {
            runCatching { SessionIsolationHooks.notifyCurrent(nextCurrent) }
        }
        runCatching { updateNotification() }

        // Never SIGKILL a user-closed PTY. On affected proot/PTY builds that
        // tears down the App process before Kotlin can catch anything. SIGTERM
        // lets the shell/agent unwind; stubborn sessions remain hidden until
        // process teardown instead of crashing the visible App.
        if (dying != null && dying.isRunning) {
            runCatching { Os.kill(dying.pid, OsConstants.SIGTERM) }
        } else {
            onSessionFinished(id, dying)
        }
        return nextCurrent
    }

    private fun onSessionFinished(id: String, finished: TerminalSession?) {
        synchronized(lifecycleLock) {
            val active = sessions[id]
            if (finished == null || active === finished) {
                sessions.remove(id)
                sessionList.remove(id)
            }
            val retiring = retiringSessions[id]
            if (finished == null || retiring === finished) {
                retiringSessions.remove(id)
            }
            closingSessionIds.remove(id)
        }
        cleanupSessionTempDir(id)
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
