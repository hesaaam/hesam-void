package com.hesamvoid.vpn

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
import android.os.PowerManager

/**
 * Keeps the app's own process running while an SSH tunnel is active.
 *
 * The VPN interface lives in the engine's separate process, but the SSH
 * session runs in this process. Without a foreground service Android
 * freezes or kills this process a few seconds after the app leaves the
 * screen, and traffic stops while the VPN still looks connected.
 */
class SshKeepAliveService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "SSH tunnel"
        val notification = buildNotification(title)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "HesamVoid:SshTunnel",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        // Not restarted on its own: the tunnel cannot resume without the app.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    private fun buildNotification(title: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SSH tunnel",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while an SSH server carries your traffic"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
        val pending = open?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText("SSH tunnel is running")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setContentIntent(pending)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "ssh_tunnel"
        private const val NOTIFICATION_ID = 7307
        private const val ACTION_STOP = "com.hesamvoid.vpn.SSH_KEEPALIVE_STOP"
        private const val EXTRA_TITLE = "title"

        fun start(context: Context, title: String) {
            val intent = Intent(context, SshKeepAliveService::class.java)
                .putExtra(EXTRA_TITLE, title)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SshKeepAliveService::class.java))
        }
    }
}
