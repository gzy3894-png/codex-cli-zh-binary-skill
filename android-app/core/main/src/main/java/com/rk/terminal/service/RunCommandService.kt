package com.rk.terminal.service

import android.app.Service
import android.content.Intent
import android.os.IBinder

class RunCommandService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopSelf(startId)
        return START_NOT_STICKY
    }
}
