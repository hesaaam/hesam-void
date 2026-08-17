package com.hesamvoid.vpn

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val installedAppsChannel = "hesam_void/installed_apps"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installedAppsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchableApps" -> result.success(getLaunchableApps())
                    else -> result.notImplemented()
                }
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
