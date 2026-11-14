package com.hesamvoid.vpn

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import java.io.ByteArrayOutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val installedAppsChannel = "hesam_void/installed_apps"
    private val appUsageChannel = "hesam_void/app_usage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installedAppsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchableApps" -> result.success(getLaunchableApps())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUsageChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAccess" -> result.success(hasUsageAccess())
                    "openSettings" -> {
                        openUsageAccessSettings()
                        result.success(null)
                    }
                    "foregroundTime" -> {
                        val intervals = call.argument<List<List<Number>>>("intervals") ?: emptyList()
                        Thread {
                            try {
                                val usage = foregroundTime(intervals)
                                runOnUiThread { result.success(usage) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("usage", error.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageAccessSettings() {
        val withPackage = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
        }
        try {
            startActivity(withPackage)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
            } catch (_: Exception) {
                // No usage access screen on this device.
            }
        }
    }

    /**
     * Foreground time per app, counted only inside the given protected
     * intervals (epoch millis). Built from Android's own usage events.
     */
    private fun foregroundTime(intervals: List<List<Number>>): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) return emptyList()
        val spans = intervals
            .filter { it.size >= 2 }
            .map { Pair(it[0].toLong(), it[1].toLong()) }
            .filter { it.second > it.first }
        if (spans.isEmpty()) return emptyList()

        val begin = spans.minOf { it.first }
        val end = spans.maxOf { it.second }
        val usageStats = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        // Start earlier so apps already open when a session began are found.
        val events = usageStats.queryEvents(begin - 6 * 60 * 60 * 1000L, end)
        val event = UsageEvents.Event()
        val openSince = HashMap<String, Long>()
        val totals = HashMap<String, Long>()

        fun add(pkg: String, from: Long, to: Long) {
            for (span in spans) {
                val overlap = minOf(to, span.second) - maxOf(from, span.first)
                if (overlap > 0) totals[pkg] = (totals[pkg] ?: 0L) + overlap
            }
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            val time = event.timeStamp
            when (event.eventType) {
                // MOVE_TO_FOREGROUND / ACTIVITY_RESUMED
                1 -> openSince[pkg] = time
                // MOVE_TO_BACKGROUND / ACTIVITY_PAUSED, ACTIVITY_STOPPED
                2, 23 -> openSince.remove(pkg)?.let { add(pkg, it, time) }
                // SCREEN_NON_INTERACTIVE: nothing is really in use.
                16 -> {
                    openSince.forEach { (open, from) -> add(open, from, time) }
                    openSince.clear()
                }
            }
        }
        openSince.forEach { (pkg, from) -> add(pkg, from, end) }

        val home = homePackage()
        return totals
            .filter { (pkg, ms) -> pkg != packageName && pkg != home && ms >= 60_000L }
            .entries
            .sortedByDescending { it.value }
            .take(12)
            .map { (pkg, ms) ->
                mapOf(
                    "packageName" to pkg,
                    "appName" to appLabel(pkg),
                    "ms" to ms,
                    "icon" to appIcon(pkg)
                )
            }
    }

    private fun homePackage(): String? {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return try {
            packageManager.resolveActivity(intent, 0)?.activityInfo?.packageName
        } catch (_: Exception) {
            null
        }
    }

    private fun appLabel(pkg: String): String {
        return try {
            val info = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            pkg
        }
    }

    private fun appIcon(pkg: String): ByteArray? {
        return try {
            val drawable = packageManager.getApplicationIcon(pkg)
            val size = 96
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        } catch (_: Exception) {
            null
        }
    }

    private fun getLaunchableApps(): List<Map<String, Any>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val packageManager = packageManager
        val resolveInfos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.ResolveInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launcherIntent, 0)
        }

        return resolveInfos
            .asSequence()
            .map { it.activityInfo.applicationInfo }
            .filter { it.packageName != packageName }
            .distinctBy { it.packageName }
            .map { appInfo ->
                val isSystem = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                mapOf(
                    "packageName" to appInfo.packageName,
                    "appName" to packageManager.getApplicationLabel(appInfo).toString(),
                    "isSystemApp" to isSystem
                )
            }
            .sortedWith(compareBy<Map<String, Any>> { it["isSystemApp"] as Boolean }
                .thenBy { (it["appName"] as String).lowercase() })
            .toList()
    }
}
