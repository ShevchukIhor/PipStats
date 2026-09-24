package com.pipstats.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import android.util.Log

class ForegroundService : Service() {

    private val TAG = "ForegroundService"
    private val CHANNEL_ID = "device_stats_foreground"
    private val NOTIFICATION_ID = 1001
    /** Wall-clock start, used as the chronometer base. 0 until first start. */
    private var startTime: Long = 0

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Device Stats Monitoring",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background monitoring of battery and app usage"
                enableVibration(false)
                setSound(null, null)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, ForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PipStats")
            .setContentText("Monitoring battery & app usage")
            // The elapsed time is drawn by the system from this base, so the
            // notification no longer has to be rebuilt once a second just to
            // tick a counter — that was 86,400 CPU wake-ups a day inside an
            // app whose whole purpose is measuring battery drain.
            .setUsesChronometer(true)
            .setWhen(startTime)
            .setShowWhen(true)
            .setSmallIcon(R.drawable.ic_stat_monitor)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop Monitoring",
                    stopPendingIntent
                ).build()
            )
            .build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // The stop action and ForegroundService.stop() both send this, but the
        // action was never read: every stop request restarted the service
        // instead, so the notification's "Stop" button could not stop anything.
        if (intent?.action == ACTION_STOP) {
            isRunning = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        // Keep the original start time across re-deliveries (START_STICKY
        // restarts, boot, repeated start calls) so the chronometer shows how
        // long monitoring has really been up, not time since the last restart.
        if (startTime == 0L) {
            startTime = System.currentTimeMillis()
        }

        val notification = buildNotification()
        // Any startForeground can be refused — the system may deny a start
        // from the background, and a refusal throws. Letting it propagate
        // killed the app outright, which is how the dataSync time limit
        // surfaced: a crash rather than a service that quietly stopped.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isRunning = true
        } catch (e: Exception) {
            Log.w(TAG, "startForeground refused: ${e.message}")
            isRunning = false
            stopSelf()
            // Collection continues through the AlarmManager receiver, which
            // reads UsageStatsManager retroactively and needs no service.
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_STOP = "com.pipstats.app.STOP_SERVICE"

        /** Set while the service is live, so the UI can show its real state. */
        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, ForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, ForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}