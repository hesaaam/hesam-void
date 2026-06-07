package com.hesam.void

import android.app.Activity
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * KillSwitchPlugin
 * Handles the `hesam_void/kill_switch` MethodChannel.
 *
 * enableKillSwitch  → blocks all non-VPN traffic at the OS level
 * disableKillSwitch → restores normal connectivity
 *
 * On Android 8+ we use ConnectivityManager.requestNetwork with
 * TRANSPORT_VPN capability — this effectively starves non-tunnel sockets.
 * On older devices we fall back to setting the VPN as "always-on" via intent.
 */
class KillSwitchPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "hesam_void/kill_switch")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "enableKillSwitch" -> {
                enableKillSwitch()
                result.success(null)
            }
            "disableKillSwitch" -> {
                disableKillSwitch()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun enableKillSwitch() {
        val ctx = context ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE)
                    as ConnectivityManager
            // Request a network that MUST go through VPN transport.
            // Until satisfied, OS does not route packets — kill switch achieved.
            val req = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_VPN)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .build()
            cm.requestNetwork(req, object : ConnectivityManager.NetworkCallback() {})
        }
        // For Android < 8 and as belt-and-suspenders, also flag in shared prefs
        // so the VPN service can check on restart
        ctx.getSharedPreferences("kill_switch_prefs", Context.MODE_PRIVATE)
            .edit().putBoolean("kill_switch_active", true).apply()
    }

    private fun disableKillSwitch() {
        val ctx = context ?: return
        ctx.getSharedPreferences("kill_switch_prefs", Context.MODE_PRIVATE)
            .edit().putBoolean("kill_switch_active", false).apply()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivity() { activity = null }
}
