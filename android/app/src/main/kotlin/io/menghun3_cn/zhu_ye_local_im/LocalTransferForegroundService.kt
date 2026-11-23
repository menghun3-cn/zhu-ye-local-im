package io.menghun3_cn.zhu_ye_local_im

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
import androidx.core.app.ServiceCompat

/**
 * Keeps the process at foreground priority while the app is alive.
 *
 * The whole product runs in this one process: the UDP broadcast listener,
 * the TCP Sessions, and every Dart timer. Android freezes or kills a
 * backgrounded process, which is why switching to another app used to take
 * this Device offline. This service does nothing itself — it exists so the
 * process holding those sockets is not a candidate for reclamation.
 *
 * It is deliberately not sticky: if the system kills the process anyway, a
 * restarted service would come back with no Flutter engine and dead sockets,
 * which is a notification that lies. [onTaskRemoved] is the only graceful
 * exit — the user swiping the app away from recents is a deliberate "go
 * offline", so the service stops with it.
 */
class LocalTransferForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = CHANNEL_DESCRIPTION
                setShowBadge(false)
            },
        )
    }

    private fun buildNotification(): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val tap = launch?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(APP_NAME)
            .setContentText(NOTIFICATION_TEXT)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(tap)
            .build()
    }

    private companion object {
        const val CHANNEL_ID = "background_presence"
        const val CHANNEL_NAME = "后台保活"
        const val CHANNEL_DESCRIPTION = "应用在后台时保持局域网在线"
        const val NOTIFICATION_TEXT = "正在局域网中保持在线"
        const val NOTIFICATION_ID = 1
        // Matches android:label in the manifest — Android resources here carry
        // no translations, so the title is the same literal the launcher shows.
        const val APP_NAME = "竹叶局域网传输"
    }
}
