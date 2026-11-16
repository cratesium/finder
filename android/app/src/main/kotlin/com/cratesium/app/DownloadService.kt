package com.cratesium.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service that keeps the app process (and with it yt-dlp and the
 * Dart download queue) alive while downloads are active or waiting.
 *
 * It owns no work itself: [Toolchain] runs the processes and Dart reports the
 * queue state through [updateStatus]. The service stops itself shortly after
 * nothing is running or waiting.
 */
class DownloadService : Service() {

    /** Queue state reported by Dart (`setForegroundStatus`). */
    data class Status(
        val active: Int = 0,
        val queued: Int = 0,
        val title: String? = null,
        val progress: Double? = null,
        val completed: Int = 0,
        val total: Int = 0,
    ) {
        val pending: Int get() = active + queued
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL_ALL) {
            cancelAll()
            return START_NOT_STICKY
        }
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(this),
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0,
            )
        } catch (e: Exception) {
            // e.g. ForegroundServiceStartNotAllowedException: downloads still run
            // while the process lives; they just aren't protected from being killed.
            Log.w(TAG, "could not enter the foreground: $e")
            stopSelf()
        }
        scheduleStopCheck()
        // If the process is killed, Dart's state is gone too; restarting the
        // service alone would be pointless.
        return START_NOT_STICKY
    }

    /** Android 15+: dataSync services get a daily time budget. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "foreground time limit reached")
        stopSelf()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        main.removeCallbacks(stopCheck)
        super.onDestroy()
    }

    private fun cancelAll() {
        if (Toolchain.listener != null) {
            // Dart cancels each task properly (removes partial files, updates history).
            Toolchain.emit(mapOf("type" to "cancelAll"))
            // Fallback in case the Dart side doesn't react.
            main.postDelayed({ Toolchain.stopAll() }, 5000)
        } else {
            Toolchain.stopAll()
        }
    }

    private fun scheduleStopCheck() {
        main.removeCallbacks(stopCheck)
        main.postDelayed(stopCheck, STOP_GRACE_MS)
    }

    private val stopCheck = Runnable {
        if (!shouldRun()) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    companion object {
        private const val TAG = "DownloadService"
        private const val CHANNEL_ID = "transfers"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_CANCEL_ALL = "com.cratesium.app.CANCEL_ALL"

        /** Waiting a moment avoids stop/start churn between consecutive queue items. */
        private const val STOP_GRACE_MS = 4000L

        private val main = Handler(Looper.getMainLooper())

        @Volatile private var instance: DownloadService? = null

        @Volatile var status = Status()
            private set

        private fun shouldRun() = Toolchain.runningCount > 0 || status.pending > 0

        fun updateStatus(context: Context, next: Status) {
            status = next
            sync(context)
        }

        /** Starts, refreshes or (after a grace period) stops the service. Main thread. */
        fun sync(context: Context) {
            val service = instance
            if (shouldRun()) {
                if (service == null) {
                    try {
                        ContextCompat.startForegroundService(context, Intent(context, DownloadService::class.java))
                    } catch (e: Exception) {
                        // Android 12+ refuses to start foreground services from the
                        // background. The service is kept running across queue items,
                        // so this only happens if the queue was idle.
                        Log.w(TAG, "could not start foreground service: $e")
                    }
                } else {
                    service.refresh()
                    service.scheduleStopCheck()
                }
            } else {
                service?.scheduleStopCheck()
            }
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Active downloads", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Progress of downloads running in the background"
                    setShowBadge(false)
                },
            )
        }

        fun buildNotification(context: Context): Notification {
            ensureChannel(context)
            val s = status
            val active = maxOf(s.active, Toolchain.runningCount)
            val title = when {
                active == 0 && s.queued > 0 -> "${s.queued} waiting"
                active == 1 -> "Downloading 1 video"
                else -> "Downloading $active videos"
            } + if (s.queued > 0 && active > 0) " · ${s.queued} waiting" else ""

            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val contentIntent = open?.let {
                PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            }
            val cancelIntent = PendingIntent.getService(
                context,
                1,
                Intent(context, DownloadService::class.java).setAction(ACTION_CANCEL_ALL),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_finder)
                .setColor(ContextCompat.getColor(context, R.color.brand_ink))
                .setContentTitle(title)
                .setContentText(s.title ?: "Finder")
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setContentIntent(contentIntent)
                .addAction(0, "Cancel all", cancelIntent)
            if (s.total > 1) builder.setSubText("${s.completed} of ${s.total} done")
            val p = s.progress
            if (p == null) {
                builder.setProgress(0, 0, active > 0)
            } else {
                builder.setProgress(1000, (p.coerceIn(0.0, 1.0) * 1000).toInt(), false)
            }
            return builder.build()
        }
    }

    private fun refresh() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return // the service still runs; the notification is just hidden
        }
        try {
            NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, buildNotification(this))
        } catch (e: SecurityException) {
            Log.w(TAG, "notification update refused: $e")
        }
    }
}
